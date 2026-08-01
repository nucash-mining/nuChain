# nuChain as the omnichain bridge hub

nuChain's purpose: be the Cosmos-SDK hub where **WATTx (WTX)**, **LayerZero
(every EVM chain)**, and **IBC (every Cosmos chain)** meet, so any asset on any
connected chain can reach any other by hopping through nuChain once. It is a
router, not a destination.

```
        Ethereum   BSC   Polygon   Base   Arbitrum        (EVM chains)
            \       |       |        |       /
             \      |    LayerZero   |      /
              \     |       |        |     /
               ▼    ▼       ▼        ▼    ▼
        ┌───────────────────────────────────────────┐
 WATTx  │            nuChain  (Cosmos SDK + EVM)     │   Osmosis, Hub,
 (WTX)  │   NuChainBridge ── OmniBridgeRouter ── x/erc20   Injective, …
   ●────┤   (lock/mint)      (LayerZero in/out)   (IBC)├────●  (Cosmos chains)
        │            every bridged asset = ERC-20      │
        └───────────────────────────────────────────┘
```

## Why a hub beats N×N bridges

Direct bridges between every pair of chains is an N² problem — every new chain
needs a bridge to every existing one, and each bridge is its own trust surface.
A hub is N: each chain connects once, to nuChain. WTX↔Ethereum, WTX↔Osmosis,
USDT(Polygon)↔Base, ETH↔Injective — all are two hops through the same audited
router, sharing one security model (nuChain's validator set + the anchor to
WATTx).

## The three transports

| Transport | In to nuChain | Out of nuChain | Contract / module |
|---|---|---|---|
| **WATTx** | lock WTX on WATTx → relayer mints wWTX | burn wWTX → relayer releases WTX | `NuChainBridge` (WATTx EVM) + `WrappedWTX` |
| **LayerZero** | remote OFT sends → `lzReceive` mints/releases | `sendOut` burns/locks → remote OFT | `OmniBridgeRouter` (+ per-chain peer OFTs) |
| **IBC** | IBC transfer → x/erc20 → ERC-20 | ERC-20 → x/erc20 → IBC transfer | cosmos/evm `x/erc20` module |

Every asset lands on nuChain as an **ERC-20**. That is the unifying trick: once
an asset is an ERC-20 on nuChain, `x/erc20` makes it a native Cosmos denom
(IBC-transferable) AND `OmniBridgeRouter` makes it LayerZero-transferable — the
same balance, two exit doors.

## Asset identity across chains

`tokenId = keccak256(symbol)` lines an asset up across every chain: `keccak("WTX")`,
`keccak("USDT")`, `keccak("ETH")`. Each remote chain runs a peer OFT registered
under the same tokenId, so the router always knows "this inbound message is WTX"
regardless of which chain it came from.

Two token modes:
- **MintBurn** — wrapped assets whose canonical supply lives elsewhere (wWTX,
  wrapped remote tokens). Minted on inbound, burned on outbound.
- **LockRelease** — assets whose canonical liquidity sits on nuChain. Pulled and
  held on outbound, released on inbound.

## Example: one WTX, three destinations

1. **WTX → Ethereum.** Lock WTX in `NuChainBridge` → wWTX minted on nuChain →
   `OmniBridgeRouter.sendOut(keccak("WTX"), ETH_EID, …)` burns wWTX → LayerZero
   → peer OFT on Ethereum mints WTX-ERC20.
2. **WTX → Osmosis.** Lock WTX → wWTX on nuChain → `x/erc20` converts to native
   `erc20/wWTX` denom → IBC transfer to Osmosis.
3. **WTX → Base, then onward to BSC.** Route to Base via LayerZero, or just
   `sendOut` again from nuChain to BSC — the hub re-routes without ever touching
   WATTx again.

All reversible; burns/locks on the way out are releases/mints on the way back,
replay-guarded by LayerZero GUID and IBC sequence.

## Security posture

- **nuChain validator set** orders and executes every hop (CometBFT BFT).
- **Anchoring to WATTx** (`NuChainBridge` epoch anchors) makes nuChain history
  as hard to rewrite as WATTx — merged-mined across seven algorithms.
- **LayerZero** provides the cross-EVM message security (DVN set per route).
- **Bonded relayers** on the WATTx leg; **zk validity proofs** upgrade anchors
  from economic to proven (mined for bounties — see `zk/`).
- Hub design means one router to audit, not N² bridges.

## Build status

| Piece | State |
|---|---|
| `NuChainBridge` (WATTx leg) | **deployed on WATTx EVM** `0xcf0fc866…e896` |
| `WrappedWTX` | written; deploy on nuChain |
| `OmniBridgeRouter` | written, compiles; deploy on nuChain, attach LZ endpoint |
| `WTXOFTAdapter` | WTX-specific OFT (superseded by the generic router for new assets) |
| `x/erc20` IBC path | cosmos/evm module — enable + register token pairs |
| Per-chain peer OFTs | deploy one per remote EVM chain, register under tokenId |

Next: deploy `WrappedWTX` + `OmniBridgeRouter` on the live nuChain node
(Legion), vendor LayerZero Endpoint V2, wire the first peer (Base or BSC
testnet), and register the WTX tokenId end to end.
