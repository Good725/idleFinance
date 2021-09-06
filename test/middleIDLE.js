const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

describe("Middle contract", function () {
    const UNISWAP_ABI = require('../abis/Uniswap_abi.json');
    const DAI_ABI = require('../abis/DAI_abi.json');
    const IDLE_ABI = require('../abis/IDLE_DAI_abi.json');
    const WETH_ABI = require('../abis/WETH_abi.json');
    const uniswapV2Router02Address = "0x7a250d5630b4cf539739df2c5dacb4c659f2488d";
    const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    const idleDAI_Address = "0x3fE7940616e5Bc47b0775a0dccf6237893353bB4";
    const wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    
    let MiddleContract;
    let uniswap;
    let dai;
    let idleDAI;
    let weth;

    let owner;
    let user1;
    let user2;
    let addrs;
  
    before(async function () {
        [owner, user1, user2, ...addrs] = await ethers.getSigners();
        MiddleContract = await ethers.getContractFactory("MiddleIDLE");
        MiddleContract = await MiddleContract.deploy();

        uniswap = new ethers.Contract(uniswapV2Router02Address, UNISWAP_ABI, owner);
        dai = new ethers.Contract(daiAddress, DAI_ABI, owner);
        idleDAI = new ethers.Contract(idleDAI_Address, IDLE_ABI, owner);
        weth = new ethers.Contract(wethAddress, WETH_ABI, owner);
    });

    it("Give 100 DAI to user1 and user2", async function () {
        let payForBuyingDAI = BigNumber.from((1 * 10 ** 18).toString());
        let daiAmount = BigNumber.from((100 * 10 ** 18).toString());
        await uniswap.connect(user1).swapETHForExactTokens(daiAmount.toString(), [wethAddress, daiAddress], user1.address, '9600952122', { value: payForBuyingDAI });
        await uniswap.connect(user2).swapETHForExactTokens(daiAmount.toString(), [wethAddress, daiAddress], user2.address, '9600952122', { value: payForBuyingDAI });

        const balance_user1 = await dai.balanceOf(user1.address);
        const balance_user2 = await dai.balanceOf(user2.address);

        await expect(balance_user1).to.equal(daiAmount);
        await expect(balance_user2).to.equal(daiAmount);
    });

    describe("Deposit, Harvest, Redeem", function () {
        const depositAmount = BigNumber.from((50 * 10 ** 18).toString());
        it("User1 and User2 deposit 50 DAI and get idleDAI tokens, Compare the mited amount with the estimated amount based on tokenPrice", async function () {
            // let depositAmount = BigNumber.from((50 * 10 ** 18).toString());
            await dai.connect(user1).approve(MiddleContract.address, depositAmount);
            await MiddleContract.connect(user1).deposit(depositAmount);
    
            let tokenPrice = await idleDAI.tokenPrice();
            let estimateAmount = depositAmount.mul(1e18.toString()).div(BigNumber.from(tokenPrice));
    
            const balance = await idleDAI.balanceOf(MiddleContract.address);
            await expect(estimateAmount).to.equal(balance);
        });
    
        it("Owner harvests, contract balance check", async function () {
            await MiddleContract.connect(owner).harvest();
            const balance = await idleDAI.balanceOf(MiddleContract.address);
    
            let tokenPrice = await idleDAI.tokenPrice();
            let estimateAmount = depositAmount.mul(1e18.toString()).div(BigNumber.from(tokenPrice));
    
            await expect(estimateAmount).to.equal(balance);
        });
    
        it("User1 redeems", async function () {
            let balanceuser1_beforeRedeem = await dai.balanceOf(user1.address);
            let wethBalance_beforeRedeem = await weth.balanceOf(user1.address);

            await MiddleContract.connect(user1).redeem();

            let balanceuser1_afterRedeem = await dai.balanceOf(user2.address);
            let wethBalance_afterRedeem = await weth.balanceOf(user1.address);

            let bala = await weth.balanceOf(MiddleContract.address);
            console.log(bala.toString());

            await expect(balanceuser1_afterRedeem).to.equal(balanceuser1_beforeRedeem.add(depositAmount));
            await expect(wethBalance_afterRedeem).to.be.above(wethBalance_beforeRedeem);
        });

        it("Should fail if user1 redeems without any deposited amount", async function () {
            await expect(MiddleContract.connect(user1).redeem()).to.be.revertedWith("No amount for redeem");
        });

        it("User1 claims", async function () {
            let wethBalance_beforeClaim = await weth.balanceOf(user1.address);
            console.log("weth balance before claim", wethBalance_beforeClaim.toString());
            await MiddleContract.connect(user1).claim();
            let wethBalance_afterClaim = await weth.balanceOf(user1.address);
            console.log("weth balance after claim", wethBalance_afterClaim.toString());
            await expect(wethBalance_afterClaim).to.be.above(wethBalance_beforeClaim);
        });
    });    
})