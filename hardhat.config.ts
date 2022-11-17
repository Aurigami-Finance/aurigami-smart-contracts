import { HardhatUserConfig } from 'hardhat/config';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.11',
        settings: {
          optimizer: {
            enabled: true,
            runs: 3000,
          },
        }
      }
    ]
  },
  typechain: {
    target: 'ethers-v5',
  },
};

export default config;
