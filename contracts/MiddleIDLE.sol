// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface idleDAIYield {
    function mintIdleToken(uint256 _amount, bool _skipRebalance, address _referral) external returns (uint256 mintedTokens);
    function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
}

interface UniswapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

contract MiddleIDLE {
    address public constant IDLE_DAI = address(0x3fE7940616e5Bc47b0775a0dccf6237893353bB4);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant UNISWAP_ROUTER = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    
    mapping(address => uint) public depositedAmountPerUser;

    event Deposited(uint mintedAmount, address indexed user);
    event Redeemed(uint redeemedAmount, address indexed user);

    constructor() {
        IERC20(DAI).approve(IDLE_DAI, type(uint).max);
        IERC20(DAI).approve(UNISWAP_ROUTER, type(uint).max);
    }

    function deposit(uint amount) public returns (uint mintedTokens) {
        require(amount > 0, "Incorrect amount");
        depositedAmountPerUser[msg.sender] += amount;
        IERC20(DAI).transferFrom(msg.sender, address(this), amount);
        mintedTokens = idleDAIYield(IDLE_DAI).mintIdleToken(amount, true, msg.sender);
        IERC20(IDLE_DAI).transfer(msg.sender, mintedTokens);

        emit Deposited(mintedTokens, msg.sender);
    }

    function redeem() public returns (uint redeemedAmount) {
        uint idleAmount = IERC20(IDLE_DAI).balanceOf(msg.sender);
        IERC20(IDLE_DAI).transferFrom(msg.sender, address(this), idleAmount);
        redeemedAmount = idleDAIYield(IDLE_DAI).redeemIdleToken(idleAmount);
        
        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = WETH;

        UniswapRouter(UNISWAP_ROUTER).swapExactTokensForTokens(redeemedAmount, 0, path, msg.sender, type(uint).max);

        emit Redeemed(redeemedAmount, msg.sender);
    }
}