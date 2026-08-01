# nuChain — L2 zk-Rollup EVM anchored to WATTx

Working architecture, 2026-08-01. Supersedes the nuChain-Z scaffold
(github.com/nucash-mining/nuChain-Z — kept for its ideas: x/pow, x/mining,
Cysic zk-oracle, Mining Game contracts; its build was aspirational and is
not resurrected).

## Stack

```
  dApps: TruthMarket (separate repo) · Mining Game · anything EVM
     │
  ┌──▼──────────────────────────────────────────────┐
  │ nuChain — Cosmos SDK + CometBFT (~1s finality)  │
  │  · cosmos/evm module → full EVM, chain-id TBD   │
  │  · IBC to Cosmos world                          │
  │  · LayerZero endpoints (phase 3)                │
  │  · zk circuits where they PAY (phase 2):        │
  │      MACI private ballots (anti vote-buying)    │
  │      Semaphore nullifiers (citizen uniqueness)  │
  └──┬──────────────────────────────────────────────┘
     │ epoch anchors: (height, CometBFT app_hash, time)
  ┌──▼──────────────────────────────────────────────┐
  │ WATTx L1 — hybrid PoW/PoS, 7-algo AuxPoW        │
  │  NuChainBridge.sol (WATTx EVM):                 │
  │   phase 1: bonded relayers, dispute window      │
  │   phase 2: zk validity proofs (swappable        │
  │            verifier; Cysic or zk light client)  │
  └─────────────────────────────────────────────────┘
```

## Why this shape

- **1-second blocks live HERE**, not on WATTx. CometBFT gives instant
  finality natively; the 120s WATTx L1 stays untouched as the security
  anchor. This resolves the "wasn't it supposed to be 1s?" question — the
  two designs were always two layers.
- **The EVM comes from cosmos/evm** (Apache-2.0, Interchain Labs; the
  ex-Evmos core). Its example chain `evmd` is the base — renamed nuchaind.
  Solidity dApps (TruthMarket's contracts are 0.8.19/paris) deploy unchanged.
- **Anchoring makes it a rollup on WATTx**, not a floating sidechain:
  every epoch, the CometBFT `app_hash` (which commits ALL nuChain state,
  including the EVM) lands in NuChainBridge on the WATTx EVM. Reorging
  anchored nuChain history then requires rewriting WATTx — which is
  merged-mined across seven algorithms.
- **"zk where it pays", not "zk" as an adjective:**
  1. MACI-style private ballots — receipts-free voting kills the
     vote-buying/coercion channel (TruthMarket's biggest attack surface).
  2. Semaphore uniqueness nullifiers — the citizen-NFT proof-of-personhood
     object, same proving stack.
  3. Rollup validity proofs (phase 2) — upgrade anchors from
     economically-challenged to proven. Verifier contract is swappable;
     candidate provers: Cysic (the nuChain-Z concept), or a CometBFT zk
     light client.
- **Privacy is in circuits, not consensus.** Consensus stays boring
  (CometBFT). "Privacy consensus" as a marketing phrase = these circuits.

## Proof mining (Cysic + any hardware prover)

Validity proofs are not a backend service — they are MINED. Ported from the
nuChain-Z concept (CysicZkOracle.sol + cysic-hardware-miner.py) and wired
into NuChainBridge:

- Each anchored epoch is an open proving job. Anyone with proving hardware —
  Cysic network provers, self-hosted GPU/FPGA rigs — races to generate the
  validity proof for the epoch's state transition.
- **First valid `submitProof` wins the epoch bounty** (funded pool on the
  bridge, satoshi-denominated on WATTx). Proof generation becomes an eighth
  algorithm in the mining economy, next to the seven PoW algos — hardware
  that can't hash competitively can prove instead.
- Same pattern extends to MACI tally proofs and any other circuit the
  ecosystem needs: post job, bounty, first valid proof paid.
- **Mining Game hook (later):** prover rigs can be represented as Mining
  Game NFT components with "proof hashrate" stats, and a slice of proof
  bounties can route through the Mining Game pool economy (same 1%-fee
  pattern as merged mining). The old CysicZkOracle contract is the starting
  point for this bridge.

## Phases

| Phase | Deliverable | Status |
|---|---|---|
| 0 | nuchaind (evmd) builds + local devnet, 1s blocks, EVM live | building |
| 1 | NuChainBridge.sol on WATTx + anchor-relayer posting epochs | contract + relayer written; deploy blocked on WATTx wallet unlock |
| 1.5 | TruthMarket contracts deployed on nuChain devnet | after 0 |
| 2 | MACI ballots + Semaphore nullifier circuits; validity-proof verifier | design |
| 3 | LayerZero endpoints (USDT in from majors, revenue out), IBC open | design |
| 4 | Decentralize sequencer set; bonded relayer set governance | design |

## Repo layout (this repo — nuchain)

- `contracts/NuChainBridge.sol` — WATTx-side anchor contract (phase 1 + 2 hooks)
- `relayer/anchor-relayer.js` — CometBFT → wattx-cli sendtocontract epoch poster
- `docs/ARCHITECTURE.md` — this file
- chain source: built from cosmos/evm `evmd` (vendored/forked as needed)

## WATTx-side gotchas (from prior deploys)

- `msg.value` is satoshi-denominated on the WATTx EVM (relayer bonds!)
- node needs `-txindex -logevents` (already set in ~/.wattx/wattx.conf)
- deploy via `createcontract`/`sendtocontract` (Qtum-style; no raw EVM txs)
- deployment currently blocked on the encrypted `nu` wallet passphrase
  (backups + recovery ladder documented in session notes)
