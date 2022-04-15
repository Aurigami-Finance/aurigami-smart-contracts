import {BigNumber as BN} from '@ethersproject/bignumber';
import {constants} from 'ethers';
import {waffle} from 'hardhat';

export const [lender, borrower, admin] = waffle.provider.getWallets();

export const ZERO_ADDRESS = constants.AddressZero;
export const ZERO = constants.Zero;
export const ONE = constants.One;
export const ONE_E_18 = BN.from(10).pow(18);
export const TWO = constants.Two;
export const PRECISION = constants.WeiPerEther;
export const ONE_DAY = BN.from(86400);
export const ONE_WEEK = ONE_DAY.mul(7);
export const ONE_MONTH = ONE_DAY.mul(31);
export const ONE_YEAR = ONE_DAY.mul(365);
export const MAX_UINT_96 = TWO.pow(96).sub(ONE);
export const MAX_UINT = constants.MaxUint256;
export const USDC_RESERVE_FACTOR = BN.from(15).mul(PRECISION).div(100);
export const USDC_COLLATERAL_FACTOR = BN.from(80).mul(PRECISION).div(100); // 0.8e18 = 80%
export const ETH_RESERVE_FACTOR = BN.from(25).mul(PRECISION).div(100);
export const ETH_COLLATERAL_FACTOR = BN.from(70).mul(PRECISION).div(100); // 0.7e18 = 70%
export const SEIZE_SHARE = BN.from(3).mul(PRECISION).div(100); // 0.03e18 = 3%
export const AURI_REWARD_SPEED = PRECISION.div(100);
export const PLY_REWARD_SPEED = PRECISION.div(100);
export const TOTAL_PLY_REWARDS = PRECISION.mul(10_000_000); // 10M
export const CHAINLINK_ETH_FEED_ON_ETH = '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419';
export const DUMMY_ADDRESS = '0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6';
export const FLUX_ETH_FEED = '0x842AF8074Fa41583E3720821cF1435049cf93565';
export const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
export const _1E8 = BN.from(10).pow(8);
export const INF = BN.from(2).pow(256).sub(1);
