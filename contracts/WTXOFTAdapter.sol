// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title WTXOFTAdapter — LayerZero OFT endpoint for wWTX on nuChain.
///
/// Two roads out of nuChain, by design:
///   • IBC (native Cosmos): wWTX -> x/erc20 native denom -> IBC transfer.
///   • LayerZero (EVM world): this adapter locks/burns wWTX and messages a
///     paired OFT on Ethereum / BSC / Polygon / Base, so WTX also reaches
///     non-Cosmos chains — the same reach WATTx's own bridge targets.
///
/// This is an interface-level scaffold: it defines the send/receive surface
/// and the trusted-remote wiring. The concrete LayerZero Endpoint V2 import
/// is added when the LZ contracts are vendored (phase 3); kept dependency-free
/// here so the repo compiles standalone.
interface IwWTX {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface ILayerZeroEndpoint {
    function send(
        uint32 dstEid,
        bytes calldata message,
        bytes calldata options,
        address refund
    ) external payable;
}

contract WTXOFTAdapter {
    IwWTX public immutable wwtx;
    address public endpoint; // LayerZero Endpoint V2 on nuChain (set at phase 3)
    address public owner;

    mapping(uint32 => bytes32) public peers; // dstEid => remote OFT (bytes32)

    event SentToChain(uint32 indexed dstEid, bytes32 indexed to, uint256 amountSat);
    event ReceivedFromChain(uint32 indexed srcEid, address indexed to, uint256 amountSat);
    event PeerSet(uint32 indexed eid, bytes32 peer);

    modifier onlyOwner() {
        require(msg.sender == owner, "OFT: not owner");
        _;
    }

    constructor(address wwtx_, address endpoint_) {
        wwtx = IwWTX(wwtx_);
        endpoint = endpoint_;
        owner = msg.sender;
    }

    function setPeer(uint32 eid, bytes32 peer) external onlyOwner {
        peers[eid] = peer;
        emit PeerSet(eid, peer);
    }

    function setEndpoint(address e) external onlyOwner {
        endpoint = e;
    }

    /// Lock wWTX on nuChain and instruct the remote OFT to mint to `to`.
    function sendToChain(uint32 dstEid, bytes32 to, uint256 amountSat, bytes calldata options)
        external
        payable
    {
        require(peers[dstEid] != bytes32(0), "OFT: no peer");
        require(wwtx.transferFrom(msg.sender, address(this), amountSat), "OFT: lock failed");
        bytes memory message = abi.encode(to, amountSat);
        if (endpoint != address(0)) {
            ILayerZeroEndpoint(endpoint).send{value: msg.value}(dstEid, message, options, msg.sender);
        }
        emit SentToChain(dstEid, to, amountSat);
    }

    /// Called by the LayerZero endpoint on inbound message (guarded in phase 3
    /// by lzReceive auth + srcEid peer check). Releases locked wWTX to `to`.
    function _credit(uint32 srcEid, address to, uint256 amountSat) internal {
        require(peers[srcEid] != bytes32(0), "OFT: unknown source");
        wwtx.transfer(to, amountSat);
        emit ReceivedFromChain(srcEid, to, amountSat);
    }
}
