# nuChain zk circuits

"zk where it pays" — three circuits, each closing a concrete attack or cost,
not zk-for-marketing. All Groth16 (BN254) so proofs verify cheaply on the
WATTx EVM and are mineable on commodity/Cysic hardware.

## 1. `ballot.circom` — MACI-style private ballots
**Problem it kills:** vote-buying and coercion. Today every ScopedGovernor
vote is public, so a briber can pay for a provable vote. A receipt-free
scheme makes it *impossible to prove to anyone how you voted*.
**Shape:** voter encrypts (proposalId, choice) to the coordinator key; a
nullifier prevents double-voting; the coordinator publishes an encrypted
tally and a Groth16 proof that the tally correctly decrypts the ballots.
Only the aggregate is ever revealed. Directly defuses the delegation-buying
attack flagged as TruthMarket's biggest surface.

## 2. `personhood.circom` — Semaphore uniqueness nullifier
**Problem it solves:** sybil resistance for the citizen NFT without KYC.
A holder proves membership in the personhood set (Merkle root of registered
identity commitments) and derives a per-context nullifier, proving "I am one
unique registered human" while revealing nothing about which one.
**Shape:** identity = (trapdoor, nullifier); public = Merkle root + external
nullifier; output = signal nullifier hash. This is the automated, no-KYC
citizenship path (replaces the testnet self-registrar on mainnet).

## 3. `epoch.circom` — rollup validity proof (the mined one)
**Problem it solves:** upgrade WATTx anchors from economically-challenged to
validity-proven, and make proving a hardware-mined activity.
**Shape:** proves the nuChain state transition from anchor N to N+1 is valid
(app-hash → app-hash under the state-transition function). First valid proof
per epoch claims the bounty in NuChainBridge.submitProof — the eighth
"algorithm" in the mining economy. Cysic provers or self-hosted GPU/FPGA.

## Toolchain (to add when building)
- circom 2.x + snarkjs for circuit compilation and Groth16 setup
- solidity verifier export (`snarkjs zkey export solidityverifier`) →
  wired into NuChainBridge.verifier and a MaciTally verifier
- Cysic prover integration for #3 (and #1 tally proofs) — port the
  proving-job/bounty client from nuChain-Z's cysic-hardware-miner.py

## Status
Design + interfaces fixed here; circuit implementation is phase 2 of
docs/ARCHITECTURE.md. The verifier hook (NuChainBridge.setVerifier /
submitProof) and the bounty economics already exist on-chain, so circuits
drop in without contract changes.
