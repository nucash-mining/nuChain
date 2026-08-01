# nuChain

**The omnichain bridge hub — a Cosmos-SDK chain routing assets between WATTx, every EVM chain (LayerZero), and every Cosmos chain (IBC). Also a full zk-rollup EVM anchored to WATTx.**

nuChain is a Cosmos SDK + CometBFT chain (~1-second finality) with a full EVM
(cosmos/evm), IBC connectivity, LayerZero endpoints, and hardware-mineable zk
validity proofs. It settles to **WATTx** — the hybrid PoW/PoS, seven-algorithm
merged-mined L1 — so anchored nuChain history is as hard to rewrite as WATTx
itself.

WTX bridges in as **wWTX** (1:1, satoshi-exact) and, through the x/erc20
module, becomes a native denom that travels the entire Cosmos ecosystem over
IBC — and out to Ethereum/BSC/Polygon/Base over LayerZero.

```
  dApps (TruthMarket, Mining Game, any EVM contract)
     │
  nuChain — Cosmos SDK + cosmos/evm · ~1s blocks · IBC · LayerZero · zk
     │  epoch anchors (CometBFT app_hash → WATTx EVM)
  WATTx L1 — hybrid PoW/PoS, 7-algo AuxPoW merged mining
```

## Why it exists

- **1-second blocks** — the fast execution layer the 120s WATTx L1 was never
  meant to be. CometBFT gives instant finality; WATTx gives settlement security.
- **WTX goes multichain** — locked on WATTx, minted as wWTX on nuChain, then
  IBC across Cosmos (Osmosis, the Hub, …) or LayerZero to the EVM world.
- **zk where it pays** — private ballots (kill vote-buying), no-KYC personhood
  (sybil-resistant citizenship), and rollup validity proofs that are **mined**:
  the first valid proof per epoch wins a bounty, an eighth algorithm alongside
  WATTx's seven PoW algos. See [`zk/README.md`](zk/README.md).

## Layout

| Path | What |
|---|---|
| `contracts/NuChainBridge.sol` | WATTx-side: epoch anchoring, WTX lock/release vault, bonded relayers, zk verifier hook, proof-mining bounties |
| `contracts/WrappedWTX.sol` | wWTX on nuChain — mint against locked WTX, burn to withdraw, x/erc20-registerable |
| `contracts/WTXOFTAdapter.sol` | LayerZero OFT endpoint — wWTX to non-Cosmos EVM chains |
| `relayer/anchor-relayer.js` | CometBFT → wattx-cli epoch anchor poster |
| `registry/` | Cosmos Chain Registry (`chain.json`, `assetlist.json`) + Keplr config |
| `wallets/vidulum-nuchain.json` | Vidulum wallet asset config for NU + wWTX |
| `zk/` | circuit designs: ballot (MACI), personhood (Semaphore), epoch (validity) |
| `docs/ARCHITECTURE.md` | full phase plan |

## Chain identity

- Cosmos chain-id: `nuchain_28277-1`  ·  EVM chain-id: `28277`  ·  bech32: `nu`
- native token: **NU** (`anu`, 18 dec)  ·  bridged: **wWTX** (`erc20/wWTX`, 8 dec)
- built from cosmos/evm `evmd`; binary `nuchaind`

## Local devnet

```bash
# from the cosmos/evm checkout
CHAIN_ID=nuchain_28277-1 ./local_node.sh -y
# CometBFT RPC :26657 · EVM JSON-RPC :18545 (0x6e75 = 28277)
```

Deploy any EVM contract with the funded dev key — TruthMarket's contracts
(0.8.19/paris) deploy unchanged; MandateToken was the first live deploy.

## Status

Devnet live (1s blocks, EVM verified). Bridge + wWTX + OFT + registry + zk
designs committed. Pending: WATTx-side bridge deploy (blocked on WATTx wallet),
zk circuit implementation, public endpoints, IBC/LayerZero peer wiring.

Supersedes the earlier [`nuChain-Z`](https://github.com/nucash-mining/nuChain-Z)
scaffold (ideas ported: x/pow, x/mining, Cysic zk-oracle, Mining Game contracts).
