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
import {BigNumber as BN, Wallet} from 'ethers';
import {assert, expect} from 'chai';
import {
  advanceTime,
  evm_revert,
  evm_snapshot,
  mineAllPendingTransactions,
  minerStart,
  minerStop,
} from './hardhat-helpers';

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

describe('Reward test 2', () => {
  const wallets = waffle.provider.getWallets();
  const [alice, bob, charlie, dave, eve] = wallets;
  let globalSnapshotId;
  let snapshotId;
  before(async () => {
    globalSnapshotId = await evm_snapshot();
    ({unitroller, oracle, fairLaunch, auUSDC, auETH, aurora, ply, tokenLock, lens} = await loadFixture(fixture));
    await oracle.setPriceValidity(INF);
    USDC = await ethers.getContractAt('ERC20', await auUSDC.underlying());
    for (let person of wallets) {
      await USDC.connect(admin).transfer(person.address, REF_AMOUNT.mul(200));
      await USDC.connect(person).approve(auUSDC.address, INF);
      const bal = await ply.balanceOf(person.address);
      if (bal.gt(0)) await ply.connect(person).transfer(ZERO_ADDRESS.replace('00', '11'), bal);
    }
    snapshotId = await evm_snapshot();
  });

  async function revertSnapshot() {
    await evm_revert(snapshotId);
    snapshotId = await evm_snapshot();
  }

  beforeEach(async () => {
    await revertSnapshot();
  });

  // alice will simulate other wallets' activity
  async function mint(person: Wallet, auToken: AuErc20 | AuETH) {
    assert(person.address != alice.address);
    if (auToken.address == auUSDC.address) {
      await auUSDC.connect(person).mint(REF_AMOUNT);
      await auUSDC.connect(alice).mint(REF_AMOUNT);
      await auUSDC.connect(person).borrow(REF_AMOUNT.div(100));
      await auUSDC.connect(alice).borrow(REF_AMOUNT.div(100));
    } else {
      await auETH.connect(person).mint({value: REF_AMOUNT});
      await auETH.connect(alice).mint({value: REF_AMOUNT});
      await auETH.connect(person).borrow(REF_AMOUNT.div(100));
      await auETH.connect(alice).borrow(REF_AMOUNT.div(100));
    }
  }

  async function redeem(person: Wallet, auToken: AuErc20 | AuETH) {
    assert(person.address != alice.address);
    let redeemAmount = (await auToken.balanceOf(person.address)).div(2);
    if (redeemAmount.eq(0)) return;

    if (auToken.address == auUSDC.address) {
      await auUSDC.connect(person).redeem(redeemAmount);
      await auUSDC.connect(alice).redeem(redeemAmount);
    } else {
      await auETH.connect(person).redeem(redeemAmount);
      await auETH.connect(alice).redeem(redeemAmount);
    }
  }

  async function allRewardAccrued(account: Wallet): Promise<BN> {
    await auUSDC.connect(account).mint(0);
    await auETH.connect(account).mint({value: 0});
    await auUSDC.connect(account).borrow(0);
    await auETH.connect(account).borrow(0);

    return (await ply.balanceOf(account.address))
      .add(await tokenLock.lockedAmounts(account.address))
      .add(await unitroller.rewardAccrued(0, account.address));
  }

  function approxBN(a: BN, b: BN) {
    expect(a.sub(b).abs()).to.be.lte(a.div(1000));
  }

  async function checkReward() {
    let aliceRw = await allRewardAccrued(alice);
    let othersRw = BN.from(0);
    for (let i = 1; i < wallets.length; ++i) othersRw = othersRw.add(await allRewardAccrued(wallets[i]));
    await approxBN(aliceRw, othersRw);
  }

  it('Scenario 1 testing', async () => {
    // pre mint for reward accounting to start
    await mint(bob, auETH);
    await mint(bob, auUSDC);

    const NUM_ITER = 100;
    for (let i = 0; i < NUM_ITER; ++i) {
      let actor = wallets[1 + (i % 4)];
      let action = i % 7 <= 3; // Random action
      let currency = i % 5 <= 2 ? auUSDC : auETH; // Random asset

      if (i % 3 == 0) {
        // claim reward along the way
        await unitroller.connect(actor)['claimReward(uint8,address)'](0, actor.address);
      }

      if (action == false) {
        await mint(actor, currency);
      } else {
        await redeem(actor, currency);
      }

      const bal = await currency.balanceOf(actor.address);
      const friend = wallets[1 + ((i + 1) % 4)];
      if (bal.gt(0)) await currency.connect(actor).transfer(friend.address, bal.div(2));

      await advanceTime(ONE_DAY.mul(2));
      await checkReward();
    }

    approxBN(
      (await allRewardAccrued(alice)).mul(2),
      PLY_REWARD_SPEED.mul(
        ONE_DAY.mul(2) // 2 days per iteration
          .mul(2) // borrow & supply
          .mul(2) // 2 assets USDC and ETH
          .mul(NUM_ITER)
      )
    );
  });
});
