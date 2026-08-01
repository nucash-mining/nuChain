# nuChain deployments

## WATTx L1 (chain 22356, EVM) — LIVE
| Contract | Address | Notes |
|---|---|---|
| NuChainBridge | `0xcf0fc8662b54a3f222bd9dedf6cb35c42fa1e896` | deployed 2026-08-01, tx `78d6a800813e0a47fe5c76f7f8562245206873b76dd4934f53b69d406166d6e4`, ctor(relayerBond=100 WTX, epochBlocks=600), gas 1,563,948, status OK |

## nuChain (EVM 28277) — pending public devnet
| Contract | Address | Notes |
|---|---|---|
| MandateToken | `0x3D641a2791533B4A0000345eA8d509d01E1ec301` | proven on local devnet |
| WrappedWTX | TBD | deploy after bridge, register with x/erc20 |
| WTXOFTAdapter | TBD | LayerZero phase 3 |

## Next wiring
1. Deploy WrappedWTX on nuChain; `WrappedWTX.setBridge(relayer)`.
2. Bond a relayer on NuChainBridge (`bondRelayer{value:100 WTX}`), run anchor-relayer.js.
3. Test round-trip: lockWTX on WATTx -> mint wWTX on nuChain -> IBC.
4. When circuits built: `NuChainBridge.setVerifier(PersonhoodVerifier)` / epoch verifier.
