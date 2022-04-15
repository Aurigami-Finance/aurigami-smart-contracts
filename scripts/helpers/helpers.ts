import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber as BN, Contract } from 'ethers';
import hre from 'hardhat';
import {
  AuErc20,
  AuETH,
  AuriConfigReader,
  AuriFairLaunch,
  AuriLens,
  AuriOracle,
  Comptroller,
  ERC20,
  EthRepayHelper,
  Faucet,
  InterestRateModel,
  JumpRateModel,
  Ply,
  Unitroller,
} from '../../typechain';
import { GlobalConfig } from '../config/type';

export class NonceHelper {
  private _nonce: number;
  private readonly _user: SignerWithAddress;

  constructor(user: SignerWithAddress) {
    this._user = user;
  }

  async init() {
    this._nonce = (await this._user.getTransactionCount()) - 1;
  }

  get() {
    if (hre.network.name == 'hardhat') {
      return {};
    } else {
      return {
        nonce: ++this._nonce,
      };
    }
  }
}

interface TestContracts {
  USDC: ERC20;
  WBTC: ERC20;
  WNEAR: ERC20;

  PLY: Ply;

  DAI: ERC20;

  USDT: ERC20;

  faucet: Faucet;
}

interface DeployedData {
  unitroller: string;
  comptrollerImpl: string;
  comptroller: string;
  PLY: string;
  jumpRateModel: string;
  oracle: string;
  auTokens: {
    USDC: string;
    ETH: string;
    WBTC: string;
    USDT: string;
    DAI: string;
    WNEAR: string;
    STNEAR: string;
    AURORA: string;
    TRI: string;
  };
  fairLaunch: string;
  auriLens: string;
  ethRepayHelper: string;
  configReader: string;
}

export class Env {
  private nonceHelper: NonceHelper;

  deployer: SignerWithAddress;
  unitroller: Unitroller;
  comptrollerImpl: Comptroller;
  comptroller: Comptroller;
  PLY: Ply;
  jumpRateModel: InterestRateModel;
  oracle: AuriOracle;
  auTokens: Record<string, string>;
  fairLaunch: AuriFairLaunch;
  auriLens: AuriLens;

  auETH: AuETH;
  auWBTC: AuErc20;
  auUSDC: AuErc20;
  auUSDT: AuErc20;
  auWNEAR: AuErc20;
  auDAI: AuErc20;
  auAURORA: AuErc20;
  auSTNEAR: AuErc20;
  auTRI: AuErc20;


  config: GlobalConfig;

  test: TestContracts;
  ethRepayHelper: EthRepayHelper;
  configReader: AuriConfigReader;

  constructor(deployer: SignerWithAddress, config: GlobalConfig) {
    this.deployer = deployer;
    this.nonceHelper = new NonceHelper(this.deployer);
    this.auTokens = {};
    this.config = config;
    this.test = {} as TestContracts;
  }

  async init(data: DeployedData = null) {
    await this.nonceHelper.init();
    if (data == null) return;
    this.unitroller = await getContractAt<Unitroller>('Unitroller', data.unitroller);
    this.comptroller = await getContractAt<Comptroller>('Comptroller', data.comptroller);
    this.comptrollerImpl = await getContractAt<Comptroller>('Comptroller', data.comptrollerImpl);
    this.PLY = await getContractAt<Ply>('Ply', data.PLY);
    this.jumpRateModel = await getContractAt<JumpRateModel>('JumpRateModel', data.jumpRateModel);
    this.oracle = await getContractAt<AuriOracle>('AuriOracle', data.oracle);
    this.auETH = await getContractAt<AuETH>('AuETH', data.auTokens.ETH);
    this.auDAI = await getContractAt<AuErc20>('AuErc20', data.auTokens.DAI);
    this.auWBTC = await getContractAt<AuErc20>('AuErc20', data.auTokens.WBTC);
    this.auWNEAR = await getContractAt<AuErc20>('AuErc20', data.auTokens.WNEAR);
    this.auUSDT = await getContractAt<AuErc20>('AuErc20', data.auTokens.USDT);
    this.auUSDC = await getContractAt<AuErc20>('AuErc20', data.auTokens.USDC);
    this.auAURORA = await getContractAt<AuErc20>('AuErc20', data.auTokens.AURORA);
    this.auSTNEAR = await getContractAt<AuErc20>('AuErc20', data.auTokens.STNEAR);
    this.auTRI = await getContractAt<AuErc20>('AuErc20', data.auTokens.TRI);
    this.fairLaunch = await getContractAt<AuriFairLaunch>('AuriFairLaunch', data.fairLaunch);
    this.auriLens = await getContractAt<AuriLens>('AuriLens', data.auriLens);
    this.ethRepayHelper = await getContractAt<EthRepayHelper>('EthRepayHelper', data.ethRepayHelper);
    this.configReader = await getContractAt<AuriConfigReader>('AuriConfigReader', data.configReader);
  }

  nonce() {
    return this.nonceHelper.get();
  }

  toJSON() {
    return {
      deployer: this.deployer.address,
      unitroller: this.unitroller.address,
      comptrollerImpl: this.comptrollerImpl.address,
      comptroller: this.comptroller.address,
      PLY: this.PLY.address,
      jumpRateModel: this.jumpRateModel.address,
      oracle: this.oracle.address,
      auTokens: this.auTokens,
      fairLaunch: this.fairLaunch.address,
      auriLens: this.auriLens.address,
      ethRepayHelper: this.ethRepayHelper.address,
      configReader: this.configReader.address,
      test:
        this.test.USDC == null
          ? {}
          : {
            USDC: this.test.USDC.address,
            USDT: this.test.USDT.address,
            DAI: this.test.DAI.address,
            WBTC: this.test.WBTC.address,
            WNEAR: this.test.WNEAR.address,
            PLY: this.test.PLY.address,
            faucet: this.test.faucet.address,
          },
    };
  }
}

export async function deploy<CType extends Contract>(env: Env, abiType: string, args: any[], name?: string) {
  name = name || abiType;
  console.log(`Deploying ${name}...`);
  const contractFactory = await hre.ethers.getContractFactory(abiType);
  const contract = await contractFactory.connect(env.deployer).deploy(...args, env.nonce());
  await contract.deployed();
  console.log(`${name} deployed at address: ${(await contract).address}`);

  return contract as CType;
}

export async function getContractAt<CType extends Contract>(abiType: string, address: string) {
  return (await hre.ethers.getContractAt(abiType, address)) as CType;
}

export function toWei(amount: number, decimals: number) {
  return BN.from(amount).mul(BN.from(10).pow(decimals));
}

export function JSONReplacerBigNum(key: string, value: any): string {
  if (typeof value == 'object' && 'type' in value && value['type'] === 'BigNumber') {
    return BN.from(value['hex']).toString();
  }
  return value;
}
