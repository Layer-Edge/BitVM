# Complete Guide: Setting Up Bitcoin to Cosmos EVM Bridge

This guide will walk you through setting up a bridge from Bitcoin to a Cosmos EVM chain (e.g., Evmos, Canto, Injective EVM) using the BitVM project.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Understanding the Architecture](#understanding-the-architecture)
3. [Step 1: Code Modifications](#step-1-code-modifications)
4. [Step 2: Deploy Smart Contract](#step-2-deploy-smart-contract)
5. [Step 3: Configuration](#step-3-configuration)
6. [Step 4: Build and Test](#step-4-build-and-test)
7. [Step 5: Usage Examples](#step-5-usage-examples)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

1. **Rust** (latest stable version)
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Cargo** (comes with Rust)

3. **Node.js and npm** (for contract deployment)
   ```bash
   # Install Node.js 18+ and npm
   ```

4. **Hardhat or Foundry** (for contract deployment)
   ```bash
   # Using npm
   npm install --save-dev hardhat
   # OR using foundry
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

5. **Bitcoin Core** (for regtest/testing) or access to Bitcoin testnet/mainnet

6. **Access to Cosmos EVM Chain RPC**
   - RPC endpoint URL for your Cosmos EVM chain
   - Chain ID
   - Native token for gas fees

### Required Knowledge

- Basic understanding of Bitcoin transactions and UTXOs
- Familiarity with EVM chains and Solidity
- Understanding of Rust (helpful but not required)

---

## Understanding the Architecture

The BitVM bridge works in two directions:

### Peg-In (Bitcoin → Cosmos EVM)
1. User deposits Bitcoin to a special address
2. Verifiers sign a confirmation transaction
3. Operator broadcasts the confirmation
4. Bridge contract mints wrapped Bitcoin on Cosmos EVM

### Peg-Out (Cosmos EVM → Bitcoin)
1. User initiates withdrawal on Cosmos EVM chain
2. Operator creates peg-out graph on Bitcoin
3. Verifiers sign the peg-out transaction
4. Operator broadcasts Bitcoin transaction to user

**Key Components:**
- **Depositor**: User who wants to bridge Bitcoin to Cosmos EVM
- **Operator**: Manages bridge operations and broadcasts transactions
- **Verifiers**: Sign transactions to ensure correctness (multi-sig)
- **Withdrawer**: User who wants to bridge back to Bitcoin

---

## Step 1: Code Modifications

The code has already been modified to support Cosmos EVM. The changes include:

1. ✅ Added `CosmosEVM` variant to `DestinationNetwork` enum
2. ✅ Updated `chain_adaptor.rs` to route Cosmos EVM to EthereumAdaptor
3. ✅ Updated `bridge-query/main.rs` to handle Cosmos EVM environments

**Note**: Since Cosmos EVM chains are EVM-compatible, they use the same `EthereumAdaptor` as Ethereum. The bridge communicates via standard Ethereum JSON-RPC methods.

---

## Step 2: Deploy Smart Contract

### 2.1 Contract Overview

The bridge requires a smart contract that emits specific events. A template contract is provided at `bridge/contracts/BitVMBridge.sol`.

**Contract Features:**
- **BitVMBridge**: Main bridge contract that handles peg-in and peg-out operations
- **EdgeBTC**: ERC20 token (automatically deployed) representing wrapped Bitcoin
  - Token Name: "Edge BTC"
  - Symbol: "edgeBTC"
  - Decimals: 8 (matching Bitcoin's satoshi precision)
  - Automatically minted on peg-in, burned on peg-out

**Required Events:**
- `PegOutInitiated`: When a user requests to withdraw Bitcoin
- `PegOutBurnt`: When a peg-out is completed on Bitcoin
- `PegInMinted`: When Bitcoin is successfully bridged to Cosmos EVM (mints edgeBTC tokens)

### 2.2 Deploy Using Hardhat

#### Setup Hardhat Project

```bash
mkdir bitvm-bridge-contract
cd bitvm-bridge-contract
npm init -y
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npx hardhat init
```

#### Copy Contract

```bash
# Copy the contract from the bridge directory
cp /path/to/BitVM/bridge/contracts/BitVMBridge.sol contracts/
```

#### Configure Hardhat

Edit `hardhat.config.js`:

```javascript
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
  networks: {
    cosmosEVM: {
      url: process.env.COSMOS_EVM_RPC_URL || "https://your-cosmos-evm-rpc.com",
      chainId: parseInt(process.env.COSMOS_EVM_CHAIN_ID || "9000"),
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    cosmosEVMTestnet: {
      url: process.env.COSMOS_EVM_TESTNET_RPC_URL || "https://testnet-rpc.com",
      chainId: parseInt(process.env.COSMOS_EVM_TESTNET_CHAIN_ID || "9001"),
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
};
```

#### Deploy Contract

Create `scripts/deploy.js`:

```javascript
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Step 1: Deploy EdgeBTC token first
  console.log("\nStep 1: Deploying EdgeBTC token...");
  const EdgeBTC = await ethers.getContractFactory("EdgeBTC");
  // Deploy with deployer as temporary minter (will be changed to bridge)
  const edgeBTC = await EdgeBTC.deploy(deployer.address);
  await edgeBTC.waitForDeployment();
  const edgeBTCAddress = await edgeBTC.getAddress();
  console.log("EdgeBTC deployed to:", edgeBTCAddress);
  console.log("EdgeBTC deployment transaction:", edgeBTC.deploymentTransaction().hash);

  // Step 2: Deploy BitVMBridge with EdgeBTC address
  console.log("\nStep 2: Deploying BitVMBridge contract...");
  const BitVMBridge = await ethers.getContractFactory("BitVMBridge");
  const bridge = await BitVMBridge.deploy(edgeBTCAddress);
  await bridge.waitForDeployment();
  const bridgeAddress = await bridge.getAddress();
  console.log("BitVMBridge deployed to:", bridgeAddress);
  console.log("BitVMBridge deployment transaction:", bridge.deploymentTransaction().hash);

  // Step 3: Set BitVMBridge as the minter of EdgeBTC
  console.log("\nStep 3: Setting BitVMBridge as EdgeBTC minter...");
  const setMinterTx = await edgeBTC.setMinter(bridgeAddress);
  await setMinterTx.wait();
  console.log("Minter updated successfully");
  console.log("SetMinter transaction:", setMinterTx.hash);

  // Verify minter was set correctly
  const currentMinter = await edgeBTC.minter();
  if (currentMinter !== bridgeAddress) {
    throw new Error("Failed to set minter correctly");
  }
  console.log("Verified: EdgeBTC minter is", currentMinter);
  
  // Save deployment info
  const network = await ethers.provider.getNetwork();
  const deploymentInfo = {
    edgeBTC: {
      address: edgeBTCAddress,
      name: "Edge BTC",
      symbol: "edgeBTC",
      decimals: 8,
      deploymentTx: edgeBTC.deploymentTransaction().hash,
      blockNumber: (await ethers.provider.getBlockNumber()) - 2, // Approximate, check receipt for exact
    },
    bridge: {
      address: bridgeAddress,
      network: network.name,
      chainId: network.chainId.toString(),
      deploymentTx: bridge.deploymentTransaction().hash,
      blockNumber: (await ethers.provider.getBlockNumber()) - 1, // Approximate, check receipt for exact
    },
  };
  
  console.log("\n=== Deployment Summary ===");
  console.log(JSON.stringify(deploymentInfo, null, 2));
  
  console.log("\n=== Next Steps ===");
  console.log("1. Get exact block numbers from transaction receipts");
  console.log("2. Verify both contracts on block explorer");
  console.log("3. Update .env file with addresses and block numbers");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

#### Run Deployment

```bash
# Set environment variables
export PRIVATE_KEY="your_private_key_here"
export COSMOS_EVM_RPC_URL="https://your-cosmos-evm-rpc.com"
export COSMOS_EVM_CHAIN_ID="9000"

# Deploy
npx hardhat run scripts/deploy.js --network cosmosEVM
```

**Save the deployment information:**
- Bridge contract address
- EdgeBTC token address (automatically deployed)
- Block number where contract was deployed
- Chain ID

### 2.3 Deploy Using Foundry

Alternatively, you can use Foundry:

```bash
# Initialize Foundry project
forge init bitvm-bridge-contract
cd bitvm-bridge-contract

# Copy contract
cp /path/to/BitVM/bridge/contracts/BitVMBridge.sol src/

# Step 1: Deploy EdgeBTC token first
forge create src/EdgeBTC.sol:EdgeBTC \
  --rpc-url $COSMOS_EVM_RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" $DEPLOYER_ADDRESS)

# Save EdgeBTC address
EDGEBTC_ADDRESS="<deployed_edgebtc_address>"

# Step 2: Deploy BitVMBridge with EdgeBTC address
forge create src/BitVMBridge.sol:BitVMBridge \
  --rpc-url $COSMOS_EVM_RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" $EDGEBTC_ADDRESS)

# Save Bridge address
BRIDGE_ADDRESS="<deployed_bridge_address>"

# Step 3: Set BitVMBridge as minter of EdgeBTC
cast send $EDGEBTC_ADDRESS "setMinter(address)" $BRIDGE_ADDRESS \
  --rpc-url $COSMOS_EVM_RPC_URL \
  --private-key $PRIVATE_KEY

# Verify minter was set correctly
cast call $EDGEBTC_ADDRESS "minter()(address)" --rpc-url $COSMOS_EVM_RPC_URL
# Should return the bridge address
```

---

## Step 3: Configuration

### 3.1 Environment Variables

Create a `.env` file in the project root:

```bash
# Bitcoin Network Configuration
ENVIRONMENT=testnet  # or "cosmos-evm" for testnet, "cosmos-evm-mainnet" for mainnet

# Cosmos EVM Chain Configuration
BRIDGE_CHAIN_ADAPTOR_ETHEREUM_RPC_URL=https://your-cosmos-evm-rpc.com
BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_ADDRESS=0xYourDeployedContractAddress
BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_CREATION=12345  # Block number where contract was deployed
BRIDGE_CHAIN_ADAPTOR_ETHEREUM_TO_BLOCK=latest  # Optional: "latest", "finalized", or block number

# EdgeBTC Token Address (automatically deployed with bridge)
EDGEBTC_TOKEN_ADDRESS=0xYourEdgeBTCTokenAddress

# Verifier Public Keys (comma-separated, Bitcoin public keys)
VERIFIERS=026cc14f56ad7e8fdb323378287895c6c0bcdbb37714c74fba175a0c5f0cd0d56f,02452556ed6dbac394cbb7441fbaf06c446d1321467fa5a138895c6c9e246793dd

# Data Store Configuration (optional)
BRIDGE_DATA_STORE_CLIENT_DATA_SUFFIX=bridge-client-data.json

# AWS S3 (if using cloud storage)
BRIDGE_AWS_ACCESS_KEY_ID=
BRIDGE_AWS_SECRET_ACCESS_KEY=
BRIDGE_AWS_REGION=
BRIDGE_AWS_BUCKET=

# Key Directory (optional, defaults to ~/.bitvm-bridge/)
KEY_DIR=~/.bitvm-bridge

# User Profile (optional, for multi-user setups)
USER_PROFILE=default_user
```

### 3.2 Key Management

Create `~/.bitvm-bridge/bridge.toml`:

```toml
[keys]
# Depositor private key (Bitcoin WIF format)
depositor = "your_depositor_private_key_here"

# Operator private key (Bitcoin WIF format)
operator = "your_operator_private_key_here"

# Verifier private key (Bitcoin WIF format)
verifier = "your_verifier_private_key_here"

# Withdrawer private key (Bitcoin WIF format, optional)
withdrawer = "your_withdrawer_private_key_here"

# ZK Proof Verifying Key (get from BitVM project)
verifying_key = "your_verifying_key_here"
```

**Security Note**: 
- Never commit private keys to version control
- Use environment variables or secure key management in production
- Consider using hardware wallets for production keys

### 3.3 Generate Keys

If you need to generate new Bitcoin keys:

```bash
# Using Bitcoin Core
bitcoin-cli -testnet getnewaddress
bitcoin-cli -testnet dumpprivkey <address>

# Or use the bridge CLI
cargo run --bin bridge -- keys --depositor <private_key> --operator <private_key> --verifier <private_key>
```

---

## Step 4: Build and Test

### 4.1 Build the Project

```bash
cd /path/to/BitVM
cargo build --release
```

### 4.2 Verify Configuration

```bash
# Check funding amounts needed
./target/release/bridge get-funding-amounts

# Get depositor address
./target/release/bridge get-depositor-address

# Get operator address
./target/release/bridge get-operator-address

# Check status
./target/release/bridge status
```

### 4.3 Test Connection to Cosmos EVM

Create a simple test script to verify the RPC connection:

```bash
# Test RPC connection (using curl)
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $BRIDGE_CHAIN_ADAPTOR_ETHEREUM_RPC_URL

# Should return a block number in hex
```

### 4.4 Test Event Listening

The bridge listens for events from the smart contract. Verify events are being emitted correctly:

```bash
# Using bridge-query to check for events
./target/release/bridge-query -e cosmos-evm pegins
```

---

## Step 5: Usage Examples

### 5.1 Peg-In: Bridge Bitcoin to Cosmos EVM

#### Step 1: Fund Depositor Address

```bash
# Get depositor address
./target/release/bridge get-depositor-address

# Send Bitcoin to this address (minimum amount from get-funding-amounts)
# Wait for confirmation
```

#### Step 2: Initiate Peg-In

```bash
# Get UTXO
./target/release/bridge get-depositor-utxos

# Initiate peg-in (replace with your UTXO and Cosmos EVM address)
./target/release/bridge initiate-peg-in \
  --utxo <TXID>:<VOUT> \
  --destination_address 0xYourCosmosEVMAddress
```

This will:
1. Create a peg-in graph
2. Broadcast the deposit transaction
3. Generate a peg-in graph ID

#### Step 3: Verifiers Sign

Each verifier needs to:
1. Push nonces
2. Push signatures

```bash
# Verifier 0
./target/release/bridge push-nonces --id <PEG_IN_GRAPH_ID>
./target/release/bridge push-signatures --id <PEG_IN_GRAPH_ID>

# Verifier 1 (on different machine/instance)
./target/release/bridge push-nonces --id <PEG_IN_GRAPH_ID>
./target/release/bridge push-signatures --id <PEG_IN_GRAPH_ID>
```

#### Step 4: Operator Broadcasts Confirmation

```bash
./target/release/bridge broadcast pegin --graph_id <PEG_IN_GRAPH_ID> confirm
```

#### Step 5: Mint on Cosmos EVM

After the peg-in confirm transaction is mined, call the smart contract's `mintPegIn` function:

```javascript
// Using ethers.js or web3
const bridge = new ethers.Contract(bridgeAddress, abi, signer);
await bridge.mintPegIn(
  depositorAddress,  // Cosmos EVM address
  amount,            // Amount in satoshis
  depositorPubKey    // Bitcoin public key (32 bytes)
);
```

**Note**: In production, this should be automated by an operator service that monitors Bitcoin and calls the contract.

### 5.2 Peg-Out: Bridge from Cosmos EVM to Bitcoin

#### Step 1: Initiate Peg-Out on Cosmos EVM

Call the smart contract:

```javascript
const bridge = new ethers.Contract(bridgeAddress, abi, signer);
await bridge.initiatePegOut(
  withdrawerAddress,      // Your Cosmos EVM address
  bitcoinAddress,          // Your Bitcoin address (string)
  {
    txId: sourceTxId,     // bytes32
    vOut: sourceVOut       // uint256
  },
  amount,                 // uint256 (satoshis)
  operatorPubKey          // bytes (Bitcoin operator public key)
);
```

#### Step 2: Operator Creates Peg-Out Graph

```bash
# Operator creates peg-out graph
./target/release/bridge create-peg-out \
  --utxo <OPERATOR_FUNDING_UTXO> \
  --peg_in_id <PEG_IN_GRAPH_ID>
```

#### Step 3: Verifiers Sign

```bash
# Verifiers push nonces and signatures (same as peg-in)
./target/release/bridge push-nonces --id <PEG_OUT_GRAPH_ID>
./target/release/bridge push-signatures --id <PEG_OUT_GRAPH_ID>
```

#### Step 4: Operator Broadcasts Transactions

```bash
# Broadcast peg-out
./target/release/bridge broadcast tx \
  --graph_id <PEG_OUT_GRAPH_ID> \
  --utxo <WITHDRAWER_FUNDING_UTXO> \
  peg_out

# Broadcast peg-out confirm
./target/release/bridge broadcast tx \
  --graph_id <PEG_OUT_GRAPH_ID> \
  peg_out_confirm

# Continue with kick-off and assert transactions
./target/release/bridge broadcast tx --graph_id <PEG_OUT_GRAPH_ID> kick_off_1
./target/release/bridge broadcast tx --graph_id <PEG_OUT_GRAPH_ID> kick_off_2
./target/release/bridge broadcast tx --graph_id <PEG_OUT_GRAPH_ID> assert_initial
# ... continue with remaining transactions
```

### 5.3 Automatic Mode

For production, use automatic mode which polls for updates:

```bash
./target/release/bridge automatic
```

This will:
- Monitor for new peg-in/peg-out events
- Automatically handle signing and broadcasting
- Sync state across participants

### 5.4 Interactive Mode

For manual control:

```bash
./target/release/bridge interactive
```

This provides an interactive CLI for all operations.

---

## Step 6: Production Considerations

### 6.1 Security

1. **Multi-sig for Contract Owner**: Use a multisig wallet for the bridge contract owner
2. **Key Management**: Use hardware wallets or secure key management services
3. **Operator Service**: Run operator service on secure, monitored infrastructure
4. **Verifier Distribution**: Distribute verifiers across different entities/regions
5. **Monitoring**: Set up alerts for contract events and Bitcoin transactions

### 6.2 Monitoring

Monitor:
- Bridge contract events on Cosmos EVM
- Bitcoin transactions related to bridge
- Operator and verifier availability
- RPC endpoint health

### 6.3 Scaling

- Consider running multiple operator instances (with coordination)
- Use cloud storage (S3) for shared state
- Implement rate limiting on contract functions
- Monitor gas costs on Cosmos EVM chain

---

## Troubleshooting

### Common Issues

#### 1. RPC Connection Errors

**Error**: `Failed to connect to RPC endpoint`

**Solutions**:
- Verify RPC URL is correct
- Check if RPC endpoint requires authentication
- Ensure network connectivity
- Try a different RPC endpoint

#### 2. Contract Events Not Found

**Error**: `No events found` or `Failed to get logs`

**Solutions**:
- Verify contract address is correct
- Check `bridge_creation_block` is correct
- Ensure events are being emitted (check contract code)
- Verify RPC supports `eth_getLogs`

#### 3. Transaction Broadcasting Fails

**Error**: `Failed to broadcast transaction`

**Solutions**:
- Check Bitcoin network connectivity
- Verify UTXO is available and sufficient
- Ensure transaction fees are adequate
- Check if transaction is already in mempool

#### 4. Signature Errors

**Error**: `Invalid signature` or `Missing signature`

**Solutions**:
- Verify all verifiers have pushed nonces
- Ensure nonces are pushed before signatures
- Check verifier keys match the configured keys
- Verify transaction hasn't changed after nonce generation

#### 5. Insufficient Funds

**Error**: `Insufficient funds` or `UTXO not found`

**Solutions**:
- Check funding amounts with `get-funding-amounts`
- Verify UTXOs are confirmed
- Ensure you're using the correct network (testnet/mainnet)

### Getting Help

1. Check the project's GitHub issues
2. Review the demo instructions: `DEMO_INSTRUCTIONS.md`
3. Check logs for detailed error messages
4. Verify all configuration matches this guide

---

## Additional Resources

- [BitVM Documentation](https://bitvm.org/)
- [BitVM2 Paper](https://bitvm.org/bitvm2)
- Cosmos EVM Chain Documentation (specific to your chain)
- Ethereum JSON-RPC Specification

---

## Summary

You now have a complete bridge setup from Bitcoin to Cosmos EVM:

1. ✅ Code supports Cosmos EVM chains
2. ✅ Smart contract template provided
3. ✅ Configuration guide complete
4. ✅ Usage examples provided

**Next Steps:**
1. Deploy the contract to your Cosmos EVM chain
2. Configure environment variables
3. Test with small amounts on testnet
4. Set up monitoring and automation
5. Deploy to mainnet after thorough testing

**Remember**: This is experimental software. Always test thoroughly before using with real funds!

