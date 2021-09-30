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

  // Deploy RewardsDistributorDelegate
  const RewardsDistributorDelegate = await hre.ethers.getContractFactory("RewardsDistributorDelegate");
  const rewardsDistributorDelegate = await RewardsDistributorDelegate.deploy();
  await rewardsDistributorDelegate.deployed();
  console.log("RewardsDistributorDelegate:", rewardsDistributorDelegate.address);

  // Deploy RewardsDistributorDelegator
  const RewardsDistributorDelegator = await hre.ethers.getContractFactory("RewardsDistributorDelegator");
  const rewardsDistributorDelegator = await RewardsDistributorDelegator.deploy("0x639572471f2f318464dc01066a56867130e45e25", "0xc7283b66Eb1EB5FB86327f08e1B5816b0720212B", rewardsDistributorDelegate.address);
  await rewardsDistributorDelegator.deployed();
  console.log("RewardsDistributorDelegator:", rewardsDistributorDelegator.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
