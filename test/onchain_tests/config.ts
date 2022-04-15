import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {providers, Wallet, BigNumber as BN} from 'ethers';
import {exit} from 'process';
import deployment from '../../deployment.json';
import {
  AuErc20,
  AuETH,
  AuriOracle,
  AuriFairLaunch,
  AuriLens,
  Comptroller,
  ERC20,
  FluxPriceFeed,
  JumpRateModel,
  TokenLock,
  Unitroller,
} from '../../typechain';
import {getContract} from './helpers';

export enum Network {
  MAINNET,
  TESTNET,
}

export interface Token<T = AuErc20> {
  contract: ERC20;
  auContract: T;
  whale?: string;
}

export interface TestTokens {
  USDC?: Token;
  PLY?: Token;
  WNEAR?: Token;
  AURORA?: Token;
  WBTC?: Token;
  USDT?: Token;
  ETH?: Token;
  DAI?: Token;
}

export interface TestEnv {
  networkId: Network;
  deployer?: string;
  unitroller?: Unitroller;
  comptroller?: Comptroller;
  tokenLock?: TokenLock;
  lens?: AuriLens;
  fairLaunch?: AuriFairLaunch;
  oracle?: AuriOracle;
  interestRateModel?: JumpRateModel;
  tokens?: TestTokens;
}

export async function deploymentFixture(): Promise<TestEnv> {
  const env: TestEnv = {
    networkId: deployment.networkId == 1313161555 ? Network.TESTNET : Network.MAINNET,
  };
  env.deployer = deployment.deployer;
  env.unitroller = await getContract('Unitroller', deployment.unitroller);
  env.comptroller = await getContract('Comptroller', deployment.unitroller);
  env.tokenLock = await getContract('TokenLock', deployment.tokenLock);
  env.lens = await getContract('AuriLens', deployment.lens);
  env.fairLaunch = await getContract('AuriFairLaunch', deployment.fairLaunch);
  env.oracle = await getContract('AuriOracle', deployment.oracle);
  env.interestRateModel = await getContract('JumpRateModel', deployment.interestRateModel);

  env.tokens = {};
  env.tokens.PLY = {
    contract: await getContract('ERC20', deployment.ply),
    auContract: await getContract('AuErc20', deployment.auTokens.PLY),
    whale: deployment.deployer,
  };
  if (deployment.supportedTokens.USDC !== null) {
    env.tokens.USDC = {
      contract: await getContract('ERC20', deployment.supportedTokens.USDC),
      auContract: await getContract('AuErc20', deployment.auTokens.USDC),
      whale: env.networkId == Network.MAINNET ? '0x2fe064B6c7D274082aa5d2624709bC9AE7D16C77' : deployment.deployer,
    };
  }
  if (deployment.supportedTokens.WBTC !== null) {
    env.tokens.WBTC = {
      contract: await getContract('ERC20', deployment.supportedTokens.WBTC),
      auContract: await getContract('AuErc20', deployment.auTokens.WBTC),
      whale: env.networkId == Network.MAINNET ? '0xbc8A244e8fb683ec1Fd6f88F3cc6E565082174Eb' : deployment.deployer,
    };
  }
  if (deployment.supportedTokens.AURORA !== null) {
    env.tokens.AURORA = {
      contract: await getContract('ERC20', deployment.supportedTokens.AURORA),
      auContract: await getContract('AuErc20', deployment.auTokens.AURORA),
      whale: env.networkId == Network.MAINNET ? '0xd1654a7713617d41A8C9530Fb9B948d00e162194' : deployment.deployer,
    };
  }
  if (deployment.supportedTokens.USDT !== null) {
    env.tokens.USDT = {
      contract: await getContract('ERC20', deployment.supportedTokens.USDT),
      auContract: await getContract('AuErc20', deployment.auTokens.USDT),
      whale: env.networkId == Network.MAINNET ? '0x2fe064B6c7D274082aa5d2624709bC9AE7D16C77' : deployment.deployer,
    };
  }
  if (deployment.supportedTokens.DAI !== null) {
    env.tokens.DAI = {
      contract: await getContract('ERC20', deployment.supportedTokens.DAI),
      auContract: await getContract('AuErc20', deployment.auTokens.DAI),
      whale: env.networkId == Network.MAINNET ? '0xc90dB0d8713414d78523436dC347419164544A3f' : deployment.deployer,
    };
  }
  if (deployment.supportedTokens.WNEAR !== null) {
    env.tokens.WNEAR = {
      contract: await getContract('ERC20', deployment.supportedTokens.WNEAR),
      auContract: await getContract('AuErc20', deployment.auTokens.WNEAR),
      whale: env.networkId == Network.MAINNET ? '0xbc8A244e8fb683ec1Fd6f88F3cc6E565082174Eb' : deployment.deployer,
    };
  }
  return env;
}
