import {fixture} from './fixture';
import {
  AggregatorV3Interface,
  AggregatorV3Interface__factory,
  AuErc20,
  AuETH,
  AuriFairLaunch,
  AuriLens,
  AuriOracle,
  AuriPriceFeed,
  AuriPriceFeed__factory,
  Comptroller,
  ComptrollerNoReward__factory,
  ERC20,
  ERC20PresetFixedSupply,
  Ply,
  TokenLock,
  Unitroller,
} from '../typechain';
import {loadFixture} from 'ethereum-waffle';
import {ethers, waffle} from 'hardhat';
import hre from 'hardhat';
import {
  admin,
  AURI_REWARD_SPEED,
  CHAINLINK_ETH_FEED_ON_ETH,
  ETH_ADDRESS,
  FLUX_ETH_FEED,
  INF,
  ONE_DAY,
  ONE_E_18,
  ONE_MONTH,
  PLY_REWARD_SPEED,
  ZERO,
  ZERO_ADDRESS,
} from './Constants';
import {BigNumber as BN} from 'ethers';
import {expect} from 'chai';
import {advanceTime, evm_revert, evm_snapshot} from './hardhat-helpers';

let unitroller: Comptroller;
let oracle: AuriOracle;
let fairLaunch: AuriFairLaunch;
let USDC: ERC20;
let auUSDC: AuErc20;
let auETH: AuETH;
let aurora: ERC20PresetFixedSupply;
let ply: Ply;
let tokenLock: TokenLock;
let lens: AuriLens;
let auriETHFeed: AuriPriceFeed;
let auriUSDCFeed: AuriPriceFeed;
let FluxEthFeed: AggregatorV3Interface;
let ChainlinkEthFeed: AggregatorV3Interface;
const REF_AMOUNT: BN = BN.from(100000);

describe('Math test', () => {
  const [alice, bob, charlie, dave, eve] = waffle.provider.getWallets();
  let globalSnapshotId;
  let snapshotId;
  before(async () => {
    globalSnapshotId = await evm_snapshot();
    ({unitroller, oracle, fairLaunch, auUSDC, auETH, aurora, ply, tokenLock, lens} = await loadFixture(fixture));
    await oracle.setPriceValidity(INF);
    USDC = await ethers.getContractAt('ERC20', await auUSDC.underlying());
    await USDC.connect(admin).transfer(alice.address, REF_AMOUNT.mul(100));
    snapshotId = await evm_snapshot();
  });

  async function revertSnapshot() {
    await evm_revert(snapshotId);
    snapshotId = await evm_snapshot();
  }

  beforeEach(async () => {
    await revertSnapshot();
  });

  it('Testing math for mint & borrow', async () => {
    await auETH.connect(charlie).mint({value: REF_AMOUNT.mul(2)});
    const exchangeRate = await auUSDC.callStatic.exchangeRateCurrent();
    await auUSDC.connect(alice).mint(REF_AMOUNT);
    expect(await auUSDC.balanceOf(alice.address)).to.be.eq(REF_AMOUNT.mul(ONE_E_18).div(exchangeRate));

    expect(auUSDC.connect(alice).callStatic.borrow(REF_AMOUNT.mul(81).div(100))).to.be.reverted;

    await auUSDC.connect(alice).callStatic.borrow(REF_AMOUNT.mul(79).div(100));
  });

  it('Testing math on interest', async () => {
    await USDC.connect(admin).transfer(bob.address, REF_AMOUNT.mul(2));
    await USDC.connect(bob).approve(auUSDC.address, INF);
    await auUSDC.connect(bob).mint(REF_AMOUNT.mul(2));

    await auETH.connect(alice).mint({value: ONE_E_18});
    await unitroller.enterMarkets([auETH.address]);

    let preBal = await USDC.balanceOf(alice.address);
    await auUSDC.connect(alice).borrow(REF_AMOUNT);
    let afterBorrowBal = await USDC.balanceOf(alice.address);
    await advanceTime(ONE_MONTH);
    await USDC.connect(alice).approve(auUSDC.address, INF);

    const borrowBal = await auUSDC.callStatic.borrowBalanceCurrent(alice.address);
    await auUSDC.connect(alice).repayBorrow(borrowBal);

    let afterRepayBal = await USDC.balanceOf(alice.address);
    expect(preBal).to.be.lt(afterBorrowBal);
    expect(preBal).to.be.gt(afterRepayBal);
  });
});
