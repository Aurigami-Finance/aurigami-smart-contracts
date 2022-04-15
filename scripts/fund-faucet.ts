import hre from 'hardhat';
import {BigNumber as BN, Contract} from 'ethers';
import {AuriConfigReader, AuriLens, AuriOracle, Comptroller, ERC20, Faucet} from '../typechain';
import {getContract} from '../test/onchain_tests/helpers';
import * as testnet from '../deployments/aurora_testnet.json';
import fs from 'fs';
let _nonce: number;
let configReader: AuriConfigReader;

async function main() {
  function nonce(): any {
    const nonceSettings = {
      nonce: _nonce,
    };
    _nonce++;
    return nonceSettings;
  }
  function toWei(amount: number, decimals: number) {
    return BN.from(amount).mul(BN.from(10).pow(decimals));
  }

  const [deployer] = await hre.ethers.getSigners();
  hre.ethers.utils.Logger.setLogLevel(hre.ethers.utils.Logger.levels.ERROR); // turn off warnings
  _nonce = await deployer.getTransactionCount();
  console.log(`Deployer: ${deployer.address}`);

  let faucet: Faucet = await getContract('Faucet', testnet.faucet);

  let sup = testnet.supportedTokens;
  let _1E7 = 10 ** 7;
  // for(let x of [sup.USDC, sup.WBTC, sup.USDT, sup.DAI, sup.PLY, sup.WNEAR]){
  //   let tok : ERC20 = await getContract('ERC20', x);
  //   console.log(await tok.balanceOf(testnet.faucet));
  // }

  await faucet.fundToken(sup.USDC, toWei(2500, 6), toWei(_1E7 * 2, 6), nonce());
  console.log('Done');
  await faucet.fundToken(sup.WBTC, toWei(1, 8).div(16), toWei(10 ** 5, 8), nonce());
  console.log('Done');
  await faucet.fundToken(sup.USDT, toWei(2500, 6), toWei(_1E7 * 2, 6), nonce());
  console.log('Done');
  await faucet.fundToken(sup.DAI, toWei(2500, 18), toWei(_1E7 * 2, 18), nonce());
  console.log('Done');
  await faucet.fundToken(sup.PLY, toWei(2500, 18), toWei(_1E7 * 2, 18), nonce());
  console.log('Done');
  await faucet.fundToken(sup.WNEAR, toWei(250, 24), toWei(_1E7 * 2, 24), nonce());
  console.log('Done');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
