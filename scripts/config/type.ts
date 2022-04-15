import {BigNumber as BN} from '@ethersproject/bignumber';

export type InterestRateConfig = {
  BASE_RATE: BN;
  NORMAL_MULTIPLIER: BN;
  JUMP_MULTIPLIER: BN;
  KINK: BN;
};
export type TokenConfig = {
  name: string;
  address: string;
  BORROW_CAP: BN;
  COLLATERAL_FACTOR: BN;
  RESERVE_FACTOR: BN;
  SEIZE_SHARE: BN;
  AURORA_REWARD_LEND_SPEED: BN;
  AURORA_REWARD_BORROW_SPEED: BN;
  PLY_REWARD_LEND_SPEED: BN;
  PLY_REWARD_BORROW_SPEED: BN;
  UNDERLYING_DECIMAL: number;
  MAINNET_BACKUP_FEED: string;
  TESTNET_BACKUP_FEED: string;
  // INTEREST_RATE_MODEL_TYPE: Number
};
export type GlobalConfig = {
  IS_MAINNET: boolean;
  REWARD_CLAIM_START: BN;
  CLOSE_FACTOR: BN;
  LIQUIDATION_INCENTIVE: BN;
  TOKENS: TokenConfig[];
  BORROW_CAP_GUARDIAN: string;
  PAUSE_GUARDIAN: string;
  ORACLE: string;
  EXPORT_FILENAME: string;
  MAX_ASSET: number;
  AURORA_ADDRESS: string;
  GOVERNANCE_MULTISG: string;
  INTEREST_RATE_MODEL: InterestRateConfig;

  updator1?: string;
  updator2?: string;
  updator3?: string;
};
