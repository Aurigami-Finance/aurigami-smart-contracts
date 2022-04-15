import {ethers, waffle} from 'hardhat';
import chai, {expect} from 'chai';
import {BigNumber as BN} from 'ethers';
import {
  AuErc20,
  AuETH,
  AuriFairLaunch,
  AuriLens,
  AuriOracle,
  Comptroller,
  ERC20PresetFixedSupply,
  Ply,
  TokenLock,
  TokenLock__factory,
} from '../typechain';
import {testnetDeployConfig as config} from '../scripts/config/config';
import {
  admin,
  borrower,
  INF,
  lender,
  MAX_UINT,
  MAX_UINT_96,
  ONE,
  ONE_DAY,
  ONE_E_18,
  ONE_WEEK,
  ONE_YEAR,
  PRECISION,
  ZERO,
  ZERO_ADDRESS,
} from './Constants';
import {endTime, fixture, rewardClaimStart, rewardPerSecond, startTime} from './fixture';
import {advanceTime, moveToTimestamp, setNextBlockTimeStamp} from './hardhat-helpers';

const {solidity, loadFixture} = waffle;
chai.use(solidity);

const verifyPoolInfo = async (poolData: any) => {
  let onchainData = await fairLaunch.getPoolInfo(poolData.id);
  expect(poolData.rewardPerSecond).to.be.eq(onchainData.rewardPerSecond);
  expect(poolData.accRewardPerShare).to.be.eq(onchainData.accRewardPerShare);
  expect(poolData.totalStake).to.be.eq(onchainData.totalStake);
  expect(poolData.stakeToken).to.be.eq(onchainData.stakeToken);
  expect(poolData.startTime).to.be.eq(onchainData.startTime);
  expect(poolData.endTime).to.be.eq(onchainData.endTime);
  expect(poolData.lastRewardTimestamp).to.be.eq(onchainData.lastRewardTimestamp);
};

let unitroller: Comptroller;
let oracle: AuriOracle;
let fairLaunch: AuriFairLaunch;
let auUSDC: AuErc20;
let auETH: AuETH;
let aurora: ERC20PresetFixedSupply;
let ply: Ply;
let tokenLock: TokenLock;
let lens: AuriLens;

ethers.utils.Logger.setLogLevel(ethers.utils.Logger.levels.ERROR); // turn off warnings

describe('Tests', () => {
  beforeEach('load fixture', async () => {
    ({unitroller, oracle, fairLaunch, auUSDC, auETH, aurora, ply, tokenLock, lens} = await loadFixture(fixture));
    await oracle.connect(admin).setPriceValidity(INF); // price is always valid
  });

  describe('test permissions', async () => {
    const newRewardClaimStart = config.REWARD_CLAIM_START.add(1);
    it('should revert if caller is not admin', async () => {
      await expect(unitroller.setTokens(lender.address, auUSDC.address)).to.be.reverted;
      await expect(unitroller.setLockAddress(lender.address)).to.be.reverted;
      await expect(unitroller.setRewardClaimStart(newRewardClaimStart)).to.be.reverted;
    });

    it('should set relevant variables if caller is admin', async () => {
      await unitroller.connect(admin).setTokens(lender.address, auUSDC.address);
      expect(await unitroller.ply()).to.be.eq(lender.address);
      expect(await unitroller.aurora()).to.be.eq(auUSDC.address);

      await unitroller.connect(admin).setLockAddress(lender.address);
      expect(await unitroller.tokenLock()).to.be.eq(lender.address);

      await unitroller.connect(admin).setRewardClaimStart(newRewardClaimStart);
      expect(await unitroller.rewardClaimStart()).to.be.eq(newRewardClaimStart);
    });
  });

  describe('test Ply token', async () => {
    const newPlyAmount = ONE_E_18.mul(123);
    it('initialisation: set correct values', async () => {
      expect(await ply.governance()).to.be.eq(admin.address);
      expect(await ply.pendingGovernance()).to.be.eq(ZERO_ADDRESS);
      expect(await ply.totalSupply()).to.be.eq(ONE_E_18.mul(1e10));
    });

    it('transferGovernance: revert if caller is not admin', async () => {
      await expect(ply.connect(lender).transferGovernance(lender.address)).to.be.reverted;
    });

    it('transferGovernance: successful if caller is admin', async () => {
      await ply.connect(admin).transferGovernance(lender.address);
      expect(await ply.pendingGovernance()).to.be.eq(lender.address);
      expect(await ply.governance()).to.be.eq(admin.address);
    });

    it('claimGovernance: revert if not from new governance', async () => {
      await ply.connect(admin).transferGovernance(lender.address);
      await expect(ply.connect(admin).claimGovernance()).to.be.reverted;
    });

    it('claimGovernance: successful if caller is new governance', async () => {
      await ply.connect(admin).transferGovernance(lender.address);
      await ply.connect(lender).claimGovernance();
      expect(await ply.pendingGovernance()).to.be.eq(ZERO_ADDRESS);
      expect(await ply.governance()).to.be.eq(lender.address);
    });

    it('mintPly: cannot mint Ply before 1 year', async () => {
      await expect(ply.connect(admin).mintPly(admin.address, newPlyAmount)).to.be.reverted;
    });

    it('mintPly: can mint Ply after 1 year', async () => {
      await advanceTime(BN.from(365 * 24 * 3600));
      await ply.connect(lender).delegate(admin.address);

      const voteBefore = await ply.getCurrentVotes(admin.address);

      await ply.connect(admin).mintPly(lender.address, newPlyAmount);
      expect(await ply.balanceOf(lender.address)).to.be.eq(newPlyAmount);
      expect(await ply.totalSupply()).to.be.eq(ONE_E_18.mul(1e10).add(newPlyAmount));

      // Vote of delegate of user (which is admin) should increase by the amount minted
      const voteAfter = await ply.getCurrentVotes(admin.address);
      expect(voteAfter).to.be.eq(voteBefore.add(newPlyAmount));
    });

    it('mintPly: cant mint Ply after 1 year from non-admin', async () => {
      await advanceTime(BN.from(365 * 24 * 3600));
      await expect(ply.connect(lender).mintPly(lender.address, newPlyAmount)).to.be.reverted;
    });
  });

  describe('test lending, borrowing, reward locking and claiming', async () => {
    it('USDC lending: should have rewards accruing', async () => {
      await auUSDC.connect(lender).mint(PRECISION.mul(10_000));
      await unitroller.connect(lender).enterMarkets([auUSDC.address]);
      await advanceTime(ONE_DAY);
      await unitroller.connect(admin).mintAllowed(auUSDC.address, lender.address, 0);
      expect(await unitroller.rewardAccrued(0, lender.address)).to.be.gt(ZERO);
    });

    it('ETH lending: should have rewards accruing', async () => {
      await auETH.connect(lender).mint({value: PRECISION});
      await unitroller.connect(lender).enterMarkets([auETH.address]);
      await advanceTime(ONE_DAY);
      await unitroller.connect(admin).mintAllowed(auETH.address, lender.address, 0);
      expect(await unitroller.rewardAccrued(0, lender.address)).to.be.gt(ZERO);
    });

    it('borrowing: should have rewards accruing', async () => {
      await auUSDC.connect(lender).mint(PRECISION.mul(5000));
      await auETH.connect(borrower).mint({value: PRECISION});
      await unitroller.connect(borrower).enterMarkets([auETH.address]);
      await auUSDC.connect(borrower).borrow(PRECISION);
      await advanceTime(ONE_DAY);
      await unitroller.connect(admin).borrowAllowed(auUSDC.address, borrower.address, 0);
      expect(await unitroller.rewardAccrued(0, borrower.address)).to.be.gt(ZERO);
    });

    describe('reward locks and claims', async () => {
      beforeEach('generate rewards for lender and borrower', async () => {
        await auETH.connect(lender).mint({value: PRECISION.mul(10)});
        await auUSDC.connect(lender).mint(PRECISION.mul(5000));
        await auETH.connect(borrower).mint({value: PRECISION});
        await unitroller.connect(borrower).enterMarkets([auETH.address]);
        await auUSDC.connect(borrower).borrow(PRECISION);
        await advanceTime(ONE_DAY);
      });

      // it('should correctly generate rewardsMetadata before claimStart', async () => {
      //   let lenderPlyBalBefore = await ply.balanceOf(lender.address);
      //   let lenderAuroraBalBefore = await aurora.balanceOf(lender.address);

      //   let result = await lens.connect(lender).callStatic.claimAndGetRewardBalancesMetadata(
      //     unitroller.address,
      //     fairLaunch.address,
      //     []
      //   );

      //   expect(result.plyAccrued).to.be.gt(ZERO);
      //   expect(result.auroraAccrued).to.be.gt(ZERO);
      //   expect(result.plyBalance).to.be.eq(lenderPlyBalBefore);
      //   expect(result.auroraBalance).to.be.eq(lenderAuroraBalBefore);
      // });

      it('claimReward: should store values in rewardAccrued (no transfers) before claimStart via lens', async () => {
        let lenderPlyBalBefore = await ply.balanceOf(lender.address);
        let borrowerPlyBalBefore = await ply.balanceOf(borrower.address);
        let lenderAuroraBalBefore = await aurora.balanceOf(lender.address);
        let borrowerAuroraBalBefore = await aurora.balanceOf(borrower.address);

        await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, []);
        await lens.connect(borrower).claimRewards(unitroller.address, fairLaunch.address, []);

        expect(await ply.balanceOf(lender.address)).to.be.eq(lenderPlyBalBefore);
        expect(await ply.balanceOf(borrower.address)).to.be.eq(borrowerPlyBalBefore);
        expect(await aurora.balanceOf(lender.address)).to.be.eq(lenderAuroraBalBefore);
        expect(await aurora.balanceOf(borrower.address)).to.be.eq(borrowerAuroraBalBefore);
        expect(await unitroller.rewardAccrued(0, lender.address)).to.be.gt(ZERO);
        expect(await unitroller.rewardAccrued(0, borrower.address)).to.be.gt(ZERO);
        expect(await unitroller.rewardAccrued(1, lender.address)).to.be.gt(ZERO);
        expect(await unitroller.rewardAccrued(1, borrower.address)).to.be.gt(ZERO);
      });

      it('should transfer / lock rewards', async () => {
        await setNextBlockTimeStamp(rewardClaimStart);
        let lenderPlyBalBefore = await ply.balanceOf(lender.address);
        let lenderAuroraBalBefore = await aurora.balanceOf(lender.address);
        await unitroller.connect(lender)['claimReward(uint8,address)'](0, lender.address);
        await unitroller.connect(lender)['claimReward(uint8,address)'](1, lender.address);
        expect(await ply.balanceOf(lender.address)).to.be.gt(lenderPlyBalBefore);
        expect(await aurora.balanceOf(lender.address)).to.be.gt(lenderAuroraBalBefore);
      });

      it('should be able to claim directly from unitroller if msg.sender is claimee', async () => {
        await setNextBlockTimeStamp(rewardClaimStart);
        let lenderPlyBalBefore = await ply.balanceOf(lender.address);
        let lenderAuroraBalBefore = await aurora.balanceOf(lender.address);
        await unitroller.connect(lender)['claimReward(uint8,address)'](0, lender.address);
        await unitroller.connect(lender)['claimReward(uint8,address)'](1, lender.address);
        expect(await ply.balanceOf(lender.address)).to.be.gt(lenderPlyBalBefore);
        expect(await aurora.balanceOf(lender.address)).to.be.gt(lenderAuroraBalBefore);
      });

      it('should revert if trying to claim rewards via lens without prior approval', async () => {
        await setNextBlockTimeStamp(rewardClaimStart);
        await unitroller.connect(admin).setWhitelisted(lens.address, false);
        await expect(lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, [])).to.be.revertedWith(
          'not approved'
        );
      });

      it('should be able to claim rewards via lens after giving approval', async () => {
        await setNextBlockTimeStamp(rewardClaimStart);
        await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, []);
      });

      // it('should be able to claim rewards via lens without giving approval but whitelistAll set to true', async () => {
      //   await setNextBlockTimeStamp(rewardClaimStart);
      //   await unitroller.connect(admin).setWhitelistAll(true);
      //   await unitroller.connect(admin).setWhitelisted(lens.address, false);
      //   await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, []);
      // });

      it('claimReward: should have some rewards sent to users after reward claim starts', async () => {
        await setNextBlockTimeStamp(rewardClaimStart);
        let lenderPlyBalBefore = await ply.balanceOf(lender.address);
        let borrowerPlyBalBefore = await ply.balanceOf(borrower.address);
        let lenderAuroraBalBefore = await aurora.balanceOf(lender.address);
        let borrowerAuroraBalBefore = await aurora.balanceOf(borrower.address);

        await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, []);

        await lens.connect(borrower).claimRewards(unitroller.address, fairLaunch.address, []);

        expect(await ply.balanceOf(lender.address)).to.be.gt(lenderPlyBalBefore);
        expect(await ply.balanceOf(borrower.address)).to.be.gt(borrowerPlyBalBefore);
        expect(await aurora.balanceOf(lender.address)).to.be.gt(lenderAuroraBalBefore);
        expect(await aurora.balanceOf(borrower.address)).to.be.gt(borrowerAuroraBalBefore);
      });

      it('claimReward: should not claim comp approved rewards if caller is not given approval by claimee', async () => {
        await setNextBlockTimeStamp(rewardClaimStart);

        // no change expected
        let lenderPlyBalBefore = await ply.balanceOf(lender.address);
        let lenderAuroraBalBefore = await aurora.balanceOf(lender.address);
        await lens.connect(borrower).claimRewards(unitroller.address, fairLaunch.address, []);
        expect(await ply.balanceOf(lender.address)).to.be.eq(lenderPlyBalBefore);
        expect(await aurora.balanceOf(lender.address)).to.be.eq(lenderAuroraBalBefore);
      });

      it('claimReward: should have locked up PLY tokens after reward claim starts', async () => {
        await setNextBlockTimeStamp(rewardClaimStart);
        let lenderLockAmtBefore = await tokenLock.lockedAmounts(lender.address);
        let borrowerLockAmtBefore = await tokenLock.lockedAmounts(borrower.address);

        await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, []);

        await lens.connect(borrower).claimRewards(unitroller.address, fairLaunch.address, []);

        expect(await tokenLock.lockedAmounts(lender.address)).to.be.gt(lenderLockAmtBefore);
        expect(await tokenLock.lockedAmounts(borrower.address)).to.be.gt(borrowerLockAmtBefore);
      });

      it('claimReward: should lock up and release according to percentage set in tokenLock', async () => {
        // move to week 22
        await moveToTimestamp(rewardClaimStart + 22 * 7 * 24 * 3600);
        let lenderLockAmtBefore = await tokenLock.lockedAmounts(lender.address);
        let lenderPlyBalBefore = await ply.balanceOf(lender.address);

        await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, []);

        // lock = 51%, claim = 49%
        let lenderLockAmt = (await tokenLock.lockedAmounts(lender.address)).sub(lenderLockAmtBefore);
        let lenderClaimAmt = (await ply.balanceOf(lender.address)).sub(lenderPlyBalBefore);
        let lockPercentage = lenderLockAmt.mul(10_000).div(lenderLockAmt.add(lenderClaimAmt));
        let claimPercentage = lenderClaimAmt.mul(10_000).div(lenderLockAmt.add(lenderClaimAmt));
        // within a buffer
        expect(lockPercentage).to.be.gte(5099);
        expect(lockPercentage).to.be.lte(5100);
        expect(claimPercentage).to.be.gte(4900);
        expect(claimPercentage).to.be.lte(4901);
      });

      it('claimReward: should not lock up any tokens once unlock starts', async () => {
        let result = await tokenLock.calcUnlockTimes(lender.address);
        await setNextBlockTimeStamp(result.unlockEnd.toNumber());
        let lenderLockAmtBefore = await tokenLock.lockedAmounts(lender.address);
        let lenderPlyBalBefore = await ply.balanceOf(lender.address);

        await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, []);

        expect(await tokenLock.lockedAmounts(lender.address)).to.be.eq(lenderLockAmtBefore);
        expect(await ply.balanceOf(lender.address)).to.be.gt(lenderPlyBalBefore);
      });
    });
  });

  describe('TokenLock', async () => {
    describe('instantiation', async () => {
      it('should revert if ctor args are null', async () => {
        let Factory = (await ethers.getContractFactory('TokenLock')) as TokenLock__factory;
        await expect(Factory.connect(admin).deploy(ZERO_ADDRESS, unitroller.address)).to.be.revertedWith(
          'null address'
        );
        await expect(Factory.connect(admin).deploy(ply.address, ZERO_ADDRESS)).to.be.revertedWith('null address');
      });

      it('should have correctly instantiated the contract', async () => {
        expect(await tokenLock.token()).to.be.eq(ply.address);
        expect(await tokenLock.rewardToken()).to.be.eq(ply.address);
        expect(await tokenLock.unitroller()).to.be.eq(unitroller.address);
        for (let i = 0; i < 48; i++) {
          expect(await tokenLock.percentageLock(i)).to.be.eq(9500 - i * 200);
        }
        expect(await tokenLock.percentageLock(48)).to.be.eq(ZERO);
      });
    });

    describe('setPercentageLock', async () => {
      it('should not have unauthorized parties', async () => {
        await expect(tokenLock.connect(lender).setPercentageLock([1], [50])).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );
      });

      it('should revert for unequal weekNumbers and values lengths', async () => {
        await expect(tokenLock.connect(admin).setPercentageLock([1], [50, 100])).to.be.revertedWith(
          'bad array lengths'
        );
        await expect(tokenLock.connect(admin).setPercentageLock([1, 3], [50])).to.be.revertedWith('bad array lengths');
      });

      it('should have percentages <= 10_000', async () => {
        await expect(tokenLock.connect(admin).setPercentageLock([1], [10_001])).to.be.revertedWith('exceed max value');
        await expect(tokenLock.connect(admin).setPercentageLock([1, 2], [0, 10_001])).to.be.revertedWith(
          'exceed max value'
        );
        await expect(tokenLock.connect(admin).setPercentageLock([1, 2], [10_001, 0])).to.be.revertedWith(
          'exceed max value'
        );
      });

      it('should allow setting max value of 10_000', async () => {
        await tokenLock.connect(admin).setPercentageLock([1], [10_000]);
        expect(await tokenLock.percentageLock(1)).to.be.eq(10_000);
      });

      it('should have correctly set percentages', async () => {
        let weekNumbers = [1, 2, 3, 4, 5];
        let values = [10_000, 9000, 8000, 7000, 6000];
        await tokenLock.connect(admin).setPercentageLock(weekNumbers, values);
        for (let i = 0; i < 5; i++) {
          expect(await tokenLock.percentageLock(weekNumbers[i])).to.be.eq(values[i]);
        }
      });
    });

    describe('setEarlierUnlockStart', async () => {
      it('should not have unauthorized parties', async () => {
        await expect(tokenLock.connect(lender).setEarlierUnlockStart(lender.address, 1)).to.be.revertedWith(
          'Ownable: caller is not the owner'
        );
      });

      it('should revert if specified timestamp is equal / later to user unlockStart', async () => {
        let result = await tokenLock.calcUnlockTimes(lender.address);

        await expect(
          tokenLock.connect(admin).setEarlierUnlockStart(lender.address, result.unlockEnd)
        ).to.be.revertedWith('timestamp >= user unlockBegin');

        await expect(
          tokenLock.connect(admin).setEarlierUnlockStart(lender.address, result.unlockBegin)
        ).to.be.revertedWith('timestamp >= user unlockBegin');
      });

      it('should have set earlier unlockStart', async () => {
        await tokenLock.connect(admin).setEarlierUnlockStart(lender.address, 1);
        expect(await tokenLock.unlockStartOverrides(lender.address)).to.be.eq(1);
        let result = await tokenLock.calcUnlockTimes(lender.address);
        expect(result.unlockBegin).to.be.eq(1);
        expect(result.unlockEnd).to.be.eq(ONE_YEAR.add(1));
      });
    });

    describe('calcUnlockTimes', async () => {
      it('should use default values if not overriden', async () => {
        let result = await tokenLock.calcUnlockTimes(lender.address);
        let unlockBegin = ONE_DAY.mul(7 * 49).add(rewardClaimStart);
        expect(result.unlockBegin).to.be.eq(unlockBegin);
        expect(result.unlockEnd).to.be.eq(ONE_YEAR.add(unlockBegin));
      });

      // overriden value tested in setEarlierUnlockStart
    });

    describe('calcLockAmount', async () => {
      it('should return full lock amount before rewardClaimStart', async () => {
        let result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(PRECISION);
        expect(result.claimAmount).to.be.eq(ZERO);

        await setNextBlockTimeStamp(rewardClaimStart - 1);
        result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(PRECISION);
        expect(result.claimAmount).to.be.eq(ZERO);
      });

      it('should return full lock amount before rewardClaimStart after unitroller update', async () => {
        let result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(PRECISION);
        expect(result.claimAmount).to.be.eq(ZERO);

        let newRewardClaimStart = BN.from(rewardClaimStart).sub(ONE_DAY.mul(7));
        await unitroller.connect(admin).setRewardClaimStart(newRewardClaimStart);
        await setNextBlockTimeStamp(rewardClaimStart - 1);
        result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(PRECISION);
        expect(result.claimAmount).to.be.eq(ZERO);
      });

      it('should return full unlock amount after default unlockBegin and unlockEnd', async () => {
        let unlockTimes = await tokenLock.calcUnlockTimes(lender.address);
        await moveToTimestamp(unlockTimes.unlockBegin.toNumber());
        let result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(ZERO);
        expect(result.claimAmount).to.be.eq(PRECISION);

        await moveToTimestamp(unlockTimes.unlockEnd.toNumber());
        result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(ZERO);
        expect(result.claimAmount).to.be.eq(PRECISION);
      });

      it('prevents premature unlocking before rewardClaimStart despite overriding unlock time', async () => {
        let newUnlockTime = rewardClaimStart - 86400;
        await setNextBlockTimeStamp(newUnlockTime);
        await tokenLock.connect(admin).setEarlierUnlockStart(lender.address, newUnlockTime);
        let result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(PRECISION);
        expect(result.claimAmount).to.be.eq(ZERO);
      });

      it('should return full unlock amount after overriden unlockEnd', async () => {
        let newUnlockTime = rewardClaimStart;
        await setNextBlockTimeStamp(newUnlockTime);
        await tokenLock.connect(admin).setEarlierUnlockStart(lender.address, newUnlockTime);
        let result = await tokenLock.calcLockAmount(lender.address, PRECISION);
        expect(result.lockAmount).to.be.eq(ZERO);
        expect(result.claimAmount).to.be.eq(PRECISION);

        // move to week 22
        // lock = 51%, claim = 49%
        newUnlockTime = rewardClaimStart + 22 * 7 * 24 * 3600;
        await moveToTimestamp(newUnlockTime);
        result = await tokenLock.calcLockAmount(borrower.address, PRECISION);
        expect(result.lockAmount).to.be.eq(PRECISION.mul(51).div(100));
        expect(result.claimAmount).to.be.eq(PRECISION.mul(49).div(100));

        // shift unlock start time earlier
        await setNextBlockTimeStamp(newUnlockTime + 100);
        await tokenLock.connect(admin).setEarlierUnlockStart(borrower.address, newUnlockTime);
        result = await tokenLock.calcLockAmount(borrower.address, PRECISION);
        expect(result.lockAmount).to.be.eq(ZERO);
        expect(result.claimAmount).to.be.eq(PRECISION);
      });

      it('should return same lock and claim amounts while timestamp < unlockBegin', async () => {
        // shift borrower unlock time earlier by 24 weeks
        let newUnlockTime = (await tokenLock.calcUnlockTimes(borrower.address)).unlockBegin
          .sub(ONE_WEEK.mul(24))
          .toNumber();
        await tokenLock.connect(admin).setEarlierUnlockStart(borrower.address, newUnlockTime);
        // move to rewardClaimStart
        newUnlockTime = rewardClaimStart;
        await moveToTimestamp(newUnlockTime);
        for (let i = 1; i < 26; i++) {
          let defaultAmts = await tokenLock.calcLockAmount(lender.address, PRECISION);
          let overridenAmts = await tokenLock.calcLockAmount(borrower.address, PRECISION);
          expect(defaultAmts.lockAmount).to.be.eq(overridenAmts.lockAmount);
          expect(defaultAmts.claimAmount).to.be.eq(overridenAmts.claimAmount);
          newUnlockTime = ONE_WEEK.toNumber() + newUnlockTime;
          await moveToTimestamp(newUnlockTime);
        }
        // time == unlockBegin, hence full unlock for overriden amounts
        let defaultAmts = await tokenLock.calcLockAmount(lender.address, PRECISION);
        let overridenAmts = await tokenLock.calcLockAmount(borrower.address, PRECISION);
        expect(defaultAmts.lockAmount).to.be.gt(ZERO);
        expect(defaultAmts.claimAmount).to.be.lt(PRECISION);
        expect(overridenAmts.lockAmount).to.be.eq(ZERO);
        expect(overridenAmts.claimAmount).to.be.eq(PRECISION);
      });
    });

    describe('claimableBalance', async () => {});

    describe('lock', async () => {});

    describe('claim', async () => {});
  });

  describe('FairLaunch', async () => {
    it('should have correctly instantiated the contracts', async () => {
      expect(await fairLaunch.owner()).to.be.eq(admin.address);
      expect(await fairLaunch.rewardToken()).to.be.eq(ply.address);
      expect(await ply.allowance(fairLaunch.address, tokenLock.address)).to.be.eq(MAX_UINT_96);
    });

    it('should have only admin add pool', async () => {
      await expect(
        fairLaunch.connect(lender).addPool(aurora.address, startTime, endTime, rewardPerSecond)
      ).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should revert if stake token is null', async () => {
      await expect(
        fairLaunch.connect(admin).addPool(ZERO_ADDRESS, startTime, endTime, rewardPerSecond)
      ).to.be.revertedWith('add: invalid stake token');
    });

    it('should revert for invalid times', async () => {
      await setNextBlockTimeStamp(endTime);
      await expect(
        fairLaunch.connect(admin).addPool(aurora.address, startTime, endTime, rewardPerSecond)
      ).to.be.revertedWith('add: invalid times');

      await expect(
        fairLaunch.connect(admin).addPool(aurora.address, endTime + 100, endTime + 50, rewardPerSecond)
      ).to.be.revertedWith('add: invalid times');
    });

    it('should successfully create pool', async () => {
      await fairLaunch.connect(admin).addPool(aurora.address, startTime, endTime, rewardPerSecond);
      await verifyPoolInfo({
        id: 0,
        stakeToken: aurora.address,
        startTime: startTime,
        endTime: endTime,
        rewardPerSecond: rewardPerSecond,
        lastRewardTimestamp: startTime,
        accRewardPerShare: ZERO,
        totalStake: ZERO,
      });
    });

    describe('test claiming rewards', async () => {
      beforeEach('create pool, get lender to give allowance', async () => {
        await fairLaunch.connect(admin).addPool(aurora.address, startTime, endTime, rewardPerSecond);
        await aurora.connect(lender).approve(fairLaunch.address, MAX_UINT);
      });

      it('should revert deposit if no allowance given', async () => {
        await expect(fairLaunch.connect(borrower).deposit(0, ONE)).to.be.revertedWith('ERC20: insufficient allowance');
      });

      it('should have lender deposit into pool', async () => {
        await expect(() => fairLaunch.connect(lender).deposit(0, PRECISION)).to.changeTokenBalances(
          aurora,
          [fairLaunch, lender],
          [PRECISION, PRECISION.mul(-1)]
        );
        await verifyPoolInfo({
          id: 0,
          stakeToken: aurora.address,
          startTime: startTime,
          endTime: endTime,
          rewardPerSecond: rewardPerSecond,
          lastRewardTimestamp: startTime,
          accRewardPerShare: ZERO,
          totalStake: PRECISION,
        });
      });

      it('should have lender be able to withdraw from pool before rewards accrue', async () => {
        await fairLaunch.connect(lender).deposit(0, PRECISION);
        await fairLaunch.connect(lender).withdraw(0, PRECISION);
        await verifyPoolInfo({
          id: 0,
          stakeToken: aurora.address,
          startTime: startTime,
          endTime: endTime,
          rewardPerSecond: rewardPerSecond,
          lastRewardTimestamp: startTime,
          accRewardPerShare: ZERO,
          totalStake: ZERO,
        });
      });

      describe('user deposits some aurora into pool', async () => {
        beforeEach('have user deposit some aurora into pool', async () => {
          // no harvest
          await fairLaunch.connect(lender).deposit(0, PRECISION);
        });

        it('should start accuring rewards', async () => {
          await moveToTimestamp(rewardClaimStart + ONE_DAY.toNumber());
          expect(await fairLaunch.pendingRewards(0, lender.address)).to.be.gt(ZERO);
        });

        it('should be able to lock up rewards', async () => {
          await setNextBlockTimeStamp(rewardClaimStart + ONE_DAY.toNumber());
          let tokensLockedBefore = await tokenLock.lockedAmounts(lender.address);
          await fairLaunch.connect(lender).harvest(lender.address, 0, INF);
          expect(await tokenLock.lockedAmounts(lender.address)).to.be.gt(tokensLockedBefore);
        });

        it('should not allow unauthorized people to harvest rewards', async () => {
          await setNextBlockTimeStamp(rewardClaimStart + ONE_DAY.toNumber());
          await unitroller.connect(admin).setWhitelisted(lens.address, false);
          await expect(fairLaunch.connect(borrower).harvest(lender.address, 0, INF)).to.be.revertedWith(
            'not approved'
          );
          // lens not given approval yet
          await expect(
            lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, [0])
          ).to.be.revertedWith('not approved');
        });

        it('should not claim rewards via lens if caller is not given approval', async () => {
          await moveToTimestamp(rewardClaimStart + ONE_DAY.toNumber());
          let pendingRewards = await fairLaunch.pendingRewards(0, lender.address);
          await lens.connect(borrower).claimRewards(unitroller.address, fairLaunch.address, [0]);
          expect(await fairLaunch.pendingRewards(0, lender.address)).to.be.gte(pendingRewards);
        });

        it('should allow claimer to harvest directly for user after approval is given', async () => {
          await moveToTimestamp(rewardClaimStart + ONE_DAY.toNumber());
          await unitroller.connect(admin).setWhitelisted(borrower.address, true);
          expect(await fairLaunch.pendingRewards(0, lender.address)).to.be.gt(ZERO);
          await fairLaunch.connect(borrower).harvest(lender.address, 0, INF);
          expect(await fairLaunch.pendingRewards(0, lender.address)).to.be.eq(ZERO);
        });

        it('should claim and lock rewards via lens after approval to lens', async () => {
          // lender directly claim via lens
          await moveToTimestamp(rewardClaimStart + ONE_DAY.toNumber());
          let tokensLockedBefore = await tokenLock.lockedAmounts(lender.address);
          await lens.connect(lender).claimRewards(unitroller.address, fairLaunch.address, [0]);
          expect(await tokenLock.lockedAmounts(lender.address)).to.be.gt(tokensLockedBefore);
        });

        it('should have sent and locked up amounts equal to default locking schedule', async () => {
          // move to week 22
          await moveToTimestamp(rewardClaimStart + ONE_WEEK.mul(22).toNumber());
          let tokensLockedBefore = await tokenLock.lockedAmounts(lender.address);
          let plyTokenBal = await ply.balanceOf(lender.address);

          await fairLaunch.connect(lender).harvest(lender.address, 0, INF);

          let lenderLockAmt = (await tokenLock.lockedAmounts(lender.address)).sub(tokensLockedBefore);
          let lenderClaimAmt = (await ply.balanceOf(lender.address)).sub(plyTokenBal);
          let lockPercentage = lenderLockAmt.mul(10_000).div(lenderLockAmt.add(lenderClaimAmt));
          let claimPercentage = lenderClaimAmt.mul(10_000).div(lenderLockAmt.add(lenderClaimAmt));
          // lock = 51%, claim = 49%
          // within a buffer
          expect(lockPercentage).to.be.gte(5099);
          expect(lockPercentage).to.be.lte(5100);
          expect(claimPercentage).to.be.gte(4900);
          expect(claimPercentage).to.be.lte(4901);
        });

        it('should have sent and locked up amounts equal to overriden locking schedule', async () => {
          // set unlockBegin to be slightly earlier but after week 22
          let unlockTime = rewardClaimStart + ONE_WEEK.mul(23).toNumber();
          await tokenLock.connect(admin).setEarlierUnlockStart(lender.address, unlockTime);

          // move to week 22
          // since timestamp < unlockBegin, lock and claim amts should be the same as default schedule
          await moveToTimestamp(rewardClaimStart + ONE_WEEK.mul(22).toNumber());
          let tokensLockedBefore = await tokenLock.lockedAmounts(lender.address);
          let plyTokenBal = await ply.balanceOf(lender.address);

          await fairLaunch.connect(lender).harvest(lender.address, 0, INF);

          let lenderLockAmt = (await tokenLock.lockedAmounts(lender.address)).sub(tokensLockedBefore);
          let lenderClaimAmt = (await ply.balanceOf(lender.address)).sub(plyTokenBal);
          let lockPercentage = lenderLockAmt.mul(10_000).div(lenderLockAmt.add(lenderClaimAmt));
          let claimPercentage = lenderClaimAmt.mul(10_000).div(lenderLockAmt.add(lenderClaimAmt));
          // lock = 51%, claim = 49%
          // within a buffer
          expect(lockPercentage).to.be.gte(5099);
          expect(lockPercentage).to.be.lte(5100);
          expect(claimPercentage).to.be.gte(4900);
          expect(claimPercentage).to.be.lte(4901);

          tokensLockedBefore = await tokenLock.lockedAmounts(lender.address);
          plyTokenBal = await ply.balanceOf(lender.address);

          // now shift to unlock time
          await setNextBlockTimeStamp(unlockTime);
          await fairLaunch.connect(lender).harvest(lender.address, 0, INF);

          // should have been fully sent to lender
          lenderLockAmt = (await tokenLock.lockedAmounts(lender.address)).sub(tokensLockedBefore);
          lenderClaimAmt = (await ply.balanceOf(lender.address)).sub(plyTokenBal);
          expect(lenderLockAmt).to.be.eq(ZERO);
          expect(lenderClaimAmt).to.be.gt(ZERO);
        });

        it('should allow user to withdraw his deposit at any time', async () => {
          await moveToTimestamp(rewardClaimStart);
          await fairLaunch.connect(lender).withdrawAll(0);
          await fairLaunch.connect(lender).deposit(0, PRECISION);

          await moveToTimestamp(rewardClaimStart + ONE_WEEK.mul(22).toNumber());
          await fairLaunch.connect(lender).withdrawAll(0);
          await fairLaunch.connect(lender).deposit(0, PRECISION);

          let unlockTimes = await tokenLock.calcUnlockTimes(lender.address);
          await moveToTimestamp(unlockTimes.unlockBegin.toNumber());
          await fairLaunch.connect(lender).withdrawAll(0);
          await fairLaunch.connect(lender).deposit(0, PRECISION);

          await moveToTimestamp(unlockTimes.unlockEnd.toNumber());
          await fairLaunch.connect(lender).withdrawAll(0);
        });
      });
    });
  });
});
