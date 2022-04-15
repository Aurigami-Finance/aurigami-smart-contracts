import { Env } from "./helpers/helpers";
import hre from "hardhat";
import assert from "assert";
import fs from "fs";
import path from "path";
import * as config from "./config/config";
import { BigNumber } from "ethers";
import {
  configComptroller, deployAllAuTokens,
  deployAuriLens,
  deployComptroller, deployConfigReader, deployEthRepayHelper, deployFairLaunch,
  deployInterestRateModel,
  deployPly,
  deployTestContracts,
  fetchOracle,
  fundFaucet,
  replaceConfig
} from "./deploy-functions";

const DO_DEPLOY_MAINNET: boolean = true;

// replace all string constants with token config
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  let env: Env;

  if (DO_DEPLOY_MAINNET) {
    console.log('DEPLOYING ON MAINNET');
    console.log('********************************');
    env = new Env(deployer, config.mainnetDeployConfig);
    await env.init();

    assert(env.config.IS_MAINNET);

    await deployPly(env);
  } else {
    console.log('DEPLOYING ON TESTNET');
    console.log('********************************');
    env = new Env(deployer, config.testnetDeployConfig);
    await env.init();

    assert(!env.config.IS_MAINNET);

    await deployTestContracts(env);
    await fundFaucet(env);
    await replaceConfig(env);
    // ply deployed with faucet
  }

  await deployInterestRateModel(env);
  await fetchOracle(env);
  await deployComptroller(env);
  await deployFairLaunch(env);
  await deployAuriLens(env);

  await configComptroller(env);

  await deployAllAuTokens(env);
  await deployEthRepayHelper(env);
  await deployConfigReader(env);
  // setCollateral
  fs.writeFileSync(path.resolve(__dirname, '../deployments/', env.config.EXPORT_FILENAME), JSON.stringify(env));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
