import hre from 'hardhat';
import { AuErc20, AuETH, AuriConfigReader, AuriLens, Comptroller, ERC20, EthRepayHelper, TimeQuery } from '../typechain';
import { deploy, Env, getContractAt, toWei } from './helpers/helpers';
import * as config from './config/config';
import { TokenConfig } from './config/type';
import { deployConfigReader, deployEthRepayHelper } from "./deploy-functions";
import * as mainnet from "../deployments/aurora_mainnet.json";
import * as testnet from "../deployments/aurora_testnet.json";
import { impersonateAccount } from '../test/onchain_tests/helpers';
import { INF } from './helpers/Constants';
import { BN } from 'ethereumjs-util/node_modules/@types/bn.js';
async function setToken(env: Env, comptrollerAddr: string, tokenAddr: string, underlying: TokenConfig) {
  let comptroller = await getContractAt<Comptroller>('Comptroller', comptrollerAddr);
  await comptroller._setCollateralFactor(tokenAddr, underlying.COLLATERAL_FACTOR, env.nonce());
}
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  let env = new Env(deployer, config.mainnetDeployConfig);
  await env.init(mainnet);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
