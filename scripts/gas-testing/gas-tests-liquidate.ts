import deployments from '../../1313161555-deployment.json';
import hre from 'hardhat';
import assert from 'assert';
import {AuErc20, AuriOracle, Comptroller, ERC20, Ply} from '../../typechain';
import {getContract} from '../../test/onchain_tests/helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {BigNumber as BN} from 'ethers';
import {AuriPriceFeed} from '../../typechain/AuriPriceFeed';
import {gasTestingFixture} from './fixture';

const REF_AMOUNT = 1000; // FIXED AMOUNT FOR ALL TXs
const INF = BN.from(2).pow(95);
const ONE_DOLLAR = BN.from(10).pow(8);

async function main() {
  const [deployer, alice] = await hre.ethers.getSigners();
  let _nonceDeployer = await deployer.getTransactionCount();
  let _nonceAlice = await alice.getTransactionCount();

  function nonce(wallet: SignerWithAddress): any {
    if (hre.network.name === 'hardhat') return {};
    if (wallet.address === deployer.address) return {nonce: _nonceDeployer++};
    else return {nonce: _nonceAlice++};
  }

  assert(deployer.address == deployments.deployer, 'Wrong private key, must be deployer. (TOM)');
  const fixture = await gasTestingFixture();
  const assets = fixture.assets;
  const comptroller = fixture.comptroller;
  const oracle = fixture.oracle;

  try {
    let LIMIT_ASSETS = 7;
    await comptroller.connect(deployer)._setMaxAssets(LIMIT_ASSETS, nonce(deployer));

    for (let [token, auToken] of assets) {
      await token.connect(deployer).approve(auToken.address, INF, nonce(deployer));
      await (auToken as AuErc20).connect(deployer).mint(30, nonce(deployer));
      await (auToken as AuErc20).connect(deployer).borrow(10, nonce(deployer));
      if (--LIMIT_ASSETS == 0) break;
    }

    const auUSDC = assets[1][1] as AuErc20;
    const auUSDT = assets[0][1] as AuErc20;
    const USDT = assets[0][0] as ERC20;

    await USDT.connect(alice).approve(auUSDT.address, INF, nonce(alice));
    await USDT.connect(deployer).transfer(alice.address, 10 ** 6, nonce(deployer));
    await auUSDT.connect(alice).mint(5 * 10 ** 5, nonce(alice));
    // Collateral 1 USDC, borrow 0.1 USDT
    await oracle.connect(deployer).updateMainFeedData(auUSDT.address, ONE_DOLLAR.mul(1), nonce(deployer));
    await auUSDC.connect(deployer).mint(2 * 10 ** 5, nonce(deployer));
    await auUSDT.connect(deployer).borrow(10 ** 5, nonce(deployer));
    // // USDT raises x100
    await oracle.connect(deployer).updateMainFeedData(auUSDT.address, ONE_DOLLAR.mul(100), nonce(deployer));

    // // alice liquidate
    console.log(await comptroller.getAccountLiquidity(deployer.address));
    const tx = await auUSDT.connect(alice).liquidateBorrow(deployer.address, 10 ** 2, auUSDC.address, nonce(alice));

    const receipt = await tx.wait();
    console.log(receipt.transactionHash, receipt.gasUsed);
  } catch (e) {
    console.log(e);
  }

  for (let person of [deployer, alice]) {
    for (let [token, auToken] of assets) {
      const borrowBal = await (auToken as AuErc20).callStatic.borrowBalanceCurrent(person.address);
      if (borrowBal.gt(0)) {
        await (auToken as AuErc20).connect(person).repayBorrow(borrowBal, nonce(person));
      }
      const supplyBal = await (auToken as AuErc20).balanceOf(person.address);
      if (supplyBal.gt(0)) {
        await (auToken as AuErc20).connect(person).redeem(supplyBal, nonce(person));
      }
      await comptroller.connect(person).exitMarket(auToken.address, nonce(person));
    }
  }
}

main();
