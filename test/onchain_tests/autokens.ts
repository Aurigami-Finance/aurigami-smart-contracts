import {waffle} from 'hardhat';
import {deploymentFixture, Network, TestEnv, Token} from './config';
import {
  emptyToken,
  evm_revert,
  evm_snapshot,
  getContract,
  getEth,
  impersonateAccount,
  impersonateAccountStop,
  mintFromSource,
  toWei,
} from './helpers';
import {BigNumber as BN, Wallet} from 'ethers';
import {expect} from 'chai';
import {FluxPriceFeed} from '../../typechain';
import hre from 'hardhat';
import {loadFixture} from 'ethereum-waffle';
import {ComptrollerError, TokenError} from './consts';

describe('Onchain autoken tests', async () => {
  const wallets = waffle.provider.getWallets();
  const [alice, bob, charlie, dave, eve] = wallets;

  let env: TestEnv;
  let tokens: Token[];
  let testToken: Token;

  const INF = BN.from(2).pow(96).sub(1);
  const ONE_E_8 = BN.from(10).pow(12);
  let REF_AMOUNT: BN = BN.from(10 ** 8);
  const FLUX_FEEDS = ['0x2720AE5F31643080b8701d677EC284BC646dd290', '0x842AF8074Fa41583E3720821cF1435049cf93565'];
  const FLUX_OWNER: string = '0xB8af1be8169bC0e6345fAcb383be58A6B4D04EE4';

  let snapshotId: string;
  let globalSnapshotId: string;

  before(async () => {
    globalSnapshotId = await evm_snapshot();
    env = await loadFixture(deploymentFixture);

    testToken = env.tokens!.USDC!;
    tokens = [
      env.tokens!.USDC!,
      env.tokens!.USDT!,
      env.tokens!.WBTC!,
      env.tokens!.DAI!,
      env.tokens!.PLY!,
      env.tokens!.AURORA!,
      env.tokens!.WNEAR!,
    ]; // @TODO: Add Eth
    for (let token of tokens) {
      await env.comptroller!.connect(alice)._setBorrowPaused(token.auContract.address, false);
      for (let user of wallets) {
        await mintFromSource(token.whale!, user.address, token.contract.address, REF_AMOUNT.mul(100));
        await token.contract.connect(user).approve(token.auContract.address, INF);
      }
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

  after(async () => {
    await evm_revert(globalSnapshotId);
  });

  async function runSimpleTokenTest(test: any) {
    for (let token of tokens) {
      testToken = token;
      console.log('Testing on: ', await testToken.contract.symbol());
      await test();
    }
  }

  async function createBadGasScenario(flux: FluxPriceFeed) {
    for (let token of tokens) {
      await env.oracle!.connect(alice).setFeed(await token.contract.symbol(), flux.address);
      for (let user of wallets) {
        // each person will deposit 10 token and borrow 1 token from the contract to create the worst gas scenario
        await token.auContract.connect(user).mint(100);
        await token.auContract.connect(user).borrow(10);
      }
    }
  }

  async function addFakeIncome(amount: BN = REF_AMOUNT) {
    await testToken.contract.connect(eve).transfer(testToken.auContract.address, amount);
  }

  async function tokenBalance(user: Wallet, token: Token = testToken): Promise<BN> {
    return token.contract.balanceOf(user.address);
  }

  async function auTokenBalance(user: Wallet, token: Token = testToken): Promise<BN> {
    return token.auContract.balanceOf(user.address);
  }

  it('AuToken minting & burning', async () => {
    await runSimpleTokenTest(async () => {
      for (let user of [alice, bob, charlie, dave]) {
        const oldBal = await tokenBalance(user);
        await testToken.auContract.connect(user).mint(REF_AMOUNT);

        const auBal = await auTokenBalance(user);
        expect(auBal).to.be.gt(0);

        await addFakeIncome();
        await testToken.auContract.connect(user).redeem(auBal);

        const newBal = await tokenBalance(user);
        expect(newBal).to.be.gt(oldBal);
      }
    });
  });

  it('AuToken transfer & approve', async () => {
    await runSimpleTokenTest(async () => {
      let AU_REF_AMOUNT: BN = BN.from(1);
      for (let user of wallets) {
        await testToken.auContract.connect(user).mint(REF_AMOUNT);
        AU_REF_AMOUNT = await auTokenBalance(user);
      }

      for (let i = 0; i + 1 < wallets.length; i += 2) {
        await testToken.auContract.connect(wallets[i]).approve(eve.address, AU_REF_AMOUNT);
        await testToken.auContract
          .connect(eve)
          .transferFrom(wallets[i].address, wallets[i + 1].address, AU_REF_AMOUNT);
        await testToken.auContract.connect(wallets[i + 1]).transfer(wallets[i].address, AU_REF_AMOUNT);
      }

      for (let user of wallets) {
        expect(await auTokenBalance(user)).to.be.eq(AU_REF_AMOUNT);
      }
    });
  });

  // @TLDR: Liquidate & borrowng scenario. Long & ugly test
  it.only('Autokens borrowing', async () => {
    async function setPriceFeed(flux: FluxPriceFeed, newPrice: BN): Promise<void> {
      await impersonateAccount(FLUX_OWNER);
      const signer = await hre.ethers.getSigner(FLUX_OWNER);
      await getEth(FLUX_OWNER);
      await flux.connect(signer).transmit(newPrice);
      await impersonateAccountStop(FLUX_OWNER);
    }

    for (let [token0, token1] of [
      [env.tokens!.WNEAR!, env.tokens!.USDC!],
      [env.tokens!.USDC!, env.tokens!.WNEAR!],
    ]) {
      await revertSnapshot();
      const flux0 = (await getContract('FluxPriceFeed', FLUX_FEEDS[0])) as FluxPriceFeed;
      const flux1 = (await getContract('FluxPriceFeed', FLUX_FEEDS[1])) as FluxPriceFeed;
      await setPriceFeed(flux0, ONE_E_8);
      await createBadGasScenario(flux0);
      await setPriceFeed(flux1, ONE_E_8);
      await env.oracle!.connect(alice).setFeed(await token0.contract.symbol(), flux0.address);
      await env.oracle!.connect(alice).setFeed(await token1.contract.symbol(), flux1.address);

      // prepare tokens
      const REF_AMOUNT_0 = toWei(1, await token0.contract.decimals());
      const REF_AMOUNT_1 = toWei(1, await token1.contract.decimals());
      await emptyToken(token0.contract, alice);
      await emptyToken(token1.contract, alice);
      await mintFromSource(token0.whale!, alice.address, token0.contract.address, REF_AMOUNT_0);
      await mintFromSource(token1.whale!, bob.address, token1.contract.address, REF_AMOUNT_1.mul(2));
      await token0.auContract.connect(alice).mint(REF_AMOUNT_0);
      await token1.auContract.connect(bob).mint(REF_AMOUNT_1);

      // Alice provide liquidity && borrow more token0
      expect(await tokenBalance(alice, token0)).to.be.eq(0);
      await token0.auContract.connect(alice).borrow(REF_AMOUNT_0.div(2));
      expect(await tokenBalance(alice, token0)).to.be.gt(0);

      // Bob tries to liquidate, but reverted
      expect(
        await token0.auContract
          .connect(bob)
          .callStatic.liquidateBorrow(alice.address, REF_AMOUNT_0.mul(2), token0.auContract.address)
      ).to.be.eq(TokenError.COMPTROLLER_REJECTION);
      // token0 price drops, bob still can't liquidate with
      await setPriceFeed(flux0, ONE_E_8.div(2));
      expect(
        await token1.auContract
          .connect(bob)
          .callStatic.liquidateBorrow(alice.address, REF_AMOUNT_0.mul(2), token0.auContract.address)
      ).to.be.eq(TokenError.COMPTROLLER_REJECTION);

      // Alice repays the loan
      await setPriceFeed(flux0, ONE_E_8);
      await token0.auContract.connect(alice).repayBorrow(REF_AMOUNT_0.div(2));
      expect(await tokenBalance(alice, token0)).to.be.eq(0);

      // Alice then borrow token1, token0 price drops, bob tries to liquidate with token1 and succeeds
      expect(await tokenBalance(alice, token1)).to.be.eq(0);
      await token1.auContract.connect(alice).borrow(REF_AMOUNT_1.div(2));
      expect(await tokenBalance(alice, token1)).to.be.gt(0);

      await setPriceFeed(flux0, ONE_E_8.div(3));
      const oldBal = await auTokenBalance(bob, token0);
      // liquidate borrow failed, due to 50% close factor
      await token1.auContract
        .connect(bob)
        .liquidateBorrow(alice.address, REF_AMOUNT_1.div(2), token0.auContract.address);
      expect(await auTokenBalance(bob, token0)).to.be.equal(oldBal);

      // liquidation succeed
      await token1.auContract
        .connect(bob)
        .liquidateBorrow(alice.address, REF_AMOUNT_1.div(10), token0.auContract.address);
      expect(await auTokenBalance(bob, token0)).to.be.gt(oldBal);
    }
  });
});
