# nuChain deployments

## WATTx L1 (chain 22356, EVM) — LIVE
| Contract | Address |
|---|---|
| NuChainBridge | `0xcf0fc8662b54a3f222bd9dedf6cb35c42fa1e896` |

## nuChain (EVM 28277, live on Legion) — LIVE
| Contract | Address | Role |
|---|---|---|
| WrappedWTX (wWTX) | `0x3D641a2791533B4A0000345eA8d509d01E1ec301` | WTX on nuChain, 1:1, minted by relayer on WATTx lock |
| OmniBridgeRouter | `0x07Aa076883658B7ED99D25b1E6685808372C8fE2` | universal LayerZero/WTX/IBC router |

### Wired & proven (2026-08-01)
- wWTX minted (WATTx→nuChain leg): relayer mint path works.
- Router registered `keccak("WTX")` → wWTX in **LockRelease** mode (nuChain locks
  wWTX; the remote chain mints WTX-ERC20).
- Router linked to NuChainBridge on WATTx.
- Route set: WTX → Base Sepolia (LZ EID 40245), peer pending.
- **Outbound proven**: `sendOut` of 100 wWTX locked it in the router
  (user 1000→900, router 0→100). Only the LayerZero Endpoint wiring + the
  remote peer OFT remain to complete a real cross-chain delivery.

## Remaining to finish a live WTX→Ethereum/Base delivery
1. Vendor LayerZero Endpoint V2, deploy on nuChain, `router.setEndpoint(...)`.
2. Deploy a peer OFT on the remote testnet (Base Sepolia), register under
   `keccak("WTX")`, `router.setRoute(...peer...)`.
3. Enable `x/erc20` and register wWTX as a token pair for the IBC door.
4. Run the WATTx→nuChain relayer (watch NuChainBridge.WTXLocked → mint wWTX).
