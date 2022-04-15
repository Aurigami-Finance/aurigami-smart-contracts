import hre from 'hardhat';
import {Comptroller} from '../typechain';
import {Env, getContractAt} from './helpers/helpers';
import * as config from './config/config';
import * as testnet from '../deployments/aurora_testnet.json';
import * as mainnet from '../deployments/aurora_mainnet.json';
import assert from 'assert';

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const DO_DEPLOY_MAINNET: boolean = true;
  let env: Env;

  if (DO_DEPLOY_MAINNET) {
    console.log('RUNNING ON MAINNET');
    console.log('********************************');
    env = new Env(deployer, config.mainnetDeployConfig);
    await env.init();

    assert(env.config.IS_MAINNET);
  } else {
    console.log('RUNNING ON TESTNET');
    console.log('********************************');
    env = new Env(deployer, config.testnetDeployConfig);
    await env.init();

    assert(!env.config.IS_MAINNET);
  }

  env.comptroller = await getContractAt<Comptroller>('Comptroller', mainnet.comptroller);

  for (let token in mainnet.auTokens) {
    for (let tokenData of env.config.TOKENS) {
      if (token == tokenData.name) {
        let auTokenAddr = mainnet.auTokens[token];
        console.log('setting for', 'au' + token, 'at', auTokenAddr);
        await env.comptroller._setCollateralFactor(auTokenAddr, tokenData.COLLATERAL_FACTOR, env.nonce());
        break;
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
