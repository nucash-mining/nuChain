#!/usr/bin/env node
// nuChain -> WATTx anchor relayer (phase 1).
// Reads nuChain block headers via CometBFT RPC every EPOCH blocks and posts
// (height, app_hash, time) to NuChainBridge on the WATTx EVM.
//
// WATTx side uses the node's own wallet via sendtocontract (Qtum-style),
// so no EVM private key is needed here — the wattx-cli wallet signs.
//
// Env:
//   NUCHAIN_RPC   default http://127.0.0.1:26657
//   WATTX_CLI     default ~/wattx-0.1.7.2/wattx-cli -datadir=~/.wattx
//   BRIDGE_ADDR   NuChainBridge contract address (hex, no 0x)
//   SENDER        WATTx base58 sender address (bonded relayer)
//   EPOCH         default 600 nuChain blocks (~10 min at 1s blocks)

import { execFileSync } from "child_process";

const NUCHAIN_RPC = process.env.NUCHAIN_RPC || "http://127.0.0.1:26657";
const WATTX_CLI = (process.env.WATTX_CLI ||
  `${process.env.HOME}/wattx-0.1.7.2/wattx-cli -datadir=${process.env.HOME}/.wattx`).split(" ");
const BRIDGE = process.env.BRIDGE_ADDR;
const SENDER = process.env.SENDER;
const EPOCH = parseInt(process.env.EPOCH || "600");

if (!BRIDGE || !SENDER) {
  console.error("BRIDGE_ADDR and SENDER are required");
  process.exit(1);
}

// anchor(uint64,bytes32,uint64) selector
const SELECTOR = "e63a3e0f"; // placeholder — recompute at deploy: keccak("anchor(uint64,bytes32,uint64)")[:4]

const pad = (hex, n = 64) => hex.replace(/^0x/, "").padStart(n, "0");

async function nuHeader() {
  const r = await fetch(`${NUCHAIN_RPC}/block`);
  const j = await r.json();
  const h = j.result.block.header;
  return {
    height: parseInt(h.height),
    appHash: h.app_hash.toLowerCase(),
    time: Math.floor(new Date(h.time).getTime() / 1000),
  };
}

function wattxSend(data) {
  const out = execFileSync(WATTX_CLI[0],
    [...WATTX_CLI.slice(1), "sendtocontract", BRIDGE, data, 0, 250000, 0.0000004, SENDER],
    { encoding: "utf8" });
  return JSON.parse(out).txid;
}

let lastAnchored = 0;
console.log(`anchor-relayer: nuChain=${NUCHAIN_RPC} bridge=${BRIDGE} epoch=${EPOCH}`);

setInterval(async () => {
  try {
    const h = await nuHeader();
    if (h.height >= lastAnchored + EPOCH) {
      const data = SELECTOR + pad(h.height.toString(16)) + pad(h.appHash) + pad(h.time.toString(16));
      const txid = wattxSend(data);
      lastAnchored = h.height;
      console.log(`anchored nuChain #${h.height} appHash=${h.appHash.slice(0, 16)}… wattx txid=${txid}`);
    }
  } catch (e) {
    console.error("relayer error:", e.message);
  }
}, 15000);
