const hre = require("hardhat");
const { expect, use } = require("chai");
const { ethers } = require("hardhat");
var assert = require('assert');
var axios = require("axios");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-vyper");
const BigNumber = require('bignumber.js');
const { Contract, utils, Wallet } = require("ethers");

const { expectRevert, time } = require('@openzeppelin/test-helpers');
const ERC20_abi = require("../ERC20_abi.json");

const RGT_addr = "0xD291E7a03283640FDc51b121aC401383A46cC623";
const REWARDS_DURATION = 7 * 86400; // 7 days
let veRGT_instance;

const DAI = "0x6b175474e89094c44da98b954eedeac495271d0f";
const WALLET_WITH_RGT = "0xa4B2772c88925c043888E3Da8b5723D5C53F9776";

describe('TestSupplySpeeds', function() {
  this.timeout(30000);
  
  it('update supply speeds', async function () {
    var [signer] = await ethers.getSigners();

    const accounts = await hre.ethers.getSigners();
    const DEPLOYER_ADDRESS = accounts[0].address;

    // veRGT
    const veRGT = await ethers.getContractFactory("veRGT");
    let VERGT_instance = await veRGT.deploy(RGT_addr, "veRGT", "VGT", "0,2,4");
    veRGT_instance = await VERGT_instance.deployed();

    // RGT instance
    const rgtInstance = new ethers.Contract(RGT_addr, ERC20_abi, signer);

    // gauge controller
    const GaugeController = await ethers.getContractFactory("FuseGaugeController");
    let GaugeControllerInstance = await GaugeController.deploy(RGT_addr, veRGT_instance.address);
    let gaugeControllerInstance = await GaugeControllerInstance.deployed();

    // rewards distributor 
    const RewardsDistributor = await ethers.getContractFactory("RewardsDistributor");
    let RewardsDistributorInstance = await RewardsDistributor.deploy(RGT_addr, gaugeControllerInstance.address);
    let rewardsDistributorInstance = await RewardsDistributorInstance.deployed();

    // gauges
    const FuseSupplyGauge1 = await ethers.getContractFactory("FuseSupplyGauge");
    let FuseSupplyGaugeInstance1 = await FuseSupplyGauge1.deploy(DAI, rewardsDistributorInstance.address, veRGT_instance.address);
    let fuseSupplyGaugeInstance1= await FuseSupplyGaugeInstance1.deployed();

    const FuseSupplyGauge2 = await ethers.getContractFactory("FuseSupplyGauge");
    let FuseSupplyGaugeInstance2 = await FuseSupplyGauge2.deploy(RGT_addr, rewardsDistributorInstance.address, veRGT_instance.address);
    let fuseSupplyGaugeInstance2 = await FuseSupplyGaugeInstance2.deployed();

    await gaugeControllerInstance["add_type(string,uint256)"]("Supply", 1e18.toString());
    await gaugeControllerInstance["add_gauge(address,int128,uint256)"](fuseSupplyGaugeInstance1.address, 0, 2000);
    await gaugeControllerInstance["add_gauge(address,int128,uint256)"](fuseSupplyGaugeInstance2.address, 0, 500);

    await hre.network.provider.request({
			method: "hardhat_impersonateAccount",
			params: [WALLET_WITH_RGT]
		});

    const signer0 = await ethers.getSigner(WALLET_WITH_RGT);

    console.log('signer address', signer0.address);
    console.log('rgt balance of deployer', await rgtInstance.balanceOf(signer0.address));
    await rgtInstance.connect(signer0).transfer(DEPLOYER_ADDRESS, 1000);
    console.log('rgt balance of deployer', await rgtInstance.balanceOf(DEPLOYER_ADDRESS));

    // get veRGT
    
    const deposit_amount_1 = 100;
		const deposit_amount_1_e18 = new BigNumber(`${deposit_amount_1}e18`);
    console.log(`Deposit ${deposit_amount_1} RGT (4 years) for veRGT`);

    const veRGT_deposit_days = (4 * 365); // 4 years
		let block_time_current = (await time.latest()).toNumber();
		const veRGT_deposit_end_timestamp = block_time_current + (veRGT_deposit_days * 86400);
    const deposit_amount_quick_e18_4_yr = new BigNumber(`100e18`);

    await hre.network.provider.request({
			method: "hardhat_stopImpersonatingAccount",
			params: [WALLET_WITH_RGT]
		});
    
    // Wait 7 days
		for (let j = 0; j < 7; j++){
			await time.increase(86400);
			await time.advanceBlock();
		}

    let blockTime = (await time.latest()).toNumber();
    console.log('get gauge relative weight', (await gaugeControllerInstance["gauge_relative_weight(address,uint256)"](fuseSupplyGaugeInstance1.address, blockTime)).toString());
    
    // change global emission rate to 10 RGT per year
    console.log('change global emission rate');
    await gaugeControllerInstance["change_global_emission_rate(uint256)"](11574074074074);
    
    // Wait 7 days
		for (let j = 0; j < 7; j++){
			await time.increase(86400);
			await time.advanceBlock();
		}

    console.log("updated global emission rate", (await gaugeControllerInstance["global_emission_rate()"]()).toString());

    // whitelist gauges
    await rewardsDistributorInstance._setGaugeState(fuseSupplyGaugeInstance1.address, true);
    await rewardsDistributorInstance._setGaugeState(fuseSupplyGaugeInstance2.address, true);

    await rewardsDistributorInstance.setCompSupplySpeedManual(fuseSupplyGaugeInstance1.address, 2);
    //await rewardsDistributorInstance._setCompSupplySpeed(fuseSupplyGaugeInstance1.address);
    let rewardsDistributorSupplySpeed = await rewardsDistributorInstance.compSupplySpeeds(DAI);
    console.log('rewards dist comp supply speed', rewardsDistributorSupplySpeed);
  });
});
