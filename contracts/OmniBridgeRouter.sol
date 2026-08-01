// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title OmniBridgeRouter — nuChain's universal cross-chain asset router.
///
/// nuChain is the Cosmos-SDK hub where three transports meet:
///   • WATTx     — via NuChainBridge (lock WTX → mint wWTX here)
///   • LayerZero — via this router (any EVM chain: ETH/BSC/Polygon/Base/…)
///   • IBC       — via the x/erc20 module (any Cosmos chain)
///
/// Every bridged asset lives on nuChain as an ERC-20. Once here it can leave by
/// EITHER transport:
///   - LayerZero: burn/lock here → message a peer OFT on a remote EVM chain
///   - IBC: x/erc20 converts the ERC-20 to a native denom → IBC transfer
/// …and arrive by either. That makes nuChain a hub-and-spoke router: an asset on
/// ANY connected chain can reach ANY other by hopping through nuChain once.
///
/// This contract is the LayerZero + local-mint/lock half. It is transport-generic
/// (any registered token, any endpoint id). The concrete LayerZero Endpoint V2
/// import is attached at deploy (phase 3); the router compiles standalone so the
/// repo has no external dependency to build.

interface IBridgeToken {
    function mint(address to, uint256 amount) external;      // for wrapped assets minted here
    function burn(address from, uint256 amount) external;    // burn on outbound
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface ILzEndpoint {
    function send(uint32 dstEid, bytes calldata message, bytes calldata options, address refund) external payable;
}

contract OmniBridgeRouter {
    enum Mode { MintBurn, LockRelease }

    struct TokenConfig {
        address token;      // ERC-20 on nuChain
        Mode mode;          // wrapped asset (MintBurn) vs canonical liquidity (LockRelease)
        bool enabled;
    }

    struct Route {
        bytes32 peer;       // remote OFT/router (bytes32-encoded address) on dstEid
        uint8 remoteDecimals;
        bool enabled;
    }

    address public owner;
    address public endpoint;              // LayerZero Endpoint V2 on nuChain
    address public nuChainBridge;         // WATTx bridge (authorized to mark wWTX routes)

    // tokenId => config; a tokenId is keccak(symbol) so the same asset lines up across chains
    mapping(bytes32 => TokenConfig) public tokens;
    // tokenId => dstEid => route
    mapping(bytes32 => mapping(uint32 => Route)) public routes;
    // inbound replay guard
    mapping(bytes32 => bool) public consumed;

    event TokenRegistered(bytes32 indexed tokenId, address token, Mode mode);
    event RouteSet(bytes32 indexed tokenId, uint32 indexed dstEid, bytes32 peer);
    event SentOut(bytes32 indexed tokenId, uint32 indexed dstEid, bytes32 to, uint256 amount, address from);
    event ReceivedIn(bytes32 indexed tokenId, uint32 indexed srcEid, address to, uint256 amount);

    modifier onlyOwner() { require(msg.sender == owner, "Omni: not owner"); _; }

    constructor(address endpoint_) {
        owner = msg.sender;
        endpoint = endpoint_;
    }

    function setOwner(address o) external onlyOwner { owner = o; }
    function setEndpoint(address e) external onlyOwner { endpoint = e; }
    function setNuChainBridge(address b) external onlyOwner { nuChainBridge = b; }

    // ---------------- registry ----------------

    /// tokenId = keccak256(symbol) — e.g. keccak("WTX"), keccak("USDT"), keccak("ETH").
    function registerToken(bytes32 tokenId, address token, Mode mode) external onlyOwner {
        tokens[tokenId] = TokenConfig(token, mode, true);
        emit TokenRegistered(tokenId, token, mode);
    }

    function setRoute(bytes32 tokenId, uint32 dstEid, bytes32 peer, uint8 remoteDecimals) external onlyOwner {
        require(tokens[tokenId].enabled, "Omni: token not registered");
        routes[tokenId][dstEid] = Route(peer, remoteDecimals, true);
        emit RouteSet(tokenId, dstEid, peer);
    }

    // ---------------- outbound: nuChain -> any EVM chain ----------------

    /// Send a registered asset out to a remote EVM chain over LayerZero.
    /// MintBurn tokens are burned here; LockRelease tokens are pulled and held.
    function sendOut(bytes32 tokenId, uint32 dstEid, bytes32 to, uint256 amount, bytes calldata lzOptions)
        external
        payable
    {
        TokenConfig memory tc = tokens[tokenId];
        Route memory r = routes[tokenId][dstEid];
        require(tc.enabled && r.enabled, "Omni: no route");
        require(amount > 0, "Omni: zero");

        if (tc.mode == Mode.MintBurn) {
            IBridgeToken(tc.token).burn(msg.sender, amount);
        } else {
            require(IBridgeToken(tc.token).transferFrom(msg.sender, address(this), amount), "Omni: pull failed");
        }

        bytes memory message = abi.encode(tokenId, to, amount);
        if (endpoint != address(0)) {
            ILzEndpoint(endpoint).send{value: msg.value}(dstEid, message, lzOptions, msg.sender);
        }
        emit SentOut(tokenId, dstEid, to, amount, msg.sender);
    }

    // ---------------- inbound: any chain -> nuChain ----------------

    /// Called by the LayerZero endpoint on inbound (phase 3: guarded by
    /// lzReceive auth + peer(srcEid) check). MintBurn tokens are minted to the
    /// recipient; LockRelease tokens are released from local liquidity.
    /// From here the recipient can hold the ERC-20, IBC it out via x/erc20, or
    /// route it onward to another EVM chain with sendOut — the hub in action.
    function lzReceive(uint32 srcEid, bytes32 guid, bytes calldata message) external {
        require(msg.sender == endpoint, "Omni: not endpoint");
        require(!consumed[guid], "Omni: replay");
        consumed[guid] = true;

        (bytes32 tokenId, bytes32 to32, uint256 amount) = abi.decode(message, (bytes32, bytes32, uint256));
        require(routes[tokenId][srcEid].enabled, "Omni: unknown source route");
        TokenConfig memory tc = tokens[tokenId];
        address to = address(uint160(uint256(to32)));

        if (tc.mode == Mode.MintBurn) {
            IBridgeToken(tc.token).mint(to, amount);
        } else {
            require(IBridgeToken(tc.token).transfer(to, amount), "Omni: release failed");
        }
        emit ReceivedIn(tokenId, srcEid, to, amount);
    }

    // ---------------- WATTx integration ----------------
    // wWTX arrives via NuChainBridge (WTX locked on WATTx -> wWTX minted here by
    // the relayer). Registering wWTX as a MintBurn token wires WATTx into the
    // same omnichain routing as every LayerZero and IBC asset — one WTX can
    // originate on WATTx and end up on Ethereum, Osmosis, or Base.

    function views_tokenId(string calldata symbol) external pure returns (bytes32) {
        return keccak256(bytes(symbol));
    }
}
