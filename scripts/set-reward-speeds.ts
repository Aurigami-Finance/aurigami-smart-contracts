import hre from 'hardhat';
import { AuErc20, AuETH, AuriConfigReader, Comptroller, ERC20, EthRepayHelper, TimeQuery } from '../typechain';
import { deploy, Env, getContractAt, toWei } from './helpers/helpers';
import * as config from './config/config';
import { TokenConfig } from './config/type';
import { deployConfigReader, deployEthRepayHelper } from "./deploy-functions";
import * as mainnet from "../deployments/aurora_mainnet.json";
import * as testnet from "../deployments/aurora_testnet.json";
import { impersonateAccount } from '../test/onchain_tests/helpers';
import { INF } from './helpers/Constants';
import { BN } from 'ethereumjs-util/node_modules/@types/bn.js';
import { BigNumber } from 'ethers';
async function setToken(env: Env, comptrollerAddr: string, tokenAddr: string, underlying: TokenConfig) {
  let comptroller = await getContractAt<Comptroller>('Comptroller', comptrollerAddr);
  await comptroller._setCollateralFactor(tokenAddr, underlying.COLLATERAL_FACTOR, env.nonce());
}
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  let env = new Env(deployer, config.mainnetDeployConfig);
  await env.init(mainnet);

  let tokens: string[] = [];
  let speeds: BigNumber[] = [];
  let isSupplys: boolean[] = []
  for (let token of [env.auDAI, env.auETH, env.auUSDC, env.auUSDT, env.auWBTC, env.auWNEAR]) {
    tokens = tokens.concat([token.address, token.address]);
    speeds = speeds.concat([BigNumber.from(1), BigNumber.from(1)]);
    isSupplys = isSupplys.concat([true, false]);
  }
  await env.comptroller._setRewardSpeeds(0,
    tokens,
    speeds,
    isSupplys, env.nonce());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
