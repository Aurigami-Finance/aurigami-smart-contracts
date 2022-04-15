import { waffle, ethers } from "hardhat";
import { evm_revert, evm_snapshot, moveToTimestamp } from "../hardhat-helpers";
import { loadFixture } from "ethereum-waffle";
import { INF, ONE_WEEK } from "../Constants";
import { expect } from "chai";
import { airdropFixture, getContractAt } from "./fixture";
import { AuriAirdrop, AuriAirdropMock, Ply } from "../../typechain";
import { BigNumber as BN } from "@ethersproject/bignumber/lib/bignumber";
import { BigNumberish, Wallet } from "ethers";
import { getContract, toWei } from "../onchain_tests/helpers";
import { utils } from "ethers";

describe("Airdrop test", () => {
  const [admin, bob, charlie, dave, eve] = waffle.provider.getWallets();
  let globalSnapshotId;
  let snapshotId;
  let ply: Ply;
  let auriAirdrop: AuriAirdrop;
  let auriAirdropImpl: AuriAirdrop;
  const ID = utils.formatBytes32String("testing");
  const _100PLY = BN.from(10).pow(18).mul(100);

  before(async () => {
    globalSnapshotId = await evm_snapshot();
    ({
      ply, auriAirdrop, auriAirdropImpl
    }
      = await loadFixture(airdropFixture));
    await ply.connect(admin).approve(auriAirdrop.address, INF);
    snapshotId = await evm_snapshot();
  });

  async function revertSnapshot() {
    await evm_revert(snapshotId);
    snapshotId = await evm_snapshot();
  }

  beforeEach(async () => {
    await revertSnapshot();
  });

  it("upgrades successfully", async () => {
    const auriAirdropMockFactory = await ethers.getContractFactory("AuriAirdropMock");
    const auriAirdropMockImpl = await auriAirdropMockFactory.deploy();
    await auriAirdrop.upgradeTo(auriAirdropMockImpl.address);

    const auriAirdropMock = await getContractAt<AuriAirdropMock>("AuriAirdropMock", auriAirdrop.address);
    expect(await auriAirdropMock.dummyV2(ID, ply.address, admin.address)).eq(0);
  });

  it("distribute rewards correctly", async () => {
    await auriAirdrop.distribute(ID, ply.address, [bob.address], [_100PLY]);

    expect(await auriAirdrop.totalRewards(ID, ply.address, bob.address)).eq(_100PLY);
  });

  it("undistribute rewards correctly", async () => {
    await auriAirdrop.distribute(ID, ply.address, [bob.address], [_100PLY]);
    await auriAirdrop.unDistribute(ID, ply.address, [bob.address]);

    expect(await auriAirdrop.totalRewards(ID, ply.address, bob.address)).eq(0);
  });

  it("redeem rewards correctly", async () => {
    await auriAirdrop.distribute(ID, ply.address, [bob.address], [_100PLY]);
    await auriAirdrop.redeem([ID], [ply.address], bob.address);

    expect(await auriAirdrop.totalRewards(ID, ply.address, bob.address)).eq(_100PLY);
    expect(await auriAirdrop.redeemedRewards(ID, ply.address, bob.address)).eq(_100PLY);
    expect(await ply.balanceOf(bob.address)).eq(_100PLY);
  });

  it("getRedeemableReward works correctly", async () => {
    await auriAirdrop.distribute(ID, ply.address, [bob.address], [_100PLY]);
    await auriAirdrop.redeem([ID], [ply.address], bob.address);
    await auriAirdrop.distribute(ID, ply.address, [bob.address], [_100PLY.mul(2)]);

    expect(await auriAirdrop.getRedeemableReward(ID, ply.address, bob.address)).eq(_100PLY.mul(2));
  });

  it("doesn't allow anyone to re-init the implementation", async () => {
    await expect(auriAirdropImpl.initialize()).to.be.revertedWith("Initializable: contract is already initialized");
  });

  it("doesn't allow non-admin to upgrade", async () => {
    const auriAirdropMockFactory = await ethers.getContractFactory("AuriAirdropMock");
    const auriAirdropMockImpl = await auriAirdropMockFactory.deploy();
    await expect(auriAirdrop.connect(bob).upgradeTo(auriAirdropMockImpl.address)).to.be.revertedWith("Ownable: caller is not the owner");
  });
});
