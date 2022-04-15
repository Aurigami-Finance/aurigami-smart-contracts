import deployments from '../../1313161555-deployment.json';
import {getContract} from '../../test/onchain_tests/helpers';
import {AuErc20, AuriOracle, Comptroller, ERC20, Ply} from '../../typechain';

export async function gasTestingFixture() {
  const comptroller: Comptroller = await getContract('Comptroller', deployments.unitroller);
  const Ply: Ply = await getContract('Ply', deployments.ply);
  const oracle: AuriOracle = await getContract('AuriOracle', deployments.oracle);

  const assets = [
    // skipping on Ether, doing Ply instead for 6 assets
    [
      (await getContract('ERC20', deployments.supportedTokens.USDC)) as ERC20,
      (await getContract('AuErc20', deployments.auTokens.USDC)) as AuErc20,
    ],
    [
      (await getContract('ERC20', deployments.supportedTokens.USDT)) as ERC20,
      (await getContract('AuErc20', deployments.auTokens.USDT)) as AuErc20,
    ],
    [
      (await getContract('ERC20', deployments.supportedTokens.WBTC)) as ERC20,
      (await getContract('AuErc20', deployments.auTokens.WBTC)) as AuErc20,
    ],
    [
      (await getContract('ERC20', deployments.supportedTokens.DAI)) as ERC20,
      (await getContract('AuErc20', deployments.auTokens.DAI)) as AuErc20,
    ],
    [
      (await getContract('ERC20', deployments.supportedTokens.WNEAR)) as ERC20,
      (await getContract('AuErc20', deployments.auTokens.WNEAR)) as AuErc20,
    ],
    [
      (await getContract('ERC20', deployments.supportedTokens.PLY)) as ERC20,
      (await getContract('AuErc20', deployments.auTokens.PLY)) as AuErc20,
    ],
    [
      (await getContract('ERC20', deployments.supportedTokens.AURORA)) as ERC20,
      (await getContract('AuErc20', deployments.auTokens.AURORA)) as AuErc20,
    ],
  ];

  return {
    comptroller,
    Ply,
    assets,
    oracle,
  };
}
