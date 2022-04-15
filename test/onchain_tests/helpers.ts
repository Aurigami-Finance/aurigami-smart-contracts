import hre from 'hardhat';
import {ERC20} from '../../typechain';
import {assert} from 'console';
import {BigNumber as BN, BigNumberish, Contract, Wallet} from 'ethers';
export async function getEth(user: string) {
  await hre.network.provider.send('hardhat_setBalance', [user, '0x56bc75e2d63100000000000000']);
}

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

export async function mintFromSource(source: string, to: string, token: string, amount: BN) {
  await getEth(source);
  await impersonateAccount(source);
  const signer = await hre.ethers.getSigner(source);
  const tokenContract = (await getContract('ERC20', token)) as ERC20;
  const bal = await tokenContract.balanceOf(source);
  assert(bal.gte(amount), `Amount minting exceeds source's balance ${await tokenContract.symbol()}`);
  await tokenContract.connect(signer).transfer(to, amount);
  await impersonateAccountStop(source);
}

export async function getContract(abiName: string, address: string): Promise<any> {
  await hre.ethers.getContractAt(abiName, address);
  return await hre.ethers.getContractAt(abiName, address);
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

export function toWei(amount: BigNumberish, decimal: BigNumberish): BN {
  return BN.from(amount).mul(BN.from(10).pow(decimal));
}

export async function emptyToken(token: Contract, of: Wallet): Promise<void> {
  await token.connect(of).transfer('0x0000000000000000000000000000000000000001', await token.balanceOf(of.address));
}
