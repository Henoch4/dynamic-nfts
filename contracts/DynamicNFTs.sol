// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ReentrancyGuard {
    bool private _nonReentrant;
    constructor() { _nonReentrant = false; }
    modifier nonReentrant() {
        require(!_nonReentrant, "ReentrancyGuard: reentrant call");
        _nonReentrant = true;
        _;
        _nonReentrant = false;
    }
}
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), _owner); }
    modifier onlyOwner() { require(_owner == msg.sender, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
}

contract DynamicNFTs is ReentrancyGuard, Ownable {
    struct NFT {
        address owner;
        string uri;
        uint256 level;
        uint256 xp;
        uint256 lastUpdate;
        bool active;
    }
    NFT[] public nfts;
    mapping(uint256 => address) public tokenOwner;
    mapping(address => uint256[]) public userNFTs;
    uint256 public tokenCount;
    // FIX: evolution was admin-controlled (updateNFT could set arbitrary levels on
    // user tokens). Added user-driven evolution on the msg.sender plane with a
    // native-BOT level-up cost, plus an owner exit for collected fees.
    uint256 public evolutionCost;
    uint256 public xpPerEvolution;
    uint256 public xpToLevelUp;
    uint256 public collectedFees;

    event NFTMinted(uint256 indexed tokenId, address indexed owner, string uri, uint256 level);
    event NFTUpdated(uint256 indexed tokenId, address indexed owner, uint256 newLevel, uint256 newXP);
    event NFTTransferred(uint256 indexed tokenId, address indexed from, address indexed to);
    event NFTLeveledUp(uint256 indexed tokenId, address indexed owner, uint256 newLevel);
    event EvolutionCostSet(uint256 newCost);

    constructor() {
        // FIX: sane defaults so evolution works out of the box.
        evolutionCost = 0.001 ether;
        xpPerEvolution = 25;
        xpToLevelUp = 100;
    }

    function mintNFT(address to, string memory uri, uint256 level)
        external onlyOwner nonReentrant returns (uint256) {
        require(level > 0, "Zero level");
        NFT storage n = nfts.push();
        n.owner = to;
        n.uri = uri;
        n.level = level;
        n.xp = 0;
        n.lastUpdate = block.timestamp;
        n.active = true;
        uint256 tid = nfts.length - 1;
        tokenCount = tid + 1;
        tokenOwner[tid] = to;
        userNFTs[to].push(tid);
        emit NFTMinted(tid, to, uri, level);
        return tid;
    }

    // FIX: was admin-only with arbitrary level/xp writes on user tokens (wrong plane).
    // Kept as a narrow admin metadata refresh; scores only change via evolveNFT.
    function updateNFT(uint256 tokenId, string calldata newURI)
        external onlyOwner nonReentrant {
        NFT storage n = nfts[tokenId];
        require(n.active, "NFT inactive");
        n.uri = newURI;
        n.lastUpdate = block.timestamp;
        emit NFTUpdated(tokenId, n.owner, n.level, n.xp);
    }

    // FIX: mint/transfer left tokenOwner/userNFTs out of sync. Now updated here too.
    function transferNFT(uint256 tokenId, address to) external nonReentrant {
        NFT storage n = nfts[tokenId];
        require(n.active, "NFT inactive");
        require(n.owner == msg.sender, "Not owner");
        require(to != address(0), "Zero address");
        require(to != n.owner, "Self transfer");
        address from = n.owner;
        n.owner = to;
        tokenOwner[tokenId] = to;
        userNFTs[to].push(tokenId);
        uint256[] storage owned = userNFTs[from];
        for (uint256 i = 0; i < owned.length; i++) {
            if (owned[i] == tokenId) {
                owned[i] = owned[owned.length - 1];
                owned.pop();
                break;
            }
        }
        emit NFTTransferred(tokenId, from, to);
    }

    // FIX: added owner-of-token evolution loop: pay native BOT cost, gain XP, level up
    // when threshold reached. Cost handler exits to owner so fees never get stuck.
    function evolveNFT(uint256 tokenId) external payable nonReentrant {
        NFT storage n = nfts[tokenId];
        require(n.active, "NFT inactive");
        require(msg.sender == n.owner, "Not token owner");
        require(msg.value == evolutionCost, "Wrong cost");
        collectedFees += msg.value;
        n.xp += xpPerEvolution;
        n.lastUpdate = block.timestamp;
        if (n.xp >= xpToLevelUp) {
            n.xp = 0;
            n.level += 1;
            emit NFTLeveledUp(tokenId, msg.sender, n.level);
        }
        emit NFTUpdated(tokenId, msg.sender, n.level, n.xp);
    }

    function setEvolutionCost(uint256 newCost, uint256 newXpPerEvo, uint256 newXpToLevel)
        external onlyOwner {
        require(newCost > 0, "Zero cost");
        require(newXpPerEvo > 0 && newXpToLevel > 0, "Zero xp params");
        evolutionCost = newCost;
        xpPerEvolution = newXpPerEvo;
        xpToLevelUp = newXpToLevel;
        emit EvolutionCostSet(newCost);
    }

    // FIX: only exit path for collected native fees — owner pulls, plain call.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = collectedFees;
        require(amount > 0, "Zero fees");
        collectedFees = 0;
        (bool ok,) = owner().call{value: amount}("");
        require(ok, "Withdraw failed");
    }

    function getNFT(uint256 tokenId) external view returns (address owner, string memory uri, uint256 level, uint256 xp, uint256 lastUpdate, bool active) {
        NFT storage n = nfts[tokenId];
        return (n.owner, n.uri, n.level, n.xp, n.lastUpdate, n.active);
    }
}
