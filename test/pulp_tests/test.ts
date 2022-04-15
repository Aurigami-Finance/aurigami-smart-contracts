import { waffle } from "hardhat";
import { evm_revert, evm_snapshot, moveToTimestamp } from "../hardhat-helpers";
import { loadFixture } from "ethereum-waffle";
import { INF, ONE_WEEK } from "../Constants";
import { expect } from "chai";
import { pulpFixture, T0 } from "./fixture";
import { Comptroller, Ply, PULP } from "../../typechain";
import { BigNumber as BN } from "@ethersproject/bignumber/lib/bignumber";
import { BigNumberish, Wallet } from "ethers";
import { toWei } from "../onchain_tests/helpers";

describe("PULP test", () => {
  const [admin, bob, charlie, dave, eve] = waffle.provider.getWallets();
  let globalSnapshotId;
  let snapshotId;
  let comptroller: Comptroller;
  let ply: Ply;
  let pulp: PULP;
  before(async () => {
    globalSnapshotId = await evm_snapshot();
    ({
      comptroller, ply, pulp
    }
      = await loadFixture(pulpFixture));
    await ply.connect(admin).approve(pulp.address, INF);
    snapshotId = await evm_snapshot();
  });

  async function revertSnapshot() {
    await evm_revert(snapshotId);
    snapshotId = await evm_snapshot();
  }

  beforeEach(async () => {
    await revertSnapshot();
  });

  async function verifyLockAmount(expectedPercent: BigNumberish, user?: Wallet) {
    if (user == null) user = admin;
    let lockAmount = await pulp.calcLockAmount(user.address, 10000);
    expect(lockAmount.lockAmount).eq(expectedPercent);
  }

  it("follows the unlock schedule", async () => {
    await verifyLockAmount(10000);
    for (let i = 0; i < 49; i++) {
      await moveToTimestamp(T0.add(ONE_WEEK.mul(i)).add(1));
      let expected = BN.from(10_000 - (5 + i * 2) * 100);
      if (expected.lt(0)) expected = BN.from(0);
      await verifyLockAmount(expected);
    }
  });

  it("allows the lock of ply to pulp", async () => {
    const plyLock = toWei(1000, 18);
    const prePlyBalance = await ply.balanceOf(admin.address);
    await pulp.lockPly(bob.address, plyLock);
    await expect(await pulp.balanceOf(bob.address)).eq(plyLock);
    await expect(await ply.balanceOf(admin.address)).eq(prePlyBalance.sub(plyLock));
  });

  it("still follows the unlock schedule after setting global lock", async () => {
    await pulp.setGlobalLock([0, 1, 2], [0, 1, 2]);
    for (let i = 0; i < 3; i++) {
      await moveToTimestamp(T0.add(ONE_WEEK.mul(i)).add(1));
      await verifyLockAmount(i);
    }
  });

  it("still follows the unlock schedule after setting user lock", async () => {
    await pulp.setUserLock(bob.address, [0, 1, 2], [0, 1, 2]);
    for (let i = 0; i < 3; i++) {
      await moveToTimestamp(T0.add(ONE_WEEK.mul(i)).add(1));
      await verifyLockAmount(i, bob);
    }
  });

  it("redeems fully after the FIRST_REDEEM_WEEK", async () => {
    const plyLock = toWei(1000, 18);
    await pulp.lockPly(bob.address, plyLock);

    await moveToTimestamp(T0.add(ONE_WEEK.mul(await pulp.PULP_FIRST_REDEEM_WEEK())));

    await pulp.connect(bob).redeem(bob.address, INF);
    await expect((await ply.balanceOf(bob.address))).eq(plyLock);
  });

  it("does not allow redemption of PULP before rewardClaimStart even when earlyRedeem is set", async () => {
    const plyLock = toWei(1000, 18);
    await pulp.lockPly(bob.address, plyLock);
    await pulp.addEarlyRedeems([bob.address],[INF]);

    await expect(pulp.connect(bob).redeem(bob.address, INF)).to.revertedWith("wait until rewardClaimStart");
  });

  it("allows redemption of PULP early if earlyRedeem is set", async () => {
    const plyLock = toWei(1000, 18);
    await pulp.lockPly(bob.address, plyLock);

    await moveToTimestamp(T0);

    await pulp.addEarlyRedeems([bob.address],[plyLock.div(2)]);
    await pulp.connect(bob).redeem(bob.address, INF);
    await expect((await ply.balanceOf(bob.address))).eq(plyLock.div(2));
  });

  it("reverts if the amount of PULP redeems is more than the earlyRedeem", async () => {
    const plyLock = toWei(1000, 18);
    await pulp.lockPly(bob.address, plyLock);

    await moveToTimestamp(T0);

    await pulp.addEarlyRedeems([bob.address],[plyLock.div(2)]);
    await expect(pulp.connect(bob).redeem(bob.address, plyLock)).to.be.revertedWith("insufficient earlyRedeems");
  });

  it("reset earlyRdeems works fine", async () => {
    await pulp.resetEarlyRedeems([bob.address],[1]);
    expect(await pulp.earlyRedeems(bob.address)).eq(1);
  });
});
