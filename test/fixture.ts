import {AuErc20__factory} from './../typechain/factories/AuErc20__factory';
import {
  AuETH,
  AuETH__factory,
  AuriOracle,
  AuriOracle__factory,
  AuriFairLaunch,
  AuriFairLaunch__factory,
  AuriLens,
  AuriLens__factory,
  Comptroller,
  Comptroller__factory,
  ERC20PresetFixedSupply,
  ERC20PresetFixedSupply__factory,
  JumpRateModel__factory,
  Ply,
  Ply__factory,
  TokenLock,
  TokenLock__factory,
  Unitroller__factory,
  AuErc20,
  TimeQuery,
  TimeQuery__factory,
} from '../typechain';
import hre, {ethers} from 'hardhat';
import {BigNumber as BN} from '@ethersproject/bignumber/lib/bignumber';
import {testnetDeployConfig as config} from '../scripts/config/config';
import {BigNumberish, constants, Contract} from 'ethers';
import {
  _1E8,
  admin,
  AURI_REWARD_SPEED,
  borrower,
  CHAINLINK_ETH_FEED_ON_ETH,
  DUMMY_ADDRESS,
  ETH_ADDRESS,
  ETH_COLLATERAL_FACTOR,
  ETH_RESERVE_FACTOR,
  INF,
  lender,
  PLY_REWARD_SPEED,
  PRECISION,
  SEIZE_SHARE,
  TOTAL_PLY_REWARDS,
  TWO,
  USDC_COLLATERAL_FACTOR,
  USDC_RESERVE_FACTOR,
  ZERO_ADDRESS,
  FLUX_ETH_FEED,
} from './Constants';
import {getCurrentTimestamp} from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';

export let rewardClaimStart: number;
export let startTime: number;
export let endTime: number;
export let rewardPerSecond: BigNumberish;

export class Fixtures {
  constructor(
    public unitroller: Comptroller,
    public oracle: AuriOracle,
    public fairLaunch: AuriFairLaunch,
    public auUSDC: AuErc20,
    public auETH: AuETH,
    public aurora: ERC20PresetFixedSupply,
    public ply: Ply,
    public tokenLock: TokenLock,
    public lens: AuriLens,
    public timeQuery: TimeQuery
  ) {}
}

function calcRewardPerSecond(totalRewards: BigNumberish, startTime: BigNumberish, endTime: BigNumberish) {
  return BN.from(totalRewards).div(BN.from(endTime).sub(startTime));
}

export async function deployOracle(auETH: Contract, auUSDC: Contract) {
  const adminAddress = await (auUSDC as AuErc20).admin();
  const EMPTY_FEED = {
    auToken: ZERO_ADDRESS,
    mainFeed: ZERO_ADDRESS,
    backupFeed: ZERO_ADDRESS,
    underlyingDecimal: 0,
  };

  const OracleFactory = (await ethers.getContractFactory('AuriOracle')) as AuriOracle__factory;
  const oracle = await OracleFactory.connect(admin).deploy(adminAddress, adminAddress, adminAddress);

  await oracle.setBackupFeedAddr([auETH.address], [FLUX_ETH_FEED]);
  await oracle.setUnderlyingDecimals([auETH.address, auUSDC.address], [18, 18]);

  return {oracle};
}
export async function fixture(): Promise<Fixtures> {
  const TimeQueryFactory = (await ethers.getContractFactory('TimeQuery')) as TimeQuery__factory;
  const timeQuery = await TimeQueryFactory.deploy();

  // mock tokens
  const TokenFactory = (await ethers.getContractFactory('ERC20PresetFixedSupply')) as ERC20PresetFixedSupply__factory;
  const aurora = await TokenFactory.deploy('AURORA', 'AURORA', BN.from(100_000_000).mul(PRECISION), admin.address);
  const usdc = await TokenFactory.deploy('USDC', 'USDC', BN.from(100_000_000).mul(PRECISION), admin.address);
  await aurora.connect(admin).transfer(lender.address, BN.from(500_000).mul(PRECISION));
  await aurora.connect(admin).transfer(borrower.address, BN.from(500_000).mul(PRECISION));
  await usdc.connect(admin).transfer(lender.address, BN.from(500_000).mul(PRECISION));
  await usdc.connect(admin).transfer(borrower.address, BN.from(500_000).mul(PRECISION));

  // Unitroller
  const UnitrollerFactory = (await ethers.getContractFactory('Unitroller')) as Unitroller__factory;
  const unitroller = await UnitrollerFactory.connect(admin).deploy();
  const setUnitroller = (await ethers.getContractAt('Comptroller', unitroller.address)) as Comptroller;

  const ComptrollerFactory = (await ethers.getContractFactory('Comptroller')) as Comptroller__factory;
  const comptroller = await ComptrollerFactory.connect(admin).deploy();

  await unitroller.connect(admin)._setPendingImplementation(comptroller.address);
  await comptroller.connect(admin)._become(unitroller.address);

  const PlyFactory = (await ethers.getContractFactory('Ply')) as Ply__factory;
  const ply = await PlyFactory.connect(admin).deploy(admin.address);

  // set rewards to unitroller
  await aurora.connect(admin).transfer(unitroller.address, BN.from(10_000_000).mul(PRECISION));
  await ply.connect(admin).transfer(unitroller.address, BN.from(100_000_000).mul(PRECISION));

  await setUnitroller.connect(admin)._setMaxAssets(4);
  await setUnitroller.connect(admin).setTokens(ply.address, aurora.address);
  await setUnitroller.connect(admin)._setCloseFactor(config.CLOSE_FACTOR);
  await setUnitroller.connect(admin)._setLiquidationIncentive(config.LIQUIDATION_INCENTIVE);
  let currentTime = Math.floor(new Date().getTime() / 1000);
  // rewardClaimStart = 2 weeks from current time
  rewardClaimStart = currentTime + 86400 * 14;
  await setUnitroller.connect(admin).setRewardClaimStart(rewardClaimStart);

  const JumpRateModelFactory = (await ethers.getContractFactory('JumpRateModel')) as JumpRateModel__factory;
  const interestRateModel = await JumpRateModelFactory.connect(admin).deploy(
    config.INTEREST_RATE_MODEL.BASE_RATE,
    config.INTEREST_RATE_MODEL.NORMAL_MULTIPLIER,
    config.INTEREST_RATE_MODEL.JUMP_MULTIPLIER,
    config.INTEREST_RATE_MODEL.KINK
  );

  const AuErc20__factory = (await ethers.getContractFactory('AuErc20')) as AuErc20__factory;
  const auUSDC = await AuErc20__factory.connect(admin).deploy(
    usdc.address,
    unitroller.address,
    interestRateModel.address,
    TWO.mul(PRECISION),
    'auUSDC',
    'auUSDC',
    8,
    admin.address
  );

  const AuETHFactory = (await hre.ethers.getContractFactory('AuETH')) as AuETH__factory;
  const auETH = await AuETHFactory.deploy(
    unitroller.address,
    interestRateModel.address,
    TWO.mul(PRECISION),
    'auETH',
    'auETH',
    8,
    admin.address
  );

  const {oracle} = await deployOracle(auETH, auUSDC);
  await setUnitroller.connect(admin)._setPriceOracle(oracle.address);
  await oracle.updateMainFeedData(auETH.address, BN.from(3500).mul(_1E8), await timeQuery.getTime());
  await oracle.updateMainFeedData(auUSDC.address, _1E8, await timeQuery.getTime());

  await usdc.connect(lender).approve(auUSDC.address, constants.MaxUint256);
  await usdc.connect(borrower).approve(auUSDC.address, constants.MaxUint256);
  await auUSDC.connect(admin)._setReserveFactor(USDC_RESERVE_FACTOR);
  await auETH.connect(admin)._setReserveFactor(ETH_RESERVE_FACTOR);
  await auUSDC.connect(admin)._setProtocolSeizeShare(SEIZE_SHARE);
  await setUnitroller.connect(admin)._supportMarket(auUSDC.address);
  await setUnitroller.connect(admin)._supportMarket(auETH.address);
  await setUnitroller
    .connect(admin)
    ._setRewardSpeeds(
      0,
      [auUSDC.address, auUSDC.address, auETH.address, auETH.address],
      [PLY_REWARD_SPEED, PLY_REWARD_SPEED, PLY_REWARD_SPEED, PLY_REWARD_SPEED],
      [true, false, true, false]
    );
  await setUnitroller
    .connect(admin)
    ._setRewardSpeeds(
      1,
      [auUSDC.address, auUSDC.address, auETH.address, auETH.address],
      [AURI_REWARD_SPEED, AURI_REWARD_SPEED, AURI_REWARD_SPEED, AURI_REWARD_SPEED],
      [true, false, true, false]
    );

  await setUnitroller.connect(admin)._setCollateralFactor(auUSDC.address, USDC_COLLATERAL_FACTOR);
  await setUnitroller.connect(admin)._setCollateralFactor(auETH.address, ETH_COLLATERAL_FACTOR);

  const TokenLockFactory = (await ethers.getContractFactory('TokenLock')) as TokenLock__factory;
  const tokenLock = await TokenLockFactory.connect(admin).deploy(ply.address, unitroller.address);

  await setUnitroller.connect(admin).setLockAddress(tokenLock.address);
  const FairLaunchFactory = (await ethers.getContractFactory('AuriFairLaunch')) as AuriFairLaunch__factory;
  const fairLaunch = await FairLaunchFactory.connect(admin).deploy(tokenLock.address, unitroller.address);
  await ply.connect(admin).transfer(fairLaunch.address, TOTAL_PLY_REWARDS);

  startTime = rewardClaimStart;
  endTime = (await tokenLock.calcUnlockTimes(lender.address)).unlockBegin.toNumber();
  rewardPerSecond = calcRewardPerSecond(TOTAL_PLY_REWARDS, startTime, endTime);

  const AuriLensFactory = (await ethers.getContractFactory('AuriLens')) as AuriLens__factory;
  const auriLens = await AuriLensFactory.deploy();
  await setUnitroller.connect(admin).setWhitelisted(auriLens.address, true);

  return new Fixtures(setUnitroller, oracle, fairLaunch, auUSDC, auETH, aurora, ply, tokenLock, auriLens, timeQuery);
}
