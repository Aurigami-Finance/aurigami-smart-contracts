import {assert} from 'chai';
import {BigNumber as BN, BigNumberish} from 'ethers';
import hre, {ethers} from 'hardhat';

export async function impersonateAccount(address: string) {
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [address],
  });
}

export async function impersonateAccountStop(address: string) {
  await hre.network.provider.request({
    method: 'hardhat_stopImpersonatingAccount',
    params: [address],
  });
}

export async function evm_snapshot() {
  return (await hre.network.provider.request({
    method: 'evm_snapshot',
    params: [],
  })) as string;
}

export async function evm_revert(snapshotId: string) {
  return (await hre.network.provider.request({
    method: 'evm_revert',
    params: [snapshotId],
  })) as string;
}

export async function toNumber(bn: BigNumberish) {
  return BN.from(bn).toNumber();
}

export async function advanceTime(duration: BigNumberish) {
  await hre.network.provider.send('evm_increaseTime', [await toNumber(duration)]);
  await hre.network.provider.send('evm_mine', []);
}

export async function setNextBlockTimeStamp(time: BigNumberish) {
  await hre.network.provider.send('evm_setNextBlockTimestamp', [await toNumber(time)]);
}

export async function moveToTimestamp(time: BigNumberish) {
  await hre.network.provider.send('evm_setNextBlockTimestamp', [await toNumber(time)]);
  await hre.network.provider.send('evm_mine', []);
}

export async function advanceTimeAndBlock(time: BigNumberish, blockCount: number) {
  assert(blockCount >= 1);
  await advanceTime(time);
  await mineBlock(blockCount - 1);
}

export async function mineAllPendingTransactions() {
  let pendingBlock: any = await hre.network.provider.send('eth_getBlockByNumber', ['pending', false]);
  await mineBlock();
  pendingBlock = await hre.network.provider.send('eth_getBlockByNumber', ['pending', false]);
  assert(pendingBlock.transactions.length == 0);
}

export async function mineBlock(count?: number) {
  if (count == null) count = 1;
  while (count-- > 0) {
    await hre.network.provider.send('evm_mine', []);
  }
}

export async function minerStart() {
  await hre.network.provider.send('evm_setAutomine', [true]);
}

export async function minerStop() {
  await hre.network.provider.send('evm_setAutomine', [false]);
}

export async function getEth(user: string) {
  await hre.network.provider.send('hardhat_setBalance', [user, '0x56bc75e2d63100000000000000']);
}
