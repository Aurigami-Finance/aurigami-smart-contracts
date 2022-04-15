import { deploy, Env, getContractAt, toWei } from "./helpers/helpers";
import { TokenConfig } from "./config/type";
import {
  AuErc20,
  AuETH,
  AuriConfigReader,
  AuriFairLaunch,
  AuriLens,
  AuriOracle,
  Comptroller,
  ERC20PresetFixedSupplyAuri,
  EthRepayHelper,
  Faucet,
  JumpRateModel,
  Ply,
  Unitroller
} from "../typechain";
import { BigNumber as BN } from "ethers";
import { _1E18, INF } from "./helpers/Constants";

export async function getInitialExchangeRateMantissa(tokenConfig: TokenConfig) {
  const DEFAULT_RATE = _1E18.mul(2);
  if (tokenConfig.UNDERLYING_DECIMAL < 10) {
    let divisor = BN.from(10).pow(10 - tokenConfig.UNDERLYING_DECIMAL);
    return DEFAULT_RATE.div(divisor);
  } else {
    let divisor = BN.from(10).pow(tokenConfig.UNDERLYING_DECIMAL - 10);
    return DEFAULT_RATE.mul(divisor);
  }
}

export async function deployComptroller(env: Env) {
  env.unitroller = await deploy<Unitroller>(env, "Unitroller", []);
  env.comptrollerImpl = await deploy<Comptroller>(env, "Comptroller", []);

  await env.unitroller._setPendingImplementation(env.comptrollerImpl.address, env.nonce());
  await env.comptrollerImpl._become(env.unitroller.address, env.nonce());
  console.log("Done become");
  env.comptroller = await getContractAt("Comptroller", env.unitroller.address);
}

export async function deployPly(env: Env) {
  env.PLY = await deploy<Ply>(env, "Ply", [env.config.GOVERNANCE_MULTISG]);
}

export async function deployInterestRateModel(env: Env) {
  env.jumpRateModel = await deploy<JumpRateModel>(env, "JumpRateModel", [
    env.config.INTEREST_RATE_MODEL.BASE_RATE,
    env.config.INTEREST_RATE_MODEL.NORMAL_MULTIPLIER,
    env.config.INTEREST_RATE_MODEL.JUMP_MULTIPLIER,
    env.config.INTEREST_RATE_MODEL.KINK
  ]);
}

// verify everything has been set
export async function configComptroller(env: Env) {
  await env.comptroller.setTokens(env.PLY.address, env.config.AURORA_ADDRESS, env.nonce()); // set token addresses in unitroller
  console.log("Done setTokens");
  await env.comptroller._setCloseFactor(env.config.CLOSE_FACTOR, env.nonce()); // set close factor
  console.log("Done _setCloseFactor");
  await env.comptroller._setLiquidationIncentive(env.config.LIQUIDATION_INCENTIVE, env.nonce()); // set liquidation incentive
  console.log("Done _setLiquidationIncentive");
  await env.comptroller.setRewardClaimStart(env.config.REWARD_CLAIM_START, env.nonce()); // set reward claim start
  console.log("Done setRewardClaimStart");
  await env.comptroller._setMaxAssets(env.config.MAX_ASSET, env.nonce());
  console.log("Done _setMaxAssets");
  await env.comptroller._setPriceOracle(env.config.ORACLE, env.nonce());
  console.log("Done _setPriceOracle");
  await env.comptroller.setWhitelisted(env.auriLens.address, true, env.nonce());
  console.log("Done setWhitelisted");
  await env.comptroller._setBorrowCapGuardian(env.config.BORROW_CAP_GUARDIAN, env.nonce());
  console.log("Done _setBorrowCapGuardian");
  await env.comptroller._setPauseGuardian(env.config.PAUSE_GUARDIAN, env.nonce());
  console.log("Done setPauseGuardian");
}

export async function fetchOracle(env: Env) {
  env.oracle = await getContractAt<AuriOracle>("AuriOracle", env.config.ORACLE);
}

export async function deployAllAuTokens(env: Env) {
  for (let token of env.config.TOKENS) {
    env.auTokens[token.name] = (await deployAuToken(env, token)).address;
  }
}

export async function deployAuToken(env: Env, underlying: TokenConfig) {
  let auToken: AuETH | AuErc20;
  if (underlying.name == "ETH") {
    auToken = await deployAuETH(env, underlying);
  } else {
    auToken = await deployAuErc20(env, underlying);
  }
  console.log("_setReserveFactor");
  await auToken._setReserveFactor(underlying.RESERVE_FACTOR, env.nonce()); // set reserve factor
  console.log("_setProtocolSeizeShare");
  await auToken._setProtocolSeizeShare(underlying.SEIZE_SHARE, env.nonce()); // set seize share
  console.log("_supportMarket");
  await env.comptroller._supportMarket(auToken.address, env.nonce()); // add token to market

  if (underlying.name == "PLY") {
    await env.comptroller._setBorrowPaused(auToken.address, true, env.nonce()); // pause borrow for ply
  }

  console.log("_setRewardSpeeds0");
  await env.comptroller._setRewardSpeeds(
    0,
    [auToken.address, auToken.address],
    [underlying.PLY_REWARD_LEND_SPEED, underlying.PLY_REWARD_BORROW_SPEED],
    [true, false],
    env.nonce()
  );

  console.log("_setRewardSpeeds1");
  await env.comptroller._setRewardSpeeds(
    1,
    [auToken.address, auToken.address],
    [underlying.AURORA_REWARD_LEND_SPEED, underlying.AURORA_REWARD_BORROW_SPEED],
    [true, false],
    env.nonce()
  );

  // console.log("_setCollateralFactor");
  // await env.comptroller._setCollateralFactor(auToken.address, underlying.COLLATERAL_FACTOR,env.nonce());

  console.log("Done");
  return auToken;
}

export async function deployAuETH(env: Env, token: TokenConfig) {
  return await deploy<AuETH>(env, "AuETH", [
    env.comptroller.address,
    env.jumpRateModel.address,
    getInitialExchangeRateMantissa(token),
    "auETH",
    "auETH",
    8,
    env.deployer.address
  ]);
}

export async function deployAuErc20(env: Env, token: TokenConfig) {
  return await deploy<AuErc20>(
    env,
    "AuErc20",
    [
      token.name == "PLY" ? env.PLY.address : token.address, // not very nice
      env.comptroller.address,
      env.jumpRateModel.address,
      getInitialExchangeRateMantissa(token),
      "au" + token.name,
      "au" + token.name,
      8,
      env.deployer.address
    ],
    "au" + token.name
  );
}

// calling tx directly from contract doesn't look very nice (because there are no messages)
export async function deployFairLaunch(env: Env) {
  // env.fairLaunch = await deploy<AuriFairLaunch>(env, "AuriFairLaunch", [
  //   env.tokenLock.address,
  //   env.comptroller.address
  // ]);
}

export async function deployAuriLens(env: Env) {
  env.auriLens = await deploy<AuriLens>(env, "AuriLens", []);
}

export async function deployTestContracts(env: Env) {
  env.test.faucet = await deploy<Faucet>(env, "Faucet", []);

  env.test.USDT = await deploy<ERC20PresetFixedSupplyAuri>(env, "ERC20PresetFixedSupplyAuri", [
    "USDT",
    "USDT",
    INF,
    6,
    env.deployer.address
  ]);
  env.test.USDC = await deploy<ERC20PresetFixedSupplyAuri>(env, "ERC20PresetFixedSupplyAuri", [
    "USDC",
    "USDC",
    INF,
    6,
    env.deployer.address
  ]);
  env.test.DAI = await deploy<ERC20PresetFixedSupplyAuri>(env, "ERC20PresetFixedSupplyAuri", [
    "DAI",
    "DAI",
    INF,
    18,
    env.deployer.address
  ]);
  env.test.WNEAR = await deploy<ERC20PresetFixedSupplyAuri>(env, "ERC20PresetFixedSupplyAuri", [
    "WNEAR",
    "WNEAR",
    INF,
    24,
    env.deployer.address
  ]);
  env.test.WBTC = await deploy<ERC20PresetFixedSupplyAuri>(env, "ERC20PresetFixedSupplyAuri", [
    "WBTC",
    "WBTC",
    INF,
    8,
    env.deployer.address
  ]);
  await deployPly(env);
  env.test.PLY = env.PLY;

  let test = env.test;
  for (let token of [test.DAI, test.PLY, test.USDC, test.USDT, test.WBTC, test.WNEAR]) {
    await token.approve(test.faucet.address, INF, env.nonce());
  }
}

export async function fundFaucet(env: Env) {
  let _1E9 = 10 ** 9;
  await env.test.faucet.fundToken(env.test.USDC.address, toWei(5000, 6), toWei(_1E9, 6), env.nonce());
  console.log("Done USDC");
  await env.test.faucet.fundToken(env.test.WBTC.address, toWei(1, 8).div(16), toWei(10 ** 5, 8), env.nonce());
  console.log("Done WBTC");
  await env.test.faucet.fundToken(env.test.USDT.address, toWei(5000, 6), toWei(_1E9, 6), env.nonce());
  console.log("Done USDT");
  await env.test.faucet.fundToken(env.test.DAI.address, toWei(5000, 18), toWei(_1E9, 18), env.nonce());
  console.log("Done DAI");
  await env.test.faucet.fundToken(env.test.PLY.address, toWei(5000, 18), toWei(_1E9, 18), env.nonce());
  console.log("Done PLY");
  await env.test.faucet.fundToken(env.test.WNEAR.address, toWei(500, 24), toWei(_1E9, 24), env.nonce());
  console.log("Done WNEAR");
}

export async function replaceConfig(env: Env) {
  let dummyTokenContracts = [env.test.USDC, env.test.WBTC, env.test.USDT, env.test.DAI, env.test.PLY, env.test.WNEAR];
  for (let i = 0; i < env.config.TOKENS.length; i++) {
    for (let token of dummyTokenContracts) {
      if ((await token.name()) === env.config.TOKENS[i].name) {
        console.log("FOUND", await token.name());
        env.config.TOKENS[i].address = token.address;
      }
    }
  }
}

export async function deployEthRepayHelper(env: Env) {
  env.ethRepayHelper = await deploy<EthRepayHelper>(env, "EthRepayHelper", [env.auTokens["ETH"]]);
}

export async function deployConfigReader(env: Env) {
  env.configReader = await deploy<AuriConfigReader>(env, "AuriConfigReader", [env.comptroller.address, env.jumpRateModel.address]);
}