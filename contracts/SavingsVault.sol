// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SavingsVault
 * @dev A contract that allows users to save both Ether and ERC20 tokens
 * Users can deposit, withdraw, and check balances for both asset types
 */

// Interface declared at the contract level, outside the main contract
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract SavingsVault {

    mapping(address => mapping(address => uint256)) private _erc20Balances;

    mapping(address => uint256) private _etherBalances;

    mapping(address => address[]) private _userTokens;

    mapping(address => mapping(address => bool)) private _isTokenTracked;


    /**
     * @dev Emitted when a user deposits Ether
     */
    event EtherDeposited(address indexed user, uint256 amount);

    /**
     * @dev Emitted when a user withdraws Ether
     */
    event EtherWithdrawn(address indexed user, uint256 amount);

    /**
     * @dev Emitted when a user deposits ERC20 tokens
     */
    event ERC20Deposited(address indexed user, address indexed token, uint256 amount);

    /**
     * @dev Emitted when a user withdraws ERC20 tokens
     */
    event ERC20Withdrawn(address indexed user, address indexed token, uint256 amount);

    constructor() {}

    /**
     * @dev Allows a user to deposit Ether into their savings
     * The Ether is sent along with the function call
     */
    function depositEther() external payable {
        require(msg.value > 0, "SavingsVault: deposit amount must be greater than 0");

        _etherBalances[msg.sender] += msg.value;

        emit EtherDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Allows a user to check their Ether balance
     * @return The user's Ether balance in the vault
     */
    function getEtherBalance(address user) external view returns (uint256) {
        return _etherBalances[user];
    }

    /**
     * @dev Allows a user to withdraw Ether from their savings
     * @param amount The amount of Ether to withdraw (in wei)
     */
    function withdrawEther(uint256 amount) external {
        require(amount > 0, "SavingsVault: withdrawal amount must be greater than 0");
        require(_etherBalances[msg.sender] >= amount, "SavingsVault: insufficient Ether balance");

        _etherBalances[msg.sender] -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "SavingsVault: Ether transfer failed");

        emit EtherWithdrawn(msg.sender, amount);
    }

    function depositERC20(address tokenAddress, uint256 amount) external {
        require(tokenAddress != address(0), "SavingsVault: invalid token address");
        require(amount > 0, "SavingsVault: deposit amount must be greater than 0");

        IERC20 token = IERC20(tokenAddress);

        // Track this token for the user if it's their first time using it
        if (!_isTokenTracked[msg.sender][tokenAddress]) {
            _userTokens[msg.sender].push(tokenAddress);
            _isTokenTracked[msg.sender][tokenAddress] = true;
        }

        // Update the user's balance BEFORE transferring tokens
        // This follows the checks-effects-interactions pattern to prevent reentrancy
        _erc20Balances[msg.sender][tokenAddress] += amount;

        // Transfer tokens from user to this contract
        // The user must have approved this contract to spend their tokens
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "SavingsVault: ERC20 transfer failed");

        emit ERC20Deposited(msg.sender, tokenAddress, amount);
    }

    function getERC20Balance(address user, address tokenAddress) external view returns (uint256) {
        return _erc20Balances[user][tokenAddress];
    }

    function withdrawERC20(address tokenAddress, uint256 amount) external {
        require(tokenAddress != address(0), "SavingsVault: invalid token address");
        require(amount > 0, "SavingsVault: withdrawal amount must be greater than 0");
        require(_erc20Balances[msg.sender][tokenAddress] >= amount, "SavingsVault: insufficient token balance");

        IERC20 token = IERC20(tokenAddress);

        // Update balance before transfer (checks-effects-interactions pattern)
        _erc20Balances[msg.sender][tokenAddress] -= amount;

        // Transfer tokens from this contract to the user
        bool success = token.transfer(msg.sender, amount);
        require(success, "SavingsVault: ERC20 transfer failed");

        emit ERC20Withdrawn(msg.sender, tokenAddress, amount);
    }

    function getUserTokens(address user) external view returns (address[] memory) {
        return _userTokens[user];
    }

    /**
     * @dev Returns comprehensive balance information for a user across all their assets
     * @param user The address of the user
     * @param tokens An array of token addresses to check balances for
     * @return etherBalance The user's Ether balance
     * @return tokenBalances An array of token balances corresponding to the input tokens
     */
    function getUserBalances(address user, address[] calldata tokens) external view returns (uint256 etherBalance, uint256[] memory tokenBalances) {
        etherBalance = _etherBalances[user];

        tokenBalances = new uint256[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            tokenBalances[i] = _erc20Balances[user][tokens[i]];
        }
    }

    /**
     * @dev Helper function to get token decimals for display purposes
     * @param tokenAddress The address of the ERC20 token
     * @return The number of decimals the token uses
     */
    function getTokenDecimals(address tokenAddress) external view returns (uint8) {
        require(tokenAddress != address(0), "SavingsVault: invalid token address");
        IERC20 token = IERC20(tokenAddress);
        return token.decimals();
    }

    /**
     * @dev Fallback function to accept Ether transfers that don't call depositEther
     * This will still credit the sender's balance automatically
     */
    receive() external payable {
        require(msg.value > 0, "SavingsVault: deposit amount must be greater than 0");
        _etherBalances[msg.sender] += msg.value;
        emit EtherDeposited(msg.sender, msg.value);
    }
}