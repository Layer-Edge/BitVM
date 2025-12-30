# Quick Start: Bitcoin to Cosmos EVM Bridge

## Prerequisites Checklist

- [ ] Rust installed (`rustc --version`)
- [ ] Cosmos EVM chain RPC URL
- [ ] Wallet with gas tokens for Cosmos EVM chain
- [ ] Bitcoin testnet/mainnet access
- [ ] Private keys for depositor, operator, and verifiers

## 5-Minute Setup

### 1. Deploy Contract

```bash
# Using Hardhat
cd bridge/contracts
npm install
npx hardhat compile
npx hardhat run scripts/deploy.js --network cosmosEVM
```

**Save**: 
- EdgeBTC token address (deployed first)
- EdgeBTC deployment block number
- Bridge contract address (deployed second)
- Bridge deployment block number

### 2. Configure Environment

Create `.env`:
```bash
ENVIRONMENT=cosmos-evm  # or cosmos-evm-mainnet
BRIDGE_CHAIN_ADAPTOR_ETHEREUM_RPC_URL=https://your-rpc-url
BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_ADDRESS=0xYourContractAddress
BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_CREATION=12345
EDGEBTC_TOKEN_ADDRESS=0xYourEdgeBTCTokenAddress  # Deployed separately before bridge
VERIFIERS=pubkey1,pubkey2
```

### 3. Setup Keys

Create `~/.bitvm-bridge/bridge.toml`:
```toml
[keys]
depositor = "your_key"
operator = "your_key"
verifier = "your_key"
verifying_key = "your_vk"
```

### 4. Build

```bash
cargo build --release
```

### 5. Test

```bash
# Check status
./target/release/bridge status

# Get addresses
./target/release/bridge get-depositor-address
./target/release/bridge get-operator-address
```

## Common Commands

### Peg-In (Bitcoin → Cosmos EVM)

```bash
# 1. Initiate
./target/release/bridge initiate-peg-in \
  --utxo <TXID>:<VOUT> \
  --destination_address 0xYourEVMAddress

# 2. Verifiers sign (each verifier)
./target/release/bridge push-nonces --id <GRAPH_ID>
./target/release/bridge push-signatures --id <GRAPH_ID>

# 3. Operator confirms
./target/release/bridge broadcast pegin --graph_id <GRAPH_ID> confirm

# 4. Mint edgeBTC tokens on Cosmos EVM (call contract mintPegIn)
# This mints EdgeBTC tokens to the depositor address
cast send $BRIDGE_ADDRESS "mintPegIn(address,uint256,bytes32)" \
  $DEPOSITOR_ADDRESS $AMOUNT $PUBKEY \
  --rpc-url $RPC_URL --private-key $OPERATOR_KEY
```

### Peg-Out (Cosmos EVM → Bitcoin)

```bash
# 1. Initiate on Cosmos EVM (call contract initiatePegOut)
# This burns edgeBTC tokens from the withdrawer's balance
cast send $BRIDGE_ADDRESS "initiatePegOut(address,string,(bytes32,uint256),uint256,bytes)" \
  $WITHDRAWER_ADDRESS $BITCOIN_ADDRESS "($TXID,$VOUT)" $AMOUNT $OPERATOR_PUBKEY \
  --rpc-url $RPC_URL --private-key $WITHDRAWER_KEY

# 2. Operator creates graph
./target/release/bridge create-peg-out \
  --utxo <UTXO> \
  --peg_in_id <PEG_IN_ID>

# 3. Verifiers sign
./target/release/bridge push-nonces --id <GRAPH_ID>
./target/release/bridge push-signatures --id <GRAPH_ID>

# 4. Operator broadcasts
./target/release/bridge broadcast tx --graph_id <GRAPH_ID> peg_out
```

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `ENVIRONMENT` | Network environment | `cosmos-evm` or `cosmos-evm-mainnet` |
| `BRIDGE_CHAIN_ADAPTOR_ETHEREUM_RPC_URL` | Cosmos EVM RPC URL | `https://rpc.evmos.org` |
| `BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_ADDRESS` | Bridge contract address | `0x1234...` |
| `BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_CREATION` | Deployment block | `12345` |
| `EDGEBTC_TOKEN_ADDRESS` | EdgeBTC ERC20 token address | `0x5678...` (auto-deployed) |
| `VERIFIERS` | Comma-separated pubkeys | `pubkey1,pubkey2` |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| RPC connection failed | Check RPC URL and network access |
| Events not found | Verify contract address and creation block |
| Signature errors | Ensure all verifiers pushed nonces first |
| Insufficient funds | Check `get-funding-amounts` for minimums |

## Next Steps

See [COSMOS_EVM_SETUP_GUIDE.md](./COSMOS_EVM_SETUP_GUIDE.md) for detailed instructions.

