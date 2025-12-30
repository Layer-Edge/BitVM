// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {EdgeBTC} from "../EdgeBTC.sol";
import {BitVMBridge} from "../BitVMBridge.sol";

contract DeployScript is Script {
    function run() external {
        console.log("=== BitVM Bridge Deployment ===");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with account:", deployer);
        
        // Get balance before deployment
        uint256 balanceBefore = deployer.balance;
        console.log("Account balance:", balanceBefore / 1e18, "ETH");
        
        if (balanceBefore < 0.02 ether) {
            revert("ERROR: Insufficient balance for deployment! Need at least 0.02 ETH");
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy EdgeBTC token first
        // Deploy with deployer as temporary minter (will be changed to bridge)
        console.log("\nStep 1: Deploying EdgeBTC token...");
        EdgeBTC edgeBTC = new EdgeBTC(deployer);
        console.log("EdgeBTC deployed to:", address(edgeBTC));
        
        // Step 2: Deploy BitVMBridge with EdgeBTC address
        console.log("\nStep 2: Deploying BitVMBridge contract...");
        BitVMBridge bridge = new BitVMBridge(address(edgeBTC));
        console.log("BitVMBridge deployed to:", address(bridge));
        
        vm.stopBroadcast();
        
        // Step 3: Set BitVMBridge as the minter of EdgeBTC
        // IMPORTANT: This must be called from the deployer account (current minter)
        console.log("\nStep 3: Setting BitVMBridge as EdgeBTC minter...");
        // Verify deployer is the current minter before calling setMinter
        address currentMinter = edgeBTC.minter();
        console.log("Current minter:", currentMinter);
        console.log("Deployer address:", deployer);
        require(currentMinter == deployer, "Deployer is not the current minter");
        
        // Use vm.broadcast for this specific call to ensure it's made from deployer
        vm.broadcast(deployerPrivateKey);
        edgeBTC.setMinter(address(bridge));
        console.log("Minter updated successfully");
        
        // Get deployment info
        uint256 chainId = block.chainid;
        
        console.log("\n=== Deployment Successful ===");
        console.log("EdgeBTC Token Address:", address(edgeBTC));
        console.log("Bridge Contract Address:", address(bridge));
        console.log("Chain ID:", chainId);
        
        // Verify minter was set correctly (read-only call, no broadcast needed)
        address finalMinter = edgeBTC.minter();
        require(finalMinter == address(bridge), "Minter not set correctly");
        console.log("Verified: EdgeBTC minter is", finalMinter);
        
        // Note: Block number will be available after broadcast
        // Check transaction receipt or use cast to get block number
        
        console.log("\n=== Next Steps ===");
        console.log("1. Save the contract addresses:");
        console.log("   EdgeBTC:", address(edgeBTC));
        console.log("   Bridge:", address(bridge));
        console.log("2. After broadcast, save the deployment block numbers from transaction receipts");
        console.log("3. Update your .env file with:");
        console.log("   BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_ADDRESS=", address(bridge));
        console.log("   BRIDGE_CHAIN_ADAPTOR_ETHEREUM_BRIDGE_CREATION=<bridge_block_number>");
        console.log("   EDGEBTC_TOKEN_ADDRESS=", address(edgeBTC));
        console.log("   EDGEBTC_TOKEN_CREATION=<edgebtc_block_number>");
        console.log("\n4. Verify both contracts on block explorer:");
        console.log("   - Verify EdgeBTC contract");
        console.log("   - Verify BitVMBridge contract");
    }
}

