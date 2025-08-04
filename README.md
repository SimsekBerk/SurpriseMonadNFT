# SurpriseMonadNFT v2 

A feature-packed ERC-721 collection for the **Monad** testnet (and any EVM-compatible chain).  
Out of the box you get:

| Category | Features |
|----------|----------|
| **Minting** | ‣ Phased sale → `Closed`, `PreSale` (Merkle allow-list), `PublicSale`  <br>‣ Discounted pre-sale price  |
| **Airdrops** | ‣ `batchAirdrop()` mints to many addresses in one call |
| **Utility** | ‣ Burn-to-Upgrade: fuse two NFTs into a special “crafted” NFT with its own URI |
| **Extras** | ‣ ERC-4907 rental layer <br>‣ Soul-bound lock per token <br>‣ One-click reveal workflow <br>‣ ERC-2981 royalties (5 %) <br>‣ Pausable sales <br>‣ Role-based permissions (OpenZeppelin v5) |

---

## Folder structure
```
├── contracts
│ └── SurpriseMonadNFT.sol
├── scripts
│ ├── deploy.ts
│ └── merkle-root.ts
├── test
│ └── SurpriseMonadNFT.test.ts
├── hardhat.config.ts
└── README.md ← you are here

│ └── merkle-root.ts
├── test
│ └── SurpriseMonadNFT.test.ts
├── hardhat.config.ts
└── README.md ← you are here
```
---

## 1 · Prerequisites

* **Node.js 18+** and **NPM** / **Yarn**
* **Hardhat** (TypeScript or JavaScript)
* **MetaMask** (or any wallet that supports Monad testnet)
* Test MON from the [Monad faucet](https://faucet.monad.xyz)

```bash
# clone & install
git clone https://github.com/your-github/SurpriseMonadNFT.git
cd SurpriseMonadNFT
npm install            # or yarn
```
2 · Compile
```bash

npx hardhat compile
```


Solidity version: 0.8.20
OpenZeppelin Contracts: v5.x

