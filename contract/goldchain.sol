// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract ERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return 18; }
    function totalSupply() public view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view returns (uint256) { return _balances[account]; }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        unchecked { _balances[account] += amount; }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked { _approve(owner, spender, currentAllowance - amount); }
        }
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Ownable {
    address private _owner;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { _transferOwnership(msg.sender); }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function _checkOwner() internal view {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
    }

    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/**
 * @title GoldChain
 * @dev A decentralized gold-backed token system with staking and trading functionality
 * @author GoldChain Team
 */
contract GoldChain is ERC20, Ownable, ReentrancyGuard {
    
    // Gold reserve tracking
    struct GoldReserve {
        uint256 totalGoldOunces;
        uint256 reserveValue; // in USD (scaled by 1e6 for precision)
        uint256 lastUpdated;
        bool isActive;
    }
    
    // Staking information
    struct StakeInfo {
        uint256 amount;
        uint256 timestamp;
        uint256 rewardDebt;
    }
    
    // State variables
    GoldReserve public goldReserve;
    mapping(address => StakeInfo) public stakes;
    
    uint256 public constant GOLD_TO_TOKEN_RATIO = 1000; // 1000 tokens per ounce of gold
    uint256 public constant STAKING_REWARD_RATE = 5; // 5% annual reward
    uint256 public constant PRECISION = 1e6;
    
    address public goldOracle; // Address authorized to update gold prices
    
    // Events
    event GoldReserveUpdated(uint256 goldOunces, uint256 reserveValue);
    event TokensMinted(address indexed to, uint256 amount, uint256 goldBacked);
    event TokensBurned(address indexed from, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event GoldPriceUpdated(uint256 newPrice, uint256 timestamp);
    
    modifier onlyOracle() {
        require(msg.sender == goldOracle, "Only oracle can call this function");
        _;
    }
    
    constructor(
        address _initialOwner,
        address _goldOracle,
        uint256 _initialGoldOunces,
        uint256 _initialReserveValue
    ) ERC20("GoldChain Token", "GOLD") {
        _transferOwnership(_initialOwner);
        goldOracle = _goldOracle;
        
        goldReserve = GoldReserve({
            totalGoldOunces: _initialGoldOunces,
            reserveValue: _initialReserveValue,
            lastUpdated: block.timestamp,
            isActive: true
        });
        
        // Mint initial tokens based on gold reserves
        uint256 initialTokens = _initialGoldOunces * GOLD_TO_TOKEN_RATIO;
        _mint(_initialOwner, initialTokens);
        
        emit GoldReserveUpdated(_initialGoldOunces, _initialReserveValue);
        emit TokensMinted(_initialOwner, initialTokens, _initialGoldOunces);
    }
    
    /**
     * @dev Core Function 1: Mint tokens backed by gold reserves
     * @param to Address to mint tokens to
     * @param goldOunces Amount of gold ounces backing the new tokens
     */
    function mintGoldBackedTokens(address to, uint256 goldOunces) 
        external 
        onlyOwner 
        nonReentrant 
    {
        require(goldReserve.isActive, "Gold reserves not active");
        require(goldOunces > 0, "Gold amount must be positive");
        
        uint256 tokensToMint = goldOunces * GOLD_TO_TOKEN_RATIO;
        
        // Update gold reserves
        goldReserve.totalGoldOunces += goldOunces;
        goldReserve.lastUpdated = block.timestamp;
        
        _mint(to, tokensToMint);
        
        emit TokensMinted(to, tokensToMint, goldOunces);
        emit GoldReserveUpdated(goldReserve.totalGoldOunces, goldReserve.reserveValue);
    }
    
    /**
     * @dev Core Function 2: Stake tokens to earn rewards
     * @param amount Amount of tokens to stake
     */
    function stakeTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Stake amount must be positive");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Calculate and pay existing rewards before updating stake
        if (stakes[msg.sender].amount > 0) {
            uint256 reward = calculateStakingReward(msg.sender);
            if (reward > 0) {
                _mint(msg.sender, reward);
            }
        }
        
        // Update stake information
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].timestamp = block.timestamp;
        stakes[msg.sender].rewardDebt = 0;
        
        // Transfer tokens to contract for staking
        _transfer(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount);
    }
    
    /**
     * @dev Core Function 3: Unstake tokens and claim rewards
     * @param amount Amount of tokens to unstake
     */
    function unstakeTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Unstake amount must be positive");
        require(stakes[msg.sender].amount >= amount, "Insufficient staked amount");
        
        // Calculate rewards
        uint256 reward = calculateStakingReward(msg.sender);
        
        // Update stake information
        stakes[msg.sender].amount -= amount;
        stakes[msg.sender].timestamp = block.timestamp;
        stakes[msg.sender].rewardDebt = 0;
        
        // Transfer staked tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        // Mint and transfer rewards
        if (reward > 0) {
            _mint(msg.sender, reward);
        }
        
        emit Unstaked(msg.sender, amount, reward);
    }
    
    /**
     * @dev Calculate staking rewards for a user
     * @param user Address of the user
     * @return reward Amount of reward tokens earned
     */
    function calculateStakingReward(address user) public view returns (uint256 reward) {
        if (stakes[user].amount == 0) return 0;
        
        uint256 stakingDuration = block.timestamp - stakes[user].timestamp;
        uint256 annualReward = (stakes[user].amount * STAKING_REWARD_RATE) / 100;
        reward = (annualReward * stakingDuration) / 365 days;
        
        return reward;
    }
    
    /**
     * @dev Update gold reserve value (only oracle)
     * @param newReserveValue New reserve value in USD
     */
    function updateGoldReserveValue(uint256 newReserveValue) external onlyOracle {
        goldReserve.reserveValue = newReserveValue;
        goldReserve.lastUpdated = block.timestamp;
        
        emit GoldPriceUpdated(newReserveValue, block.timestamp);
        emit GoldReserveUpdated(goldReserve.totalGoldOunces, newReserveValue);
    }
    
    /**
     * @dev Burn tokens and reduce gold backing
     * @param amount Amount of tokens to burn
     */
    function burnTokens(uint256 amount) external {
        require(amount > 0, "Burn amount must be positive");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        uint256 goldOuncesToRemove = amount / GOLD_TO_TOKEN_RATIO;
        
        // Update gold reserves
        if (goldOuncesToRemove > 0) {
            goldReserve.totalGoldOunces -= goldOuncesToRemove;
            goldReserve.lastUpdated = block.timestamp;
        }
        
        _burn(msg.sender, amount);
        
        emit TokensBurned(msg.sender, amount);
        emit GoldReserveUpdated(goldReserve.totalGoldOunces, goldReserve.reserveValue);
    }
    
    /**
     * @dev Get current gold backing ratio
     * @return ratio Gold backing ratio (tokens per ounce)
     */
    function getGoldBackingRatio() external view returns (uint256 ratio) {
        if (goldReserve.totalGoldOunces == 0) return 0;
        return totalSupply() / goldReserve.totalGoldOunces;
    }
    
    /**
     * @dev Update oracle address (only owner)
     * @param newOracle New oracle address
     */
    function updateOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid oracle address");
        goldOracle = newOracle;
    }
    
    /**
     * @dev Toggle gold reserve status (only owner)
     */
    function toggleGoldReserveStatus() external onlyOwner {
        goldReserve.isActive = !goldReserve.isActive;
    }
    
    /**
     * @dev Get user's staking information
     * @param user Address of the user
     * @return amount Staked amount
     * @return timestamp Staking timestamp
     * @return pendingReward Pending reward amount
     */
    function getUserStakingInfo(address user) 
        external 
        view 
        returns (uint256 amount, uint256 timestamp, uint256 pendingReward) 
    {
        amount = stakes[user].amount;
        timestamp = stakes[user].timestamp;
        pendingReward = calculateStakingReward(user);
    }
}
