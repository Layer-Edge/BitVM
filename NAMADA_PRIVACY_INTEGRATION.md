# Integrating Namada Protocol for Privacy

This guide explains how to integrate Namada protocol to add privacy features to your Bitcoin-to-Cosmos EVM bridge.

## Table of Contents

1. [Overview](#overview)
2. [Namada Privacy Features](#namada-privacy-features)
3. [Integration Approaches](#integration-approaches)
4. [Architecture Design](#architecture-design)
5. [Implementation Guide](#implementation-guide)
6. [Code Modifications](#code-modifications)
7. [Testing](#testing)
8. [Security Considerations](#security-considerations)

---

## Overview

### Current Bridge Privacy Status

The current BitVM bridge implementation has **no built-in privacy features**:

- ❌ Bitcoin addresses are visible on-chain
- ❌ Amounts are visible in events
- ❌ Transaction history is traceable
- ❌ Depositor/withdrawer addresses are linked

### What Namada Provides

Namada adds privacy through:

- ✅ **Shielded Transfers**: Hide sender, receiver, and amounts using zk-SNARKs
- ✅ **Multi-Asset Support**: Privacy for any asset via MASP (Multi-Asset Shielded Pool)
- ✅ **Cross-Chain Privacy**: Privacy maintained across IBC-connected chains
- ✅ **Unlinkability**: Transactions cannot be linked to each other

---

## Namada Privacy Features

### 1. Multi-Asset Shielded Pool (MASP)

Namada's MASP is a zero-knowledge circuit that:
- Extends Zcash Sapling protocol
- Supports any asset type
- Provides transaction privacy (amounts, senders, receivers)
- Uses zk-SNARKs for verification

### 2. Shielded Addresses

- **Transparent addresses**: Public, traceable (like current bridge)
- **Shielded addresses**: Private, untraceable (Namada provides)

### 3. IBC Integration

Namada supports Inter-Blockchain Communication (IBC), enabling:
- Cross-chain private transfers
- Privacy across Cosmos ecosystem
- Integration with Cosmos EVM chains

---

## Integration Approaches

### Approach 1: Namada as Intermediate Layer (Recommended)

**Architecture:**
```
Bitcoin → Bridge → Cosmos EVM → Namada (Shielded) → Cosmos EVM (Private)
```

**Flow:**
1. User bridges Bitcoin to Cosmos EVM (transparent)
2. User transfers to Namada via IBC
3. User performs shielded transfer on Namada
4. User transfers back to Cosmos EVM (now private)

**Pros:**
- Minimal changes to existing bridge
- Leverages Namada's existing infrastructure
- Users control privacy level
- Works with any Cosmos EVM chain

**Cons:**
- Requires additional IBC transfers
- Users need Namada wallet
- Additional transaction fees

### Approach 2: Direct Namada Integration

**Architecture:**
```
Bitcoin → Bridge → Namada (Shielded) → Cosmos EVM (Private)
```

**Flow:**
1. User bridges Bitcoin directly to Namada
2. Bridge contract mints on Namada (shielded)
3. User transfers to Cosmos EVM via IBC (maintains privacy)

**Pros:**
- Maximum privacy from the start
- No transparent phase
- Direct integration

**Cons:**
- Requires significant bridge modifications
- Need Namada-specific contracts
- More complex implementation

### Approach 3: Hybrid Privacy Bridge

**Architecture:**
```
Bitcoin → Bridge → Cosmos EVM (with privacy option)
                    ↓
              User chooses:
              - Transparent (current)
              - Shielded (via Namada)
```

**Flow:**
1. Bridge supports both transparent and shielded modes
2. Users choose privacy level during peg-in
3. Shielded mode routes through Namada

**Pros:**
- Backward compatible
- User choice
- Flexible

**Cons:**
- Most complex implementation
- Requires both transparent and shielded paths

---

## Architecture Design

### Recommended: Approach 1 (Namada as Intermediate Layer)

```
┌─────────────┐
│   Bitcoin   │
└──────┬──────┘
       │ Peg-In (Transparent)
       ▼
┌─────────────────────┐
│  BitVM Bridge        │
│  (Cosmos EVM)        │
└──────┬──────────────┘
       │ Mint wrapped BTC
       ▼
┌─────────────────────┐
│  Cosmos EVM Chain   │
│  (Transparent)      │
└──────┬──────────────┘
       │ IBC Transfer
       ▼
┌─────────────────────┐
│     Namada          │
│  (Shielded Pool)    │
│  - Hide amounts     │
│  - Hide addresses   │
│  - Unlinkable       │
└──────┬──────────────┘
       │ Shielded Transfer
       ▼
┌─────────────────────┐
│     Namada          │
│  (Shielded Output)  │
└──────┬──────────────┘
       │ IBC Transfer (Private)
       ▼
┌─────────────────────┐
│  Cosmos EVM Chain   │
│  (Private Output)   │
└─────────────────────┘
```

---

## Implementation Guide

### Step 1: Set Up Namada Integration

#### 1.1 Install Namada CLI

```bash
# Install Namada
curl -L https://github.com/anoma/namada/releases/latest/download/namada-0.23.0-Linux-x86_64.tar.gz | tar -xz
sudo mv namada-0.23.0-Linux-x86_64/namada /usr/local/bin/
```

#### 1.2 Configure Namada

```bash
# Initialize Namada
namada client utils join-network --chain-id namada-mainnet

# Create shielded address
namada wallet gen --alias my-shielded-address --shielded
```

### Step 2: Create Namada Bridge Contract

Create a new contract that interfaces with Namada via IBC:

```solidity
// bridge/contracts/NamadaPrivacyBridge.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BitVMBridge.sol";

/**
 * @title NamadaPrivacyBridge
 * @notice Extends BitVMBridge with Namada privacy integration
 */
contract NamadaPrivacyBridge is BitVMBridge {
    // IBC channel to Namada
    string public namadaChannelId;
    
    // Mapping: user address -> Namada shielded address
    mapping(address => string) public userShieldedAddresses;
    
    // Events
    event PrivacyTransferInitiated(
        address indexed user,
        string namadaShieldedAddress,
        uint256 amount,
        bool isShielded
    );
    
    event PrivacyTransferCompleted(
        address indexed user,
        uint256 amount,
        bool wasShielded
    );
    
    constructor(
        string memory _namadaChannelId
    ) BitVMBridge() {
        namadaChannelId = _namadaChannelId;
    }
    
    /**
     * @notice Register user's Namada shielded address
     */
    function registerShieldedAddress(
        string calldata namadaShieldedAddress
    ) external {
        require(bytes(namadaShieldedAddress).length > 0, "Invalid address");
        userShieldedAddresses[msg.sender] = namadaShieldedAddress;
    }
    
    /**
     * @notice Mint with privacy option
     * @param depositor The depositor address
     * @param amount Amount in satoshis
     * @param depositorPubKey Bitcoin public key
     * @param usePrivacy If true, transfer to Namada for shielding
     */
    function mintPegInWithPrivacy(
        address depositor,
        uint256 amount,
        bytes32 depositorPubKey,
        bool usePrivacy
    ) external onlyOwner {
        // First mint normally
        mintPegIn(depositor, amount, depositorPubKey);
        
        if (usePrivacy) {
            string memory shieldedAddr = userShieldedAddresses[depositor];
            require(bytes(shieldedAddr).length > 0, "Shielded address not registered");
            
            // Transfer to Namada via IBC (this would need IBC integration)
            // For now, emit event - actual IBC transfer needs Cosmos SDK integration
            emit PrivacyTransferInitiated(
                depositor,
                shieldedAddr,
                amount,
                true
            );
        }
    }
    
    /**
     * @notice Transfer from Namada back to Cosmos EVM (private)
     * This would be called after a shielded transfer on Namada
     */
    function receiveFromNamada(
        address recipient,
        uint256 amount
    ) external onlyOwner {
        // In production, this would verify IBC packet
        // For now, just emit event
        emit PrivacyTransferCompleted(recipient, amount, true);
    }
}
```

### Step 3: IBC Integration

Namada uses IBC for cross-chain communication. You'll need to integrate IBC:

#### Option A: Use Cosmos SDK Bridge Module

If your Cosmos EVM chain supports IBC:

```javascript
// IBC transfer to Namada
const ibcTransfer = {
  sourcePort: 'transfer',
  sourceChannel: namadaChannelId,
  token: {
    denom: 'wrapped-btc',
    amount: amount.toString()
  },
  sender: cosmosEVMAddress,
  receiver: namadaShieldedAddress,
  timeoutHeight: {
    revisionNumber: 0,
    revisionHeight: timeoutBlock
  }
};

// Send via IBC
await cosmosClient.sendIBCTransfer(ibcTransfer);
```

#### Option B: Use Namada SDK

```rust
// In Rust (if extending bridge in Rust)
use namada_sdk::ibc::IbcTransfer;

async fn transfer_to_namada(
    amount: u64,
    shielded_address: &str,
) -> Result<()> {
    let transfer = IbcTransfer::new(
        "transfer",
        &namada_channel_id,
        amount,
        shielded_address,
    );
    
    // Execute IBC transfer
    transfer.execute().await?;
    Ok(())
}
```

### Step 4: Modify Bridge Client

Update the bridge to support privacy options:

```rust
// Add to bridge/src/client/chain/namada_adaptor.rs (new file)
use async_trait::async_trait;
use crate::constants::DestinationNetwork;

pub struct NamadaAdaptor {
    rpc_url: String,
    channel_id: String,
}

impl NamadaAdaptor {
    pub fn new(rpc_url: String, channel_id: String) -> Self {
        Self { rpc_url, channel_id }
    }
    
    /// Transfer to Namada for shielding
    pub async fn transfer_to_shielded(
        &self,
        amount: u64,
        shielded_address: &str,
    ) -> Result<String, String> {
        // Implement IBC transfer to Namada
        // This would use Namada's RPC or IBC module
        todo!("Implement IBC transfer")
    }
    
    /// Check shielded balance
    pub async fn get_shielded_balance(
        &self,
        shielded_address: &str,
    ) -> Result<u64, String> {
        // Query Namada for shielded balance
        todo!("Implement balance query")
    }
}
```

---

## Code Modifications

### 1. Add Privacy Configuration

```rust
// bridge/src/constants.rs - Add privacy options
#[derive(Eq, PartialEq, Clone, Copy)]
pub enum PrivacyMode {
    Transparent,
    Shielded,
}
```

### 2. Update Bridge Contract Interface

Modify the bridge contract to support privacy:

```solidity
// Add to BitVMBridge.sol
struct PrivacyOptions {
    bool usePrivacy;
    string namadaShieldedAddress; // If usePrivacy is true
}

function mintPegInWithPrivacy(
    address depositor,
    uint256 amount,
    bytes32 depositorPubKey,
    PrivacyOptions calldata privacy
) external onlyOwner;
```

### 3. Update Events for Privacy

```rust
// bridge/src/client/chain/chain.rs
#[derive(Serialize, Deserialize, Eq, PartialEq, Clone, Debug)]
pub struct PegInEvent {
    pub depositor: String,
    pub amount: Amount,
    pub depositor_pubkey: PublicKey,
    pub privacy_mode: Option<PrivacyMode>, // New field
    pub namada_shielded_address: Option<String>, // New field
}
```

---

## Testing

### Test Plan

1. **Unit Tests**
   - Test privacy mode selection
   - Test shielded address registration
   - Test IBC transfer simulation

2. **Integration Tests**
   - Test full flow: Bitcoin → Cosmos EVM → Namada
   - Test shielded transfer on Namada
   - Test transfer back to Cosmos EVM

3. **Privacy Tests**
   - Verify amounts are hidden on Namada
   - Verify addresses are unlinkable
   - Verify transaction graph is broken

### Test Script

```bash
#!/bin/bash
# test-privacy-integration.sh

# 1. Deploy contracts
echo "Deploying contracts..."
npx hardhat run scripts/deploy.js --network cosmosEVM

# 2. Register shielded address
echo "Registering shielded address..."
cast send $BRIDGE_ADDRESS "registerShieldedAddress(string)" "namada1..." --rpc-url $RPC_URL

# 3. Test peg-in with privacy
echo "Testing peg-in with privacy..."
./target/release/bridge initiate-peg-in \
  --utxo $UTXO \
  --destination_address $COSMOS_EVM_ADDRESS \
  --privacy-mode shielded

# 4. Verify on Namada
echo "Checking Namada shielded balance..."
namada client balance --owner $SHIELDED_ADDRESS --token BTC
```

---

## Security Considerations

### Privacy Guarantees

1. **Shielded Pool Size**: Larger pools = better privacy
2. **Timing Attacks**: Consider transaction timing
3. **Amount Analysis**: Large amounts may be linkable
4. **Network Analysis**: IBC transfers may reveal patterns

### Best Practices

1. **Always Use Shielded Addresses**: For maximum privacy
2. **Mix Transactions**: Combine with other users' transactions
3. **Avoid Reusing Addresses**: Generate new shielded addresses
4. **Monitor Pool Size**: Wait for sufficient pool size before large transfers

### Limitations

1. **IBC Transfer Visibility**: IBC transfers are visible (but amounts/addresses on Namada are hidden)
2. **Bridge Entry Point**: Initial peg-in is transparent
3. **Exit Point**: Final withdrawal may be linkable if not careful
4. **Regulatory**: Privacy features may have regulatory implications

---

## Alternative: Direct Namada Bridge

If you want to bridge **directly** to Namada (bypassing Cosmos EVM):

### Architecture

```
Bitcoin → Bridge → Namada (Shielded) → User
```

### Implementation

1. Deploy bridge contract on Namada (using Namada's smart contract system)
2. Modify bridge to support Namada as destination
3. Use Namada's native asset system

### Code Changes

```rust
// Add Namada as destination network
#[derive(Eq, PartialEq, Clone, Copy)]
pub enum DestinationNetwork {
    Ethereum,
    EthereumSepolia,
    CosmosEVM,
    Namada,  // New
    Local,
}
```

---

## Resources

- [Namada Documentation](https://docs.namada.net/)
- [Namada GitHub](https://github.com/anoma/namada)
- [MASP Documentation](https://docs.namada.net/user-guide/masp/)
- [IBC Specification](https://ibc.cosmos.network/)
- [Namada SDK](https://docs.rs/namada-sdk/)

---

## Summary

Integrating Namada for privacy provides:

✅ **Transaction Privacy**: Hide amounts and addresses
✅ **Unlinkability**: Break transaction graph
✅ **Multi-Asset Support**: Privacy for any asset
✅ **Cross-Chain Privacy**: Maintain privacy across chains

**Recommended Approach**: Use Namada as an intermediate layer (Approach 1) for:
- Minimal code changes
- Maximum flexibility
- User control over privacy

**Next Steps**:
1. Set up Namada node/connection
2. Implement IBC integration
3. Deploy privacy bridge contract
4. Test with small amounts
5. Monitor privacy guarantees

---

## Quick Start

```bash
# 1. Install Namada
curl -L https://github.com/anoma/namada/releases/latest/download/namada-0.23.0-Linux-x86_64.tar.gz | tar -xz

# 2. Join network
namada client utils join-network --chain-id namada-mainnet

# 3. Create shielded address
namada wallet gen --alias my-shielded --shielded

# 4. Deploy privacy bridge contract
npx hardhat run scripts/deploy-privacy.js --network cosmosEVM

# 5. Register shielded address
cast send $BRIDGE "registerShieldedAddress(string)" "namada1..." --rpc-url $RPC

# 6. Use bridge with privacy
./target/release/bridge initiate-peg-in --utxo $UTXO --destination_address $ADDR --privacy
```

