pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";

// Semaphore-style unique-personhood proof for nuChain / TruthMarket citizens.
//
// A holder proves: "I am one registered human in the citizen set, and this is
// my nullifier for a given context" — revealing nothing about WHICH human.
//
// identityCommitment = Poseidon(identityNullifier, identityTrapdoor)
// The commitment is a leaf in the citizen Merkle tree (root = public input).
// nullifierHash = Poseidon(identityNullifier, externalNullifier) prevents the
// same person acting twice in the same context (a vote, a registration) while
// staying unlinkable across contexts.

template MerkleProof(nLevels) {
    signal input leaf;
    signal input pathElements[nLevels];
    signal input pathIndices[nLevels];  // 0 = leaf on left, 1 = leaf on right
    signal output root;

    component hashers[nLevels];
    signal left[nLevels];
    signal right[nLevels];
    signal cur[nLevels + 1];
    cur[0] <== leaf;

    for (var i = 0; i < nLevels; i++) {
        // pathIndices[i] must be boolean
        pathIndices[i] * (1 - pathIndices[i]) === 0;

        left[i]  <== cur[i] + pathIndices[i] * (pathElements[i] - cur[i]);
        right[i] <== pathElements[i] + pathIndices[i] * (cur[i] - pathElements[i]);

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== left[i];
        hashers[i].inputs[1] <== right[i];
        cur[i + 1] <== hashers[i].out;
    }
    root <== cur[nLevels];
}

template Personhood(nLevels) {
    // private
    signal input identityNullifier;
    signal input identityTrapdoor;
    signal input pathElements[nLevels];
    signal input pathIndices[nLevels];
    // public
    signal input merkleRoot;
    signal input externalNullifier;
    signal input signalHash;      // binds the proof to a message (anti-tamper)
    // output
    signal output nullifierHash;

    // identity commitment = Poseidon(nullifier, trapdoor)
    component commit = Poseidon(2);
    commit.inputs[0] <== identityNullifier;
    commit.inputs[1] <== identityTrapdoor;

    // membership: commitment is a leaf under merkleRoot
    component mt = MerkleProof(nLevels);
    mt.leaf <== commit.out;
    for (var i = 0; i < nLevels; i++) {
        mt.pathElements[i] <== pathElements[i];
        mt.pathIndices[i] <== pathIndices[i];
    }
    mt.root === merkleRoot;

    // per-context nullifier
    component nh = Poseidon(2);
    nh.inputs[0] <== identityNullifier;
    nh.inputs[1] <== externalNullifier;
    nullifierHash <== nh.out;

    // constrain signalHash into the circuit so the proof can't be replayed
    // against a different signal (squared to prevent optimizer stripping)
    signal signalSq;
    signalSq <== signalHash * signalHash;
}

component main {public [merkleRoot, externalNullifier, signalHash]} = Personhood(20);
