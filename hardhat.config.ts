import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import { HardhatUserConfig } from "hardhat/types";

import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-deploy";
import "solidity-coverage";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.7.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.HARDHAT_MAINNET_FORKING_URL || "",
        blockNumber: 13155900,
      },
    }
  },
  namedAccounts: {
    deployer: {
      default: 0
    },
    owner: {
      default: 1
    },
  }
};

export default config;
