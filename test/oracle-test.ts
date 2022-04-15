import {fixture} from './fixture';
import {
  AggregatorV3Interface,
  AggregatorV3Interface__factory,
  AuETH,
  AuriOracle,
  AuriFairLaunch,
  AuriLens,
  Comptroller,
  ERC20PresetFixedSupply,
  Ply,
  TokenLock,
  AuErc20,
  AuToken,
} from '../typechain';
import {loadFixture} from 'ethereum-waffle';
import {ethers} from 'hardhat';
import {admin, CHAINLINK_ETH_FEED_ON_ETH, ETH_ADDRESS, FLUX_ETH_FEED, ZERO, ZERO_ADDRESS} from './Constants';
import {BigNumber} from 'ethers';
import {expect} from 'chai';
import {advanceTime} from './hardhat-helpers';

let unitroller: Comptroller;
let oracle: AuriOracle;
let fairLaunch: AuriFairLaunch;
let auUSDC: AuErc20;
let auETH: AuETH;
let aurora: ERC20PresetFixedSupply;
let ply: Ply;
let tokenLock: TokenLock;
let lens: AuriLens;
let FluxEthFeed: AggregatorV3Interface;
let ChainlinkEthFeed: AggregatorV3Interface;

async function postPrice(
  oracle: AuriOracle,
  auToken: AuToken,
  sourceFeed: AggregatorV3Interface
): Promise<{
  roundId: BigNumber;
  answer: BigNumber;
  startedAt: BigNumber;
  updatedAt: BigNumber;
  answeredInRound: BigNumber;
}> {
  let {roundId, answer, startedAt, updatedAt, answeredInRound} = await sourceFeed.latestRoundData();
  await oracle.connect(admin).updateMainFeedData(auToken.address, answer);
  return {
    roundId,
    answer,
    startedAt,
    updatedAt,
    answeredInRound,
  };
}

describe('Oracle test', () => {
  let ethProvider = new ethers.providers.AlchemyProvider('homestead', process.env.ALCHEMY_KEY);
  before(async () => {
    FluxEthFeed = new ethers.Contract(FLUX_ETH_FEED, AggregatorV3Interface__factory.abi) as AggregatorV3Interface;
    ChainlinkEthFeed = new ethers.Contract(
      CHAINLINK_ETH_FEED_ON_ETH,
      AggregatorV3Interface__factory.abi,
      ethProvider
    ) as AggregatorV3Interface;
  });

  beforeEach('load fixture', async () => {
    ({unitroller, oracle, fairLaunch, auUSDC, auETH, aurora, ply, tokenLock, lens} = await loadFixture(fixture));
  });

  it('test fetch & query of price for ETH', async () => {
    const decimalScale = BigNumber.from(10).pow(10);
    let {answer: refPrice} = await postPrice(oracle, auETH, ChainlinkEthFeed);
    expect((await oracle.mainFeed(auETH.address)).answer).to.be.eq(refPrice);
    expect(await oracle.getUnderlyingPrice(auETH.address)).to.be.eq(refPrice.mul(decimalScale));
    let {price, isFromMainFeed} = await oracle._getRawUnderlyingPrice(auETH.address);
    expect(price).to.be.eq(refPrice);
    expect(isFromMainFeed).to.be.true;
  });

  it('backup feed should work', async () => {
    let {answer: refAnswer} = await postPrice(oracle, auETH, ChainlinkEthFeed);
    let priceValidityDuration = await oracle.validPeriod();

    console.log(priceValidityDuration);
    // force to use backup feed
    await advanceTime(priceValidityDuration.mul(2));

    console.log(refAnswer);
    console.log(await oracle.getUnderlyingPrice(auETH.address));
    expect((await oracle._getRawUnderlyingPrice(auETH.address)).isFromMainFeed).to.be.false;
  });
});
