// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./EdgeBTC.sol";

/**
 * @title BitVMBridge
 * @notice Bridge contract for Bitcoin to Cosmos EVM chain bridging via BitVM
 * @dev This contract must emit the exact events defined in the bridge's ethereum_adaptor.rs
 */
contract BitVMBridge {
    struct Outpoint {
        bytes32 txId;
        uint256 vOut;
    }

    // Events that must match the interface in ethereum_adaptor.rs
    event PegOutInitiated(
        address indexed withdrawer,
        string destination_address,
        Outpoint source_outpoint,
        uint256 amount,
        bytes operator_pubKey
    );

    event PegOutBurnt(
        address indexed withdrawer,
        Outpoint source_outpoint,
        uint256 amount,
        bytes operator_pubKey
    );

    event PegInMinted(
        address indexed depositor,
        uint256 amount,
        bytes32 depositorPubKey
    );

    // Owner/admin address (can be a multisig in production)
    address public owner;
    
    // EdgeBTC token contract
    EdgeBTC public edgeBTC;
    
    // Mapping to track minted amounts per depositor
    mapping(address => uint256) public mintedAmounts;
    
    // Mapping to track peg-out events
    mapping(bytes32 => bool) public processedPegOuts;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    /**
     * @notice Constructor that deploys EdgeBTC token or accepts an existing one
     * @param _edgeBTC The address of an existing EdgeBTC token contract (address(0) to deploy new)
     * @dev If _edgeBTC is address(0), a new EdgeBTC token will be deployed with this bridge as minter.
     *      If _edgeBTC is provided, this bridge will be set as the minter of that token.
     */
    constructor(address _edgeBTC) {
        owner = msg.sender;
        edgeBTC = EdgeBTC(_edgeBTC);
    }

    /**
     * @notice Mint wrapped Bitcoin tokens when a peg-in is confirmed on Bitcoin
     * @param depositor The address that will receive the minted tokens
     * @param amount The amount in satoshis to mint
     * @param depositorPubKey The Bitcoin public key of the depositor (32 bytes)
     */
    function mintPegIn(
        address depositor,
        uint256 amount,
        bytes32 depositorPubKey
    ) external onlyOwner {
        require(depositor != address(0), "Invalid depositor address");
        require(amount > 0, "Amount must be greater than 0");
        
        // Mint edgeBTC tokens to the depositor
        edgeBTC.mint(depositor, amount);
        
        // Track the minted amount
        mintedAmounts[depositor] += amount;
        
        emit PegInMinted(depositor, amount, depositorPubKey);
    }

    /**
     * @notice Initiate a peg-out request from the EVM chain back to Bitcoin
     * @param withdrawer The address initiating the withdrawal (must be msg.sender)
     * @param destination_address The Bitcoin address to receive the funds
     * @param source_outpoint The Bitcoin UTXO being withdrawn
     * @param amount The amount in satoshis
     * @param operator_pubKey The Bitcoin operator public key
     */
    function initiatePegOut(
        address withdrawer,
        string calldata destination_address,
        Outpoint calldata source_outpoint,
        uint256 amount,
        bytes calldata operator_pubKey
    ) external {
        // Require that the caller is the withdrawer
        require(msg.sender == withdrawer, "Only withdrawer can initiate peg-out");
        require(withdrawer != address(0), "Invalid withdrawer address");
        require(bytes(destination_address).length > 0, "Invalid destination address");
        require(amount > 0, "Amount must be greater than 0");
        require(operator_pubKey.length > 0, "Invalid operator public key");
        
        // Check if this peg-out has already been processed
        bytes32 pegOutId = keccak256(
            abi.encodePacked(
                withdrawer,
                source_outpoint.txId,
                source_outpoint.vOut
            )
        );
        require(!processedPegOuts[pegOutId], "Peg-out already processed");
        
        // Verify withdrawer has sufficient edgeBTC balance
        require(
            edgeBTC.balanceOf(withdrawer) >= amount,
            "Insufficient edgeBTC balance"
        );
        
        // Burn edgeBTC tokens from the withdrawer
        // Since this contract is the minter, it can burn tokens from any address
        edgeBTC.burn(withdrawer, amount);
        
        // Mark this peg-out as processed
        processedPegOuts[pegOutId] = true;
        
        emit PegOutInitiated(
            withdrawer,
            destination_address,
            source_outpoint,
            amount,
            operator_pubKey
        );
    }

    /**
     * @notice Mark a peg-out as burnt (completed on Bitcoin)
     * @param withdrawer The address that initiated the withdrawal
     * @param source_outpoint The Bitcoin UTXO that was withdrawn
     * @param amount The amount in satoshis
     * @param operator_pubKey The Bitcoin operator public key
     */
    function markPegOutBurnt(
        address withdrawer,
        Outpoint calldata source_outpoint,
        uint256 amount,
        bytes calldata operator_pubKey
    ) external onlyOwner {
        require(withdrawer != address(0), "Invalid withdrawer address");
        require(amount > 0, "Amount must be greater than 0");
        
        emit PegOutBurnt(
            withdrawer,
            source_outpoint,
            amount,
            operator_pubKey
        );
    }

    /**
     * @notice Transfer ownership of the contract
     * @param newOwner The new owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner address");
        owner = newOwner;
    }
}

