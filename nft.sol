// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* 
 * OpenZeppelin v5 imports.
 * If your OZ bundle does NOT include ERC4907, comment out that line and this contract’s inheritance of ERC4907.
 */
import "@openzeppelin/contracts/token/ERC721/extensions/ERC4907.sol";   // Rental extension (ERC-4907). Comment out if unavailable.
import "@openzeppelin/contracts/token/common/ERC2981.sol";              // Royalties (EIP-2981)
import "@openzeppelin/contracts/access/AccessControl.sol";              // Role-based permissions
import "@openzeppelin/contracts/access/Ownable.sol";                    // Simple ownership
import "@openzeppelin/contracts/security/Pausable.sol";                 // Circuit breaker
import "@openzeppelin/contracts/utils/Counters.sol";                    // Simple counters

/**
 * SurpriseMonadNFT
 *
 * Feature set:
 * - Public mint with price (editable).
 * - Reveal workflow (hidden placeholder URI → real metadata).
 * - Soul-bound lock per token (non-transferable while locked).
 * - Optional rental (ERC-4907): owner can set a "user" with an expiry.
 * - Pausable mints for safety.
 * - Royalties via ERC-2981 (default 5%).
 * - Role-based airdrops (MINTER_ROLE).
 * - Withdraw pattern for sale proceeds.
 *
 * Deploy on Monad testnet from ChainIDE/Remix with Solidity 0.8.20.
 */
contract SurpriseMonadNFT is
    ERC4907,          // Comment out AND replace with ERC721 if ERC4907 is unavailable
    ERC2981,
    Pausable,
    AccessControl,
    Ownable
{
    using Counters for Counters.Counter;
    Counters.Counter private _ids;

    /* -------------------- Configurable parameters -------------------- */
    uint256 public constant MAX_SUPPLY = 10_000; // Hard cap
    uint256 public mintPrice = 0.01 ether;       // Public mint price (changeable by owner)

    // Metadata handling
    string  private unrevealedURI;  // Single placeholder URI before reveal
    string  private baseURI;        // Base URI after reveal (e.g., ipfs://CID/)

    bool    public  revealed = false; // Flag that governs tokenURI behavior

    /* Soul-bound lock: when true, the token cannot be transferred (mint/burn still allowed) */
    mapping(uint256 => bool) public soulbound;

    /* Roles */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /* --------------------------- Constructor ------------------------- */
    /**
     * @param _unrevealed  URI returned for every token before reveal (e.g., ipfs://.../hidden.json)
     * @param _initialBase Base URI used after reveal (e.g., ipfs://.../metadata/)
     *
     * Ownable(msg.sender): deployer is the initial owner (OZ v5 requires passing the initial owner).
     * ERC-2981: sets a default royalty of 5% to the deployer; marketplaces use this if they support EIP-2981.
     * AccessControl: grant admin + minter roles to the deployer.
     */
    constructor(
        string memory _unrevealed,
        string memory _initialBase
    )
        ERC4907("Surprise Monad NFT", "SMN") // If you removed ERC4907, change to ERC721("Surprise Monad NFT", "SMN")
        Ownable(msg.sender)
    {
        unrevealedURI = _unrevealed;
        baseURI       = _initialBase;

        _setDefaultRoyalty(msg.sender, 500); // 500 basis points = 5%

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /* ----------------------------- Minting --------------------------- */

    /**
     * @notice Public sale mint. Anyone can mint by paying `mintPrice * amount`.
     * @dev Pausable: owner can pause/unpause mints for safety (bots, incident response, etc.).
     */
    function publicMint(uint256 amount) external payable whenNotPaused {
        require(amount > 0, "Amount = 0");
        require(totalSupply() + amount <= MAX_SUPPLY, "Sold out");
        require(msg.value >= mintPrice * amount, "Insufficient payment");

        for (uint256 i; i < amount; ++i) {
            _mintInternal(msg.sender);
        }
    }

    /**
     * @notice Role-gated mint for airdrops/allowlist claims.
     * @dev Only accounts with MINTER_ROLE may call this function.
     */
    function roleMint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "Zero address");
        require(amount > 0, "Amount = 0");
        require(totalSupply() + amount <= MAX_SUPPLY, "Sold out");

        for (uint256 i; i < amount; ++i) {
            _mintInternal(to);
        }
    }

    function _mintInternal(address to) private {
        _ids.increment();
        _safeMint(to, _ids.current());
    }

    function totalSupply() public view returns (uint256) {
        return _ids.current();
    }

    /* ---------------------------- Reveal ----------------------------- */

    /**
     * @notice Permanently switch from the placeholder URI to the real base URI.
     * @dev Can only be executed once; update `baseURI` and set `revealed = true`.
     */
    function reveal(string calldata newBase) external onlyOwner {
        require(!revealed, "Already revealed");
        baseURI  = newBase;
        revealed = true;
    }

    /* ------------------------- Soul-bound lock ----------------------- */

    /**
     * @notice Lock or unlock a token as soul-bound (non-transferable while locked).
     * @dev Does NOT block minting or burning. Prevents user-initiated transfers only.
     */
    function lockSoulbound(uint256 tokenId, bool lock_) external onlyOwner {
        soulbound[tokenId] = lock_;
    }

    /* ------------------------------ Admin ---------------------------- */

    /// @notice Emergency stop for public mints.
    function pause()  external onlyOwner { _pause();  }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Update public mint price (in wei).
    function setMintPrice(uint256 weiPrice) external onlyOwner {
        mintPrice = weiPrice;
    }

    /// @notice Withdraw contract balance to the owner.
    function withdraw() external onlyOwner {
        (bool ok, ) = owner().call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    /* ---------------------------- Metadata --------------------------- */

    /**
     * @dev OZ ERC721 uses `_baseURI()` for concatenation with tokenId.
     * For example, baseURI = ipfs://CID/  → tokenURI = ipfs://CID/{id}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Before `reveal()`, every token returns the same `unrevealedURI`.
     * After reveal, it falls back to the standard ERC721 tokenURI (baseURI + tokenId).
     */
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!revealed) return unrevealedURI;
        return super.tokenURI(id);
    }

    /* ---------------------- Soul-bound enforcement ------------------- */
    /**
     * @dev Block user-initiated transfers while a token is soul-bound.
     * We override the external transfer entry points instead of internal hooks,
     * to keep compatibility across OZ versions.
     */
    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(!soulbound[tokenId], "Soul-bound: non-transferable");
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        require(!soulbound[tokenId], "Soul-bound: non-transferable");
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
    {
        require(!soulbound[tokenId], "Soul-bound: non-transferable");
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /* ---------------------- Interface resolution --------------------- */
    function supportsInterface(bytes4 iid)
        public
        view
        override(ERC4907, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(iid);
    }

    /* --------------------------- Fallback ---------------------------- */
    /// @dev Accept ETH from public mints, donations, etc.
    receive() external payable {}
}
