// Hardhat script to deploy NamadaPrivacyBridge
// Usage: npx hardhat run scripts/deploy-privacy.js --network <network>

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Get Namada channel ID from environment or use default
  const namadaChannelId = process.env.NAMADA_CHANNEL_ID || "channel-0";
  console.log("Using Namada channel ID:", namadaChannelId);

  // Deploy BitVMBridge first (if not already deployed)
  console.log("\nDeploying BitVMBridge...");
  const BitVMBridge = await ethers.getContractFactory("BitVMBridge");
  const baseBridge = await BitVMBridge.deploy();
  await baseBridge.waitForDeployment();
  const baseBridgeAddress = await baseBridge.getAddress();
  console.log("BitVMBridge deployed to:", baseBridgeAddress);

  // Deploy NamadaPrivacyBridge
  console.log("\nDeploying NamadaPrivacyBridge...");
  const NamadaPrivacyBridge = await ethers.getContractFactory("NamadaPrivacyBridge");
  const privacyBridge = await NamadaPrivacyBridge.deploy(namadaChannelId);
  await privacyBridge.waitForDeployment();
  const privacyBridgeAddress = await privacyBridge.getAddress();
  console.log("NamadaPrivacyBridge deployed to:", privacyBridgeAddress);

  // Get deployment info
  const network = await ethers.provider.getNetwork();
  const blockNumber = await ethers.provider.getBlockNumber();

  const deploymentInfo = {
    network: network.name,
    chainId: network.chainId.toString(),
    blockNumber: blockNumber,
    contracts: {
      BitVMBridge: {
        address: baseBridgeAddress,
        transaction: baseBridge.deploymentTransaction()?.hash
      },
      NamadaPrivacyBridge: {
        address: privacyBridgeAddress,
        transaction: privacyBridge.deploymentTransaction()?.hash,
        namadaChannelId: namadaChannelId
      }
    },
    deployer: deployer.address
  };

  console.log("\n=== Deployment Summary ===");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Save to file
  const fs = require('fs');
  const path = require('path');
  const deploymentPath = path.join(__dirname, '..', 'deployments', `${network.name}.json`);
  
  // Create deployments directory if it doesn't exist
  const deploymentsDir = path.dirname(deploymentPath);
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\nDeployment info saved to: ${deploymentPath}`);

  console.log("\n=== Next Steps ===");
  console.log("1. Set environment variable:");
  console.log(`   export NAMADA_PRIVACY_BRIDGE_ADDRESS=${privacyBridgeAddress}`);
  console.log("\n2. Register a shielded address:");
  console.log(`   cast send ${privacyBridgeAddress} \\`);
  console.log(`     "registerShieldedAddress(string)" \\`);
  console.log(`     "namada1your-shielded-address" \\`);
  console.log(`     --rpc-url <RPC_URL> \\`);
  console.log(`     --private-key <PRIVATE_KEY>`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

