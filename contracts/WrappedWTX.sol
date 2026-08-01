// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title WrappedWTX (wWTX) — WATTx's coin on nuChain.
/// Minted 1:1 (8 decimals, satoshi-exact) against WTX locked in
/// NuChainBridge on the WATTx EVM; burned here to withdraw home.
/// Registered with nuChain's x/erc20 module as a token pair, wWTX converts
/// to a native Cosmos denom and travels the ecosystem over IBC — Osmosis,
/// the Hub, anywhere — and back.
contract WrappedWTX {
    string public constant name = "Wrapped WTX";
    string public constant symbol = "wWTX";
    uint8 public constant decimals = 8; // satoshi-exact vs WATTx native

    address public bridge; // relayer/multisig authorized to mint
    address public owner;
    uint256 public totalSupply;
    uint256 public burnNonce;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    /// wattxAddress is the base58 WATTx address to release to; burnId is the
    /// replay-guard key consumed by NuChainBridge.releaseWTX on WATTx.
    event BurnedToWATTx(address indexed from, string wattxAddress, uint256 amountSat, bytes32 burnId);

    modifier onlyBridge() {
        require(msg.sender == bridge, "wWTX: not bridge");
        _;
    }

    constructor(address bridge_) {
        owner = msg.sender;
        bridge = bridge_;
    }

    function setBridge(address b) external {
        require(msg.sender == owner, "wWTX: not owner");
        bridge = b;
    }

    function mint(address to, uint256 amountSat) external onlyBridge {
        balanceOf[to] += amountSat;
        totalSupply += amountSat;
        emit Transfer(address(0), to, amountSat);
    }

    /// Burn to withdraw WTX on WATTx. Emits the burnId the relayer carries home.
    function burnToWATTx(string calldata wattxAddress, uint256 amountSat) external returns (bytes32 burnId) {
        require(balanceOf[msg.sender] >= amountSat, "wWTX: insufficient");
        balanceOf[msg.sender] -= amountSat;
        totalSupply -= amountSat;
        burnId = keccak256(abi.encodePacked(block.chainid, msg.sender, wattxAddress, amountSat, burnNonce++));
        emit Transfer(msg.sender, address(0), amountSat);
        emit BurnedToWATTx(msg.sender, wattxAddress, amountSat, burnId);
    }

    // ---- minimal ERC20 ----

    function transfer(address to, uint256 v) external returns (bool) {
        return _transfer(msg.sender, to, v);
    }

    function transferFrom(address from, address to, uint256 v) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= v, "wWTX: allowance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - v;
        return _transfer(from, to, v);
    }

    function approve(address spender, uint256 v) external returns (bool) {
        allowance[msg.sender][spender] = v;
        emit Approval(msg.sender, spender, v);
        return true;
    }

    function _transfer(address from, address to, uint256 v) internal returns (bool) {
        require(balanceOf[from] >= v, "wWTX: insufficient");
        balanceOf[from] -= v;
        balanceOf[to] += v;
        emit Transfer(from, to, v);
        return true;
    }
}
