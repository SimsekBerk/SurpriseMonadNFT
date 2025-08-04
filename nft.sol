// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ───────────────────────────── Import Stack ───────────────────────────── */
import "@openzeppelin/contracts/token/ERC721/extensions/ERC4907.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/* ═══════════════════════  SurpriseMonadNFT v2  ════════════════════════ */
/**
 * Adds:
 * 1.  Sale phases (Closed ▸ PreSale ▸ PublicSale) + Merkle allow-list mint
 * 2.  Batch airdrop for efficient giveaways
 * 3.  Burn-to-Upgrade: fuse 2 tokens → 1 “crafted” token with a custom URI
 */
contract SurpriseMonadNFT is
    ERC4907,
    ERC2981,
    Pausable,
    AccessControl,
    Ownable
{
    using Counters for Counters.Counter;
    Counters.Counter private _ids;

    /* ─────────────────── Collection parameters ─────────────────── */
    uint256 public constant MAX_SUPPLY      = 10_000;
    uint256 public          mintPrice       = 0.01 ether;  // Public sale
    uint256 public          presalePrice    = 0.008 ether; // Pre-sale discount

    /* Metadata */
    string  private unrevealedURI;          // Placeholder before reveal
    string  private baseURI;                // Base after reveal
    bool    public  revealed = false;

    /* Soul-bound locking */
    mapping(uint256 => bool) public soulbound;

    /* Crafted tokens carry their own URI (overrides baseURI) */
    mapping(uint256 => string) private _customTokenURI;

    /* ───────────────────────  Roles & Phases  ────────────────────── */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    enum Phase { Closed, PreSale, PublicSale }
    Phase public phase = Phase.Closed;

    /* Merkle-root for allow-list */
    bytes32 public presaleRoot;
    mapping(address => uint256) public presaleMinted; // 1-address cap

    /* ────────────────────────── Constructor ───────────────────────── */
    constructor(string memory _unrevealed, string memory _initialBase)
        ERC4907("Surprise Monad NFT", "SMN")
        Ownable(msg.sender)
    {
        unrevealedURI = _unrevealed;
        baseURI       = _initialBase;

        _setDefaultRoyalty(msg.sender, 500); // 5 % royalties

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE,          msg.sender);
    }

    /* ═════════════════════════════ Minting ═══════════════════════════ */

    /** Pre-sale mint for allow-listed addresses (Merkle proof required). */
    function presaleMint(uint256 amount, bytes32[] calldata proof)
        external
        payable
        whenNotPaused
    {
        require(phase == Phase.PreSale,          "Pre-sale inactive");
        require(_verify(msg.sender, proof),      "Not on allow-list");
        require(presaleMinted[msg.sender] == 0,  "Already claimed");
        require(amount > 0,                      "Amount = 0");
        require(msg.value >= presalePrice * amount, "Under-paid");
        require(totalSupply() + amount <= MAX_SUPPLY, "Sold out");

        presaleMinted[msg.sender] = amount;
        for (uint256 i; i < amount; ++i) _mintInternal(msg.sender);
    }

    /** Public sale mint available to everyone. */
    function publicMint(uint256 amount) external payable whenNotPaused {
        require(phase == Phase.PublicSale, "Public sale inactive");
        require(amount > 0,                "Amount = 0");
        require(msg.value >= mintPrice * amount, "Under-paid");
        require(totalSupply() + amount <= MAX_SUPPLY, "Sold out");

        for (uint256 i; i < amount; ++i) _mintInternal(msg.sender);
    }

    /** Role-based airdrop (single call, many receivers). */
    function batchAirdrop(address[] calldata to) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + to.length <= MAX_SUPPLY, "Sold out");
        for (uint256 i; i < to.length; ++i) _mintInternal(to[i]);
    }

    /** Internal mint helper. */
    function _mintInternal(address to) private {
        _ids.increment();
        _safeMint(to, _ids.current());
    }

    function totalSupply() public view returns (uint256) {
        return _ids.current();
    }

    /* ════════════════════════ Burn-to-Upgrade ═══════════════════════ */

    /**
     * Burn two tokens owned by caller and mint ONE “crafted” token
     * that carries its own custom URI.
     */
    function craftAndUpgrade(
        uint256 tokenA,
        uint256 tokenB,
        string calldata craftedURI
    ) external whenNotPaused returns (uint256 newId)
    {
        require(tokenA != tokenB,               "Duplicate token IDs");
        require(ownerOf(tokenA) == msg.sender &&
                ownerOf(tokenB) == msg.sender,  "Not owner");
        require(!soulbound[tokenA] && !soulbound[tokenB],
                "Soul-bound locked");

        /* Burn originals */
        _burn(tokenA);
        _burn(tokenB);

        /* Mint upgraded token */
        _ids.increment();
        newId = _ids.current();
        _safeMint(msg.sender, newId);
        _customTokenURI[newId] = craftedURI;
    }

    /* ═══════════════════════ Management tools ═══════════════════════ */

    /* Sale phase control */
    function setPhase(Phase p) external onlyOwner { phase = p; }

    /* Merkle-root for allow-list */
    function setPresaleRoot(bytes32 root) external onlyOwner { presaleRoot = root; }

    /* Prices */
    function setMintPrice(uint256 weiPrice)    external onlyOwner { mintPrice    = weiPrice; }
    function setPresalePrice(uint256 weiPrice) external onlyOwner { presalePrice = weiPrice; }

    /* Pause / Unpause public functions */
    function pause()   external onlyOwner { _pause();  }
    function unpause() external onlyOwner { _unpause(); }

    /* Soul-bound lock toggle */
    function lockSoulbound(uint256 tokenId, bool locked) external onlyOwner {
        soulbound[tokenId] = locked;
    }

    /* Withdraw contract balance */
    function withdraw() external onlyOwner {
        (bool ok, ) = owner().call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    /* ═══════════════════════ Metadata ⟷ URI logic ═══════════════════ */

    /** Base URI override used by OZ’s ERC721 tokenURI. */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /** Full token URI logic (placeholder ▸ baseURI ▸ customURI). */
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!revealed)                               return unrevealedURI;
        if (bytes(_customTokenURI[id]).length != 0)  return _customTokenURI[id];
        return super.tokenURI(id);
    }

    /** One-time reveal. */
    function reveal(string calldata newBase) external onlyOwner {
        require(!revealed, "Already revealed");
        baseURI = newBase;
        revealed = true;
    }

    /* ═════════════════════ Transfer & Soul-bound guard ══════════════ */

    modifier transferable(uint256 tokenId) {
        require(!soulbound[tokenId], "Soul-bound: non-transferable");
        _;
    }

    function transferFrom(address from, address to, uint256 tokenId)
        public
        override
        transferable(tokenId)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override
        transferable(tokenId)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    )
        public
        override
        transferable(tokenId)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /* ═════════════════════ Internal helpers ═════════════════════════ */

    function _verify(address account, bytes32[] calldata proof)
        internal
        view
        returns (bool)
    {
        return MerkleProof.verify(
            proof,
            presaleRoot,
            keccak256(abi.encodePacked(account))
        );
    }

    /* Interface multiplexer */
    function supportsInterface(bytes4 iid)
        public
        view
        override(ERC4907, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(iid);
    }

    /* Accept ETH  */
    receive() external payable {}
}
