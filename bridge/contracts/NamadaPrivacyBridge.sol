// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BitVMBridge.sol";

/**
 * @title NamadaPrivacyBridge
 * @notice Extends BitVMBridge with Namada privacy integration via IBC
 * @dev This contract enables users to transfer funds to Namada's shielded pool for privacy
 */
contract NamadaPrivacyBridge is BitVMBridge {
    // IBC channel to Namada
    string public namadaChannelId;
    
    // Mapping: user address -> Namada shielded address
    mapping(address => string) public userShieldedAddresses;
    
    // Mapping: user address -> pending privacy transfers
    mapping(address => PrivacyTransfer) public pendingTransfers;
    
    // Privacy transfer structure
    struct PrivacyTransfer {
        uint256 amount;
        string namadaShieldedAddress;
        uint256 timestamp;
        bool completed;
    }
    
    // Events
    event PrivacyTransferInitiated(
        address indexed user,
        string namadaShieldedAddress,
        uint256 amount,
        bytes32 transferId
    );
    
    event PrivacyTransferCompleted(
        address indexed user,
        uint256 amount,
        bytes32 transferId
    );
    
    event ShieldedAddressRegistered(
        address indexed user,
        string namadaShieldedAddress
    );
    
    modifier hasShieldedAddress(address user) {
        require(
            bytes(userShieldedAddresses[user]).length > 0,
            "Shielded address not registered"
        );
        _;
    }
    
    constructor(
        string memory _namadaChannelId
    ) {
        require(bytes(_namadaChannelId).length > 0, "Invalid channel ID");
        namadaChannelId = _namadaChannelId;
        owner = msg.sender; // Initialize owner from BitVMBridge
    }
    
    /**
     * @notice Register user's Namada shielded address
     * @param namadaShieldedAddress The shielded address on Namada (starts with "namada1")
     */
    function registerShieldedAddress(
        string calldata namadaShieldedAddress
    ) external {
        require(bytes(namadaShieldedAddress).length > 0, "Invalid address");
        require(bytes(namadaShieldedAddress).length >= 20, "Address too short");
        
        // Basic validation - Namada addresses start with "namada1"
        bytes memory addrBytes = bytes(namadaShieldedAddress);
        require(
            addrBytes[0] == 'n' && 
            addrBytes[1] == 'a' && 
            addrBytes[2] == 'm' &&
            addrBytes[3] == 'a' &&
            addrBytes[4] == 'd' &&
            addrBytes[5] == 'a' &&
            addrBytes[6] == '1',
            "Invalid Namada address format"
        );
        
        userShieldedAddresses[msg.sender] = namadaShieldedAddress;
        
        emit ShieldedAddressRegistered(msg.sender, namadaShieldedAddress);
    }
    
    /**
     * @notice Mint with privacy option - transfers to Namada for shielding
     * @param depositor The depositor address
     * @param amount Amount in satoshis
     * @param depositorPubKey Bitcoin public key
     * @param usePrivacy If true, initiate transfer to Namada for shielding
     */
    function mintPegInWithPrivacy(
        address depositor,
        uint256 amount,
        bytes32 depositorPubKey,
        bool usePrivacy
    ) external onlyOwner {
        require(depositor != address(0), "Invalid depositor address");
        require(amount > 0, "Amount must be greater than 0");
        
        // First mint normally (this creates the wrapped token)
        // Call parent contract's mintPegIn function via internal call
        mintedAmounts[depositor] += amount;
        emit PegInMinted(depositor, amount, depositorPubKey);
        
        if (usePrivacy) {
            string memory shieldedAddr = userShieldedAddresses[depositor];
            require(bytes(shieldedAddr).length > 0, "Shielded address not registered");
            
            // Create transfer ID
            bytes32 transferId = keccak256(
                abi.encodePacked(
                    depositor,
                    amount,
                    block.timestamp,
                    block.number
                )
            );
            
            // Store pending transfer
            pendingTransfers[depositor] = PrivacyTransfer({
                amount: amount,
                namadaShieldedAddress: shieldedAddr,
                timestamp: block.timestamp,
                completed: false
            });
            
            // Emit event - actual IBC transfer would be handled by off-chain service
            // or via Cosmos SDK IBC module integration
            emit PrivacyTransferInitiated(
                depositor,
                shieldedAddr,
                amount,
                transferId
            );
        }
    }
    
    /**
     * @notice Receive from Namada - called after shielded transfer on Namada
     * @param recipient The recipient address on Cosmos EVM
     * @param amount The amount received
     * @param transferId The transfer ID from PrivacyTransferInitiated event
     */
    function receiveFromNamada(
        address recipient,
        uint256 amount,
        bytes32 transferId
    ) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        
        // In production, this would verify IBC packet and proof
        // For now, we trust the owner (should be multisig in production)
        
        PrivacyTransfer storage transfer = pendingTransfers[recipient];
        require(!transfer.completed, "Transfer already completed");
        require(transfer.amount == amount, "Amount mismatch");
        
        transfer.completed = true;
        
        // In a real implementation, you would mint/transfer tokens here
        // For now, just emit event
        emit PrivacyTransferCompleted(recipient, amount, transferId);
    }
    
    /**
     * @notice Get user's registered shielded address
     * @param user The user address
     * @return The Namada shielded address, or empty string if not registered
     */
    function getShieldedAddress(address user) external view returns (string memory) {
        return userShieldedAddresses[user];
    }
    
    /**
     * @notice Check if user has pending privacy transfer
     * @param user The user address
     * @return hasPending Whether there's a pending transfer
     * @return amount The transfer amount
     * @return shieldedAddress The Namada shielded address
     * @return timestamp When the transfer was initiated
     */
    function getPendingTransfer(address user) external view returns (
        bool hasPending,
        uint256 amount,
        string memory shieldedAddress,
        uint256 timestamp
    ) {
        PrivacyTransfer memory transfer = pendingTransfers[user];
        return (
            !transfer.completed && transfer.amount > 0,
            transfer.amount,
            transfer.namadaShieldedAddress,
            transfer.timestamp
        );
    }
    
    /**
     * @notice Update Namada channel ID (only owner)
     * @param newChannelId The new IBC channel ID
     */
    function updateNamadaChannel(string calldata newChannelId) external onlyOwner {
        require(bytes(newChannelId).length > 0, "Invalid channel ID");
        namadaChannelId = newChannelId;
    }
}

