// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title EdgeBTC
 * @notice ERC20 token representing wrapped Bitcoin on Cosmos EVM chain
 * @dev This token is minted when Bitcoin is deposited and burned when withdrawn
 */
contract EdgeBTC {
    string public constant name = "Edge BTC";
    string public constant symbol = "edgeBTC";
    uint8 public constant decimals = 8; // Bitcoin uses 8 decimal places (satoshis)
    
    uint256 private _totalSupply;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    address public minter; // Only the bridge contract can mint/burn
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterChanged(address indexed oldMinter, address indexed newMinter);
    
    modifier onlyMinter() {
        require(msg.sender == minter, "EdgeBTC: caller is not the minter");
        _;
    }
    
    constructor(address _minter) {
        require(_minter != address(0), "EdgeBTC: minter cannot be zero address");
        minter = _minter;
    }
    
    /**
     * @notice Returns the total supply of edgeBTC tokens
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @notice Returns the balance of tokens for a given address
     * @param account The address to query
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @notice Returns the amount of tokens that spender is allowed to spend on behalf of owner
     * @param owner The address that owns the tokens
     * @param spender The address that is allowed to spend
     */
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    /**
     * @notice Transfers tokens from the caller to a recipient
     * @param to The address to transfer tokens to
     * @param amount The amount of tokens to transfer
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    /**
     * @notice Approves a spender to transfer tokens on behalf of the caller
     * @param spender The address to approve
     * @param amount The amount of tokens to approve
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * @notice Transfers tokens from one address to another using an allowance
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount of tokens to transfer
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "EdgeBTC: transfer amount exceeds allowance");
        
        _transfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - amount);
        
        return true;
    }
    
    /**
     * @notice Mints new tokens (only callable by minter/bridge)
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "EdgeBTC: mint to zero address");
        
        _totalSupply += amount;
        _balances[to] += amount;
        
        emit Transfer(address(0), to, amount);
    }
    
    /**
     * @notice Burns tokens from an address (only callable by minter/bridge)
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyMinter {
        require(from != address(0), "EdgeBTC: burn from zero address");
        require(_balances[from] >= amount, "EdgeBTC: burn amount exceeds balance");
        
        _balances[from] -= amount;
        _totalSupply -= amount;
        
        emit Transfer(from, address(0), amount);
    }
    
    /**
     * @notice Changes the minter address (only callable by current minter)
     * @param newMinter The new minter address
     */
    function setMinter(address newMinter) external onlyMinter {
        require(newMinter != address(0), "EdgeBTC: new minter cannot be zero address");
        
        address oldMinter = minter;
        minter = newMinter;
        
        emit MinterChanged(oldMinter, newMinter);
    }
    
    /**
     * @notice Internal function to transfer tokens
     */
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "EdgeBTC: transfer from zero address");
        require(to != address(0), "EdgeBTC: transfer to zero address");
        require(_balances[from] >= amount, "EdgeBTC: transfer amount exceeds balance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        
        emit Transfer(from, to, amount);
    }
    
    /**
     * @notice Internal function to approve spending
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "EdgeBTC: approve from zero address");
        require(spender != address(0), "EdgeBTC: approve to zero address");
        
        _allowances[owner][spender] = amount;
        
        emit Approval(owner, spender, amount);
    }
}

