// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title NuChainBridge — nuChain state anchoring on the WATTx EVM.
///
/// Phase 1 (economic anchoring): a bonded relayer set posts nuChain block
/// headers (height, CometBFT app hash, timestamp) each epoch. Anchors are
/// challengeable during a dispute window; a successful fraud challenge
/// slashes the submitting relayer. This makes nuChain reorg-resistant
/// against anything short of rewriting WATTx itself — which is merged-mined
/// across seven algorithms.
///
/// Phase 2 (validity): `submitProof` upgrades an anchor from economic to
/// proven — a zk validity proof of the state transition (Cysic-proved or
/// zk light client), verified on-chain. The verifier address is swappable
/// by governance so proof systems can evolve.
contract NuChainBridge {
    struct Anchor {
        uint64 nuHeight;
        bytes32 appHash; // CometBFT app hash — commits all nuChain state incl. EVM
        uint64 nuTime;
        uint64 anchoredAt; // WATTx timestamp
        address relayer;
        bool proven; // zk validity proof accepted
        bool disputed;
    }

    address public owner;
    address public verifier; // zk verifier contract (phase 2); 0 = economic mode
    uint256 public relayerBond;
    uint64 public epochBlocks; // anchor every N nuChain blocks
    uint64 public disputeWindow = 1 hours;

    mapping(address => uint256) public bondOf;
    mapping(uint64 => Anchor) public anchors; // nuHeight => anchor
    uint64 public latestHeight;
    uint64[] public anchorHeights;

    event RelayerBonded(address indexed relayer, uint256 bond);
    event RelayerExited(address indexed relayer);
    event Anchored(uint64 indexed nuHeight, bytes32 appHash, address relayer);
    event Proven(uint64 indexed nuHeight);
    event Disputed(uint64 indexed nuHeight, address challenger);
    event Slashed(address indexed relayer, uint256 amount, address challenger);

    modifier onlyOwner() {
        require(msg.sender == owner, "NuChainBridge: not owner");
        _;
    }

    constructor(uint256 relayerBond_, uint64 epochBlocks_) {
        owner = msg.sender;
        relayerBond = relayerBond_;
        epochBlocks = epochBlocks_;
    }

    function setOwner(address o) external onlyOwner {
        owner = o;
    }

    function setVerifier(address v) external onlyOwner {
        verifier = v;
    }

    function setParams(uint256 bond_, uint64 epoch_, uint64 window_) external onlyOwner {
        relayerBond = bond_;
        epochBlocks = epoch_;
        disputeWindow = window_;
    }

    // ---------------- relayer set ----------------

    /// WATTx native coin bond (satoshi-denominated msg.value on WATTx!).
    function bondRelayer() external payable {
        require(msg.value >= relayerBond, "NuChainBridge: bond too small");
        bondOf[msg.sender] += msg.value;
        emit RelayerBonded(msg.sender, msg.value);
    }

    function exitRelayer() external {
        uint256 b = bondOf[msg.sender];
        require(b > 0, "NuChainBridge: no bond");
        bondOf[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: b}("");
        require(ok, "NuChainBridge: refund failed");
        emit RelayerExited(msg.sender);
    }

    // ---------------- anchoring ----------------

    function anchor(uint64 nuHeight, bytes32 appHash, uint64 nuTime) external {
        require(bondOf[msg.sender] >= relayerBond, "NuChainBridge: not bonded");
        require(nuHeight > latestHeight, "NuChainBridge: stale height");
        require(appHash != bytes32(0), "NuChainBridge: empty hash");
        anchors[nuHeight] = Anchor(nuHeight, appHash, nuTime, uint64(block.timestamp), msg.sender, false, false);
        anchorHeights.push(nuHeight);
        latestHeight = nuHeight;
        emit Anchored(nuHeight, appHash, msg.sender);
    }

    // ---------------- proof mining ----------------
    // Validity proofs are MINED: anyone with proving hardware (Cysic network
    // provers, self-hosted GPU/FPGA) races to prove each anchored epoch.
    // First valid proof wins the bounty — proof generation becomes a new
    // algorithm in the mining economy, alongside the seven PoW algos.

    uint256 public proofBounty; // paid per proven epoch, satoshi-denominated
    uint256 public bountyPool;
    mapping(uint64 => address) public proverOf; // nuHeight => winning prover

    event BountyFunded(address indexed from, uint256 amount);
    event ProofMined(uint64 indexed nuHeight, address indexed prover, uint256 bounty);

    function fundBounties() external payable {
        bountyPool += msg.value;
        emit BountyFunded(msg.sender, msg.value);
    }

    function setProofBounty(uint256 b) external onlyOwner {
        proofBounty = b;
    }

    /// Phase 2: attach a zk validity proof to an anchor. First valid proof
    /// per epoch claims the bounty — this is the proof-mining race.
    function submitProof(uint64 nuHeight, bytes calldata proof) external {
        require(verifier != address(0), "NuChainBridge: no verifier set");
        Anchor storage a = anchors[nuHeight];
        require(a.anchoredAt != 0 && !a.proven, "NuChainBridge: bad anchor");
        (bool ok, bytes memory ret) =
            verifier.staticcall(abi.encodeWithSignature("verify(bytes32,bytes)", a.appHash, proof));
        require(ok && abi.decode(ret, (bool)), "NuChainBridge: invalid proof");
        a.proven = true;
        proverOf[nuHeight] = msg.sender;

        uint256 pay = proofBounty <= bountyPool ? proofBounty : bountyPool;
        if (pay > 0) {
            bountyPool -= pay;
            (bool sent,) = msg.sender.call{value: pay}("");
            require(sent, "NuChainBridge: bounty transfer failed");
        }
        emit Proven(nuHeight);
        emit ProofMined(nuHeight, msg.sender, pay);
    }

    /// Economic-mode dispute: owner-adjudicated in phase 1 (multisig),
    /// replaced by proof-based auto-adjudication in phase 2.
    function dispute(uint64 nuHeight) external onlyOwner {
        Anchor storage a = anchors[nuHeight];
        require(a.anchoredAt != 0 && !a.proven, "NuChainBridge: bad anchor");
        require(block.timestamp <= a.anchoredAt + disputeWindow, "NuChainBridge: window closed");
        a.disputed = true;
        uint256 b = bondOf[a.relayer];
        bondOf[a.relayer] = 0;
        if (nuHeight == latestHeight && anchorHeights.length >= 2) {
            latestHeight = anchorHeights[anchorHeights.length - 2];
        }
        (bool ok,) = msg.sender.call{value: b}("");
        require(ok, "NuChainBridge: slash transfer failed");
        emit Disputed(nuHeight, msg.sender);
        emit Slashed(a.relayer, b, msg.sender);
    }

    // ---------------- WTX vault (WATTx -> nuChain -> Cosmos) ----------------
    // Lock WTX here; the bridge relayer mints wWTX 1:1 on nuChain, where the
    // x/erc20 module converts it to a native IBC-transferable denom — so WTX
    // can travel the entire Cosmos ecosystem and come home the same way.
    // NOTE: msg.value on the WATTx EVM is SATOSHI-denominated (1e8 = 1 WTX).
    // wWTX mirrors this with 8 decimals for exact 1:1 accounting.

    uint256 public totalLocked;
    mapping(bytes32 => bool) public released; // burn-event id => done (replay guard)

    event WTXLocked(address indexed from, address indexed nuRecipient, uint256 amountSat);
    event WTXReleased(address indexed to, uint256 amountSat, bytes32 burnId);

    /// Lock WTX for a nuChain EVM recipient address.
    function lockWTX(address nuRecipient) external payable {
        require(msg.value > 0, "NuChainBridge: zero lock");
        require(nuRecipient != address(0), "NuChainBridge: zero recipient");
        totalLocked += msg.value;
        emit WTXLocked(msg.sender, nuRecipient, msg.value);
    }

    /// Release WTX against a wWTX burn on nuChain. Phase 1: owner-executed
    /// (relayer multisig); phase 2: gated on a zk-proven anchor covering the
    /// burn (burnId verifiable against the anchored app hash).
    function releaseWTX(address payable to, uint256 amountSat, bytes32 burnId) external onlyOwner {
        require(!released[burnId], "NuChainBridge: replayed");
        require(amountSat <= totalLocked, "NuChainBridge: exceeds locked");
        released[burnId] = true;
        totalLocked -= amountSat;
        (bool ok,) = to.call{value: amountSat}("");
        require(ok, "NuChainBridge: release failed");
        emit WTXReleased(to, amountSat, burnId);
    }

    // ---------------- views ----------------

    function latestAnchor() external view returns (Anchor memory) {
        return anchors[latestHeight];
    }

    function anchorCount() external view returns (uint256) {
        return anchorHeights.length;
    }
}
