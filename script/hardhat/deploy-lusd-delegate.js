// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // Deploy CErc20PluginDelegate
  const CErc20PluginDelegate = await hre.ethers.getContractFactory("CErc20PluginDelegate");

  const cLusdDelegate = await CErc20PluginDelegate.deploy();
  await cLusdDelegate.deployed();

  console.log("CErc20PluginDelegate:", cLusdDelegate.address);

  // Deploy PluginRewardsDistributorDelegate + Delegator
  const PluginRewardsDistributorDelegate = await hre.ethers.getContractFactory("PluginRewardsDistributorDelegate");

  const pluginDelegate = await PluginRewardsDistributorDelegate.deploy();
  await pluginDelegate.deployed();
  
  console.log("pluginDelegate:", pluginDelegate.address);

  const PluginRewardsDistributorDelegator = await hre.ethers.getContractFactory("RewardsDistributorDelegator");

  const pluginDelegator = await PluginRewardsDistributorDelegator.deploy(
    "0xa731585ab05fC9f83555cf9Bff8F58ee94e18F85", // rari fuse admin
    "0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D", // LQTY
    pluginDelegate.address
  );
  await pluginDelegator.deployed();
  
  console.log("pluginDelegator:", pluginDelegator.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
