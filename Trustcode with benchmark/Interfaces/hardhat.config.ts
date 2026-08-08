import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",

    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },

      metadata: {
        bytecodeHash: "none"
      },

      viaIR: false
    }
  },

  networks: {
    hardhat: {
      chainId: 31337,

      mining: {
        auto: true,
        interval: 0
      },

      allowUnlimitedContractSize: false
    },

    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    }
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },

  mocha: {
    timeout: 120000
  }
};

export default config;