# nuChain circuits (circom / Groth16, BN254)

## personhood.circom
Semaphore-style unique-personhood proof (20-level Merkle tree = up to ~1M
citizens). Proves membership in the citizen set + a per-context nullifier,
revealing nothing about which citizen. This is the automated, no-KYC
citizenship + double-action guard for TruthMarket and governance.

Public inputs: `merkleRoot`, `externalNullifier`, `signalHash`
Output: `nullifierHash`

## Build

```bash
npm i -g circom snarkjs           # or use the rust circom binary
npm i circomlib

# compile
circom personhood.circom --r1cs --wasm --sym -l node_modules

# trusted setup (Groth16) — use a real ceremony ptau for production
snarkjs powersoftau new bn128 14 pot14_0.ptau
snarkjs powersoftau prepare phase2 pot14_0.ptau pot14.ptau
snarkjs groth16 setup personhood.r1cs pot14.ptau personhood_0.zkey
snarkjs zkey contribute personhood_0.zkey personhood.zkey
snarkjs zkey export verificationkey personhood.zkey vkey.json

# solidity verifier -> wire into the citizen registry / MACI coordinator
snarkjs zkey export solidityverifier personhood.zkey PersonhoodVerifier.sol
```

## Roadmap circuits (designed, not yet written)
- `ballot.circom` — MACI receipt-free vote (encrypt to coordinator key,
  nullifier per proposal); coordinator posts a Groth16 tally proof. Kills
  vote-buying.
- `epoch.circom` — nuChain state-transition validity proof; the one MINED for
  bounties in NuChainBridge.submitProof (Cysic / GPU / FPGA provers race).

The bridge already exposes `setVerifier` + `submitProof(bytes)`, so exported
Solidity verifiers drop in without contract changes.
