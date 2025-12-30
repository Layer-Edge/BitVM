# Namada Privacy Integration - Quick Start

## Overview

Add privacy to your Bitcoin-to-Cosmos EVM bridge using Namada's shielded pool.

## Architecture

```
Bitcoin → Bridge → Cosmos EVM (Transparent) → Namada (Shielded) → Cosmos EVM (Private)
```

## 3-Step Setup

### 1. Install Namada

```bash
curl -L https://github.com/anoma/namada/releases/latest/download/namada-0.23.0-Linux-x86_64.tar.gz | tar -xz
sudo mv namada-0.23.0-Linux-x86_64/namada /usr/local/bin/
namada client utils join-network --chain-id namada-mainnet
```

### 2. Create Shielded Address

```bash
namada wallet gen --alias my-shielded --shielded
# Save the address (starts with "namada1...")
```

### 3. Deploy Privacy Bridge

```bash
# Deploy NamadaPrivacyBridge contract
npx hardhat run scripts/deploy-privacy.js --network cosmosEVM

# Register your shielded address
cast send $PRIVACY_BRIDGE_ADDRESS \
  "registerShieldedAddress(string)" \
  "namada1your-shielded-address-here" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## Usage

### Bridge with Privacy

```bash
# 1. Normal peg-in (transparent)
./target/release/bridge initiate-peg-in \
  --utxo <TXID>:<VOUT> \
  --destination_address 0xYourCosmosEVMAddress

# 2. Call privacy bridge to transfer to Namada
cast send $PRIVACY_BRIDGE_ADDRESS \
  "mintPegInWithPrivacy(address,uint256,bytes32,bool)" \
  $YOUR_ADDRESS \
  $AMOUNT \
  $BITCOIN_PUBKEY \
  true \
  --rpc-url $RPC_URL

# 3. Funds are now in Namada shielded pool (private)
```

### Check Privacy Status

```bash
# Check if address is registered
cast call $PRIVACY_BRIDGE_ADDRESS \
  "getShieldedAddress(address)" \
  $YOUR_ADDRESS \
  --rpc-url $RPC_URL

# Check pending transfers
cast call $PRIVACY_BRIDGE_ADDRESS \
  "getPendingTransfer(address)" \
  $YOUR_ADDRESS \
  --rpc-url $RPC_URL
```

## Privacy Levels

| Level | Description | Privacy |
|-------|-------------|---------|
| **Transparent** | Standard bridge | ❌ None |
| **Shielded** | Via Namada | ✅ Full |

## Key Benefits

✅ **Hide Amounts**: Transaction amounts are private
✅ **Hide Addresses**: Sender/receiver are hidden
✅ **Unlinkable**: Transactions can't be linked
✅ **Multi-Asset**: Works with any asset

## Important Notes

⚠️ **Initial Transfer**: Bitcoin → Cosmos EVM is still transparent
⚠️ **IBC Required**: Need IBC connection to Namada
⚠️ **Pool Size**: Larger shielded pool = better privacy
⚠️ **Fees**: Additional IBC transfer fees apply

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Shielded address not registered" | Call `registerShieldedAddress` first |
| "Invalid Namada address format" | Ensure address starts with "namada1" |
| IBC transfer fails | Check IBC channel is open and configured |

## Next Steps

See [NAMADA_PRIVACY_INTEGRATION.md](./NAMADA_PRIVACY_INTEGRATION.md) for detailed implementation.

