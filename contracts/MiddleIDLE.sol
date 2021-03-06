// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

interface idleDAIYield {
    function mintIdleToken(uint256 _amount, bool _skipRebalance, address _referral) external returns (uint256 mintedTokens);
    function redeemIdleToken(uint256 _amount) external returns (uint256 redeemedTokens);
    function tokenPrice() external view returns (uint256 price);
    function tokenPriceWithFee(address user) external view returns (uint256 priceWFee);
}

interface UniswapRouter {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

contract MiddleIDLE is Ownable {
    address public constant IDLE_DAI = address(0x3fE7940616e5Bc47b0775a0dccf6237893353bB4);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant UNISWAP_ROUTER = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint private constant ONE_18 = 10 ** 18;
    uint public totalDepositedAmount;
    uint public totalMintedAmount;
    uint public totalHarvestedAmount;
    uint public acctotalHarvestedAmount;
    uint public lastUpdatedTime;
    uint public recentHarvestedTime;
    
    mapping(address => uint) public depositedAmountPerUser;
    mapping(address => uint) public mintedAmountPerUser;
    mapping(address => uint) public lastUpdatedTimePerUser;
    mapping(address => uint) public acctotalHarvestedAmountPerUser;

    event Deposited(uint mintedAmount, address indexed user);
    event Redeemed(uint redeemedAmount, address indexed user);
    event Harvested(uint harvestedAmount, uint newTotalMintedAmount, uint timestamp);
    event Claimed(uint claimedAmount, address indexed user);

    constructor() {
        IERC20(DAI).approve(IDLE_DAI, type(uint).max);
        IERC20(DAI).approve(UNISWAP_ROUTER, type(uint).max);
    }

    function deposit(uint amount) public returns (uint mintedTokens) {
        require(amount > 0, "Incorrect amount");
        IERC20(DAI).transferFrom(msg.sender, address(this), amount);

        acctotalHarvestedAmount += totalDepositedAmount * (block.timestamp - lastUpdatedTime);
        // TODO : lastUpdatedTimePerUser check
        acctotalHarvestedAmountPerUser[msg.sender] += depositedAmountPerUser[msg.sender] * (block.timestamp - lastUpdatedTimePerUser[msg.sender]);

        depositedAmountPerUser[msg.sender] += amount;
        totalDepositedAmount += amount;
        mintedTokens = idleDAIYield(IDLE_DAI).mintIdleToken(amount, true, msg.sender);
        mintedAmountPerUser[msg.sender] += mintedTokens;
        totalMintedAmount += mintedTokens;
        
        lastUpdatedTime = block.timestamp;
        lastUpdatedTimePerUser[msg.sender] = block.timestamp;

        emit Deposited(mintedTokens, msg.sender);
    }

    function redeem() public returns (uint redeemedAmount) {
        uint currentIdlePrice = idleDAIYield(IDLE_DAI).tokenPriceWithFee(address(this));
        uint idleAmountEstimate = depositedAmountPerUser[msg.sender] * (ONE_18) / (currentIdlePrice);

        require(depositedAmountPerUser[msg.sender] > 0, "No amount for redeem");

        if (idleAmountEstimate >= mintedAmountPerUser[msg.sender]) {
            redeemedAmount = idleDAIYield(IDLE_DAI).redeemIdleToken(mintedAmountPerUser[msg.sender]);
        } else {
            redeemedAmount = idleDAIYield(IDLE_DAI).redeemIdleToken(idleAmountEstimate);
        }
        
        if (redeemedAmount >= depositedAmountPerUser[msg.sender]) {
            mintedAmountPerUser[msg.sender] = 0;

            acctotalHarvestedAmount += totalDepositedAmount * (block.timestamp - lastUpdatedTime);
            acctotalHarvestedAmountPerUser[msg.sender] += depositedAmountPerUser[msg.sender] * (block.timestamp - lastUpdatedTimePerUser[msg.sender]);
            lastUpdatedTime = block.timestamp;
            lastUpdatedTimePerUser[msg.sender] = block.timestamp;

            totalDepositedAmount -= depositedAmountPerUser[msg.sender];
            depositedAmountPerUser[msg.sender] = 0;

            address[] memory path = new address[](2);
            path[0] = DAI;
            path[1] = WETH;
            UniswapRouter(UNISWAP_ROUTER).swapExactTokensForTokens(redeemedAmount - depositedAmountPerUser[msg.sender], 0, path, msg.sender, type(uint).max);
            IERC20(DAI).transfer(msg.sender, depositedAmountPerUser[msg.sender]);

            emit Redeemed(redeemedAmount, msg.sender);
        }
    }

    function claim() public returns (uint claimedAmount) {
        require(acctotalHarvestedAmountPerUser[msg.sender] > 0, "Insufficient amount");
        claimedAmount = totalHarvestedAmount * acctotalHarvestedAmountPerUser[msg.sender] / acctotalHarvestedAmount;
        
        acctotalHarvestedAmountPerUser[msg.sender] = 0;
        acctotalHarvestedAmount -= acctotalHarvestedAmountPerUser[msg.sender];
        IERC20(WETH).transfer(msg.sender, claimedAmount);

        emit Claimed(claimedAmount, msg.sender);
    }

    function harvest() public onlyOwner returns (uint harvestedWETHAmount) {
        uint idleAmount = IERC20(IDLE_DAI).balanceOf(address(this));
        uint totalRedeemedAmount = idleDAIYield(IDLE_DAI).redeemIdleToken(idleAmount);
        
        if (totalRedeemedAmount >= totalDepositedAmount) {
            uint harvestedDAIAmount = totalRedeemedAmount - totalDepositedAmount;
            address[] memory path = new address[](2);
            path[0] = DAI;
            path[1] = WETH;

            uint[] memory amounts = UniswapRouter(UNISWAP_ROUTER).swapExactTokensForTokens(harvestedDAIAmount, 0, path, address(this), type(uint).max);
            harvestedWETHAmount = amounts[1];
            totalHarvestedAmount += harvestedWETHAmount;
            recentHarvestedTime = block.timestamp;
            totalMintedAmount = idleDAIYield(IDLE_DAI).mintIdleToken(totalDepositedAmount, true, address(this));
            emit Harvested(harvestedWETHAmount, totalMintedAmount, block.timestamp);
        }
    }
}