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
    string public constant name = "DynamicNFTs";
    string public constant symbol = "DNFT";
    mapping(uint256 => address) private approvals;
    mapping(address => mapping(address => bool)) private operators;
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

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
        require(to != address(0), "Zero recipient");
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
        emit Transfer(address(0), to, tid);
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
        _moveNFT(ownerOf(tokenId), to, tokenId);
    }

    function _moveNFT(address from, address to, uint256 tokenId) internal {
        NFT storage n = nfts[tokenId];
        require(n.active, "NFT inactive");
        require(n.owner == from, "Wrong owner");
        require(msg.sender == from || approvals[tokenId] == msg.sender || operators[from][msg.sender], "Not authorized");
        require(to != address(0), "Zero address");
        delete approvals[tokenId];
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
        emit Transfer(from, to, tokenId);
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        require(tokenId < nfts.length && nfts[tokenId].active, "Unknown token");
        return nfts[tokenId].owner;
    }
    function balanceOf(address who) external view returns (uint256) {
        require(who != address(0), "Zero owner");
        return userNFTs[who].length;
    }
    function tokenURI(uint256 tokenId) external view returns (string memory) { ownerOf(tokenId); return nfts[tokenId].uri; }
    function supportsInterface(bytes4 id) external pure returns (bool) { return id == 0x01ffc9a7 || id == 0x80ac58cd || id == 0x5b5e139f; }
    function approve(address to, uint256 tokenId) external {
        address holder = ownerOf(tokenId);
        require(msg.sender == holder || operators[holder][msg.sender], "Not authorized");
        approvals[tokenId] = to;
        emit Approval(holder, to, tokenId);
    }
    function getApproved(uint256 tokenId) external view returns (address) { ownerOf(tokenId); return approvals[tokenId]; }
    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "Self approval");
        operators[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    function isApprovedForAll(address holder, address operator) external view returns (bool) { return operators[holder][operator]; }
    function transferFrom(address from, address to, uint256 tokenId) external nonReentrant { _moveNFT(from, to, tokenId); }
    function safeTransferFrom(address from, address to, uint256 tokenId) external nonReentrant { _safeMove(from, to, tokenId, ""); }
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external nonReentrant { _safeMove(from, to, tokenId, data); }
    function _safeMove(address from, address to, uint256 tokenId, bytes memory data) internal {
        _moveNFT(from, to, tokenId);
        if (to.code.length > 0) {
            (bool ok, bytes memory reply) = to.call(abi.encodeWithSignature("onERC721Received(address,address,uint256,bytes)", msg.sender, from, tokenId, data));
            require(ok && reply.length >= 32 && abi.decode(reply, (bytes4)) == 0x150b7a02, "Unsafe recipient");
        }
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
