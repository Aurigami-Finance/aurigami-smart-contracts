import * as dotenv from 'dotenv';

import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-etherscan';
import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import 'hardhat-contract-sizer';
import 'hardhat-storage-layout-diff';
import 'solidity-coverage';
import '@openzeppelin/hardhat-upgrades';

dotenv.config();

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
  networks: {
    hardhat: {
      chainId: 1313161554,
      forking: {
        // url: `https://testnet.aurora.dev/${process.env.AURORA_API_KEY}`,
        url: `https://mainnet.aurora.dev/`,
        // blockNumber: 65217137
      },
      accounts: [
        // 5 accounts with 10^14 ETH each
        // Addresses:
        //   your address generated from the private key
        //   0x6824c889f6EbBA8Dac4Dd4289746FCFaC772Ea56
        //   0xCFf94465bd20C91C86b0c41e385052e61ed49f37
        //   0xEBAf3e0b7dBB0Eb41d66875Dd64d9F0F314651B3
        //   0xbFe6D5155040803CeB12a73F8f3763C26dd64a92
        {
          privateKey: `${process.env.PRIVATE_KEY}`,
          balance: '1000000000000000000000000000000000000',
        },
        {
          privateKey: '0xca3547a47684862274b476b689f951fad53219fbde79f66c9394e30f1f0b4904',
          balance: '1000000000000000000000000000000000000',
        },
        {
          privateKey: '0x4bad9ef34aa208258e3d5723700f38a7e10a6bca6af78398da61e534be792ea8',
          balance: '1000000000000000000000000000000000000',
        },
        {
          privateKey: '0xffc03a3bd5f36131164ad24616d6cde59a0cfef48235dd8b06529fc0e7d91f7c',
          balance: '1000000000000000000000000000000000000',
        },
        {
          privateKey: '0x380c430a9b8fa9cce5524626d25a942fab0f26801d30bfd41d752be9ba74bd98',
          balance: '1000000000000000000000000000000000000',
        },
      ],
      allowUnlimitedContractSize: true,
      blockGasLimit: 800000000000000,
      gas: 80000000,
      loggingEnabled: false,
    },
    aurora_testnet: {
      chainId: 1313161555,
      url: `https://testnet.aurora.dev/`,
      accounts: [process.env.PRIVATE_KEY, process.env.PRIVATE_KEY_JERRY],
      timeout: 500000
    },
    aurora: {
      chainId: 1313161554,
      url: `https://mainnet.aurora.dev/${process.env.AURORA_API_KEY}`,
      accounts: [process.env.PRIVATE_KEY, process.env.PRIVATE_KEY_JERRY],
      timeout: 500000
    }
  },
  typechain: {
    target: 'ethers-v5',
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: 'USD',
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  mocha: {
    timeout: 500000,
  },
};

export default config;
