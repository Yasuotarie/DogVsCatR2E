import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@typechain/hardhat";

const config: HardhatUserConfig = {
  defaultNetwork: "localhost",
  solidity: "0.8.20",
  networks: {
    hardhat: {
      chainId: 43114,
      gasPrice: 225000000000,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v6",
  },
};

export default config;
