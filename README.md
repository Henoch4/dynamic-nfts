# Dynamic NFTs — Living Collectibles

> Collectibles that change state. Each token has a mutable metadata URI that the owner can evolve; moods, wear levels and unlocks live on-chain so artwork can react to real events without redeploying.

## What it does

Collectibles that change state. Each token has a mutable metadata URI that the owner can evolve; moods, wear levels and unlocks live on-chain so artwork can react to real events without redeploying. The entire lifecycle lives in one contract, every button in the UI calls a real function on it — there is no mock backend.

## Contract

| | |
|---|---|
| File | `contracts/DynamicNFTs.sol` |
| Contract name | `DynamicNFTs` (inherits `ReentrancyGuard, Ownable`) |
| Solidity | `^0.8.20` |
| State functions | 8 (of which 1 payable) |
| Deployed (mainnet 677) | not yet deployed — placeholder `0x000…000` |

### Function surface

| Function | Type | Returns |
|---|---|---|
| `owner` | view | address |
| `mintNFT` | write | uint256 |
| `updateNFT` | write | result / revert |
| `transferNFT` | write | result / revert |
| `evolveNFT` | payable | tx receipt |
| `setEvolutionCost` | write | result / revert |
| `withdrawFees` | write | result / revert |
| `getNFT` | view | address owner, string memory uri, uint256 level, uint256 xp, uint256 lastUpdate, bool active |

### Events

| Event | Signature |
|---|---|
| `OwnershipTransferred` | (address indexed previousOwner, address indexed newOwner) |
| `NFTMinted` | (uint256 indexed tokenId, address indexed owner, string uri, uint256 level) |
| `NFTUpdated` | (uint256 indexed tokenId, address indexed owner, uint256 newLevel, uint256 newXP) |
| `NFTTransferred` | (uint256 indexed tokenId, address indexed from, address indexed to) |
| `NFTLeveledUp` | (uint256 indexed tokenId, address indexed owner, uint256 newLevel) |
| `EvolutionCostSet` | (uint256 newCost) |

## Network

| | |
|---|---|
| Chain | BOT Chain Mainnet (chainId `677`) |
| RPC | `https://rpc.botchain.ai` |
| Explorer | `https://scan.botchain.ai` |
| Native currency | BOT (18 decimals) |
| Testnet | BOT Chain Testnet (chainId `968`) - `https://rpc.bohr.life` |

## Frontend

- **Wallet connection** - [Reown/AppKit](https://reown.com) (Web3Modal v2, inline modal, `subscribeAccount` / `subscribeNetwork`)
- **Web3 library** - ethers.js v6 (`BrowserProvider`, `Contract`, `parseEther`)
- **Animation** - GSAP 3 + ScrollTrigger (`expo.out` entrances, `prefers-reduced-motion` fallback renders content instantly)
- **Zero build step** - single `index.html`, CDN imports via ESM import map; no bundler, no framework runtime
- **Accessibility** - auto-generated `aria-label`s on all binary and form controls, focus-visible styles, button busy states

## Run it locally

```bash
git clone https://github.com/Henoch4/dynamic-nfts.git
cd dynamic-nfts
# open the frontend directly (no build step)
start frontend/index.html   # Windows
# or serve it if your browser blocks file:// modules:
npx serve frontend
```

> **Note** — contract addresses: the UI reads its deploy target from the `CA` constant at the top of the inline script. Until the contract is deployed to mainnet 677, the demo runs against the deterministic sample data built into the page; after deployment, set `CA['677']` to the real address and every button goes live.