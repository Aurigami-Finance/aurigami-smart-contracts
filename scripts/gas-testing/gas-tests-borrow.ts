import deployments from '../../1313161554-deployment.json';
import hre from 'hardhat';
import assert from 'assert';
import {AuErc20, AuriOracle, Comptroller, ERC20, Ply} from '../../typechain';
import {getContract} from '../../test/onchain_tests/helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {BigNumber as BN} from 'ethers';
import {AuriPriceFeed} from '../../typechain/AuriPriceFeed';
import {gasTestingFixture} from './fixture';

const REF_AMOUNT = 100; // FIXED AMOUNT FOR ALL TXs
const MINOR_AMOUNT = 10;
const INF = BN.from(2).pow(95);

async function main() {
  const [deployer, alice] = await hre.ethers.getSigners();
  let _nonceDeployer = await deployer.getTransactionCount();

  function nonce(wallet: SignerWithAddress): any {
    if (wallet.address === deployer.address) {
      return {nonce: _nonceDeployer++};
    }
  }

  assert(deployer.address == deployments.deployer, 'Wrong private key, must be deployer. (TOM)');
  const fixture = await gasTestingFixture();
  const comptroller = fixture.comptroller;
  const Ply = fixture.Ply;
  const assets = fixture.assets;

  let cnt = 0;
  for (let [token, auToken] of assets) {
    await token.approve(auToken.address, INF, nonce(deployer));
    if (token.address !== '') {
      // If not ply, deposit more, borrow less
      await (auToken as AuErc20).connect(deployer).mint(REF_AMOUNT, nonce(deployer));
      const tx = await (auToken as AuErc20).connect(deployer).borrow(MINOR_AMOUNT, nonce(deployer));
      await tx.wait();
      console.log(`Borrow ${await token.symbol()} ${tx.hash}`);
    } else {
      await (auToken as AuErc20).connect(deployer).mint(MINOR_AMOUNT, nonce(deployer));
      await (auToken as AuErc20).connect(deployer).borrow(REF_AMOUNT, nonce(deployer));
    }
    if (++cnt == 3) break;
  }
}

main();
