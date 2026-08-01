# Listing nuChain in the Vidulum App wallet

The Vidulum App (vidulum.app, by BZE/Vidulum team) adds Cosmos-SDK chains by
request. What to submit when the public testnet endpoints are live:

1. **Chain metadata** — everything in `chain.json` / `keplr-chain.json` here:
   - chain id `nuchain_28277-1`, bech32 prefix `nu`, coin type 60
     (eth_secp256k1 keys — confirm Vidulum supports coinType 60 chains,
     they list Evmos-lineage chains so the path exists)
   - native coin NU (base `anu`, 18 decimals), bridged asset wWTX (8 decimals)
2. **Public endpoints** (required): RPC :26657, REST :1317, gRPC :9090 —
   put these behind the existing wattxchange.app