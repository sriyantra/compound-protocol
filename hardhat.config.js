require("@nomiclabs/hardhat-vyper");
require("@nomiclabs/hardhat-waffle");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.5.16",

  defaultNetwork: "hardhat",

  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true,
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/FBoARh3vTurveT-eIEdESj8luBhaM6Fv",
        //blockNumber: 13225783
      }
    }
  },

  vyper: {
    version: "0.2.4",
  },
};
