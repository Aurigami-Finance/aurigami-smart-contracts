import {task} from 'hardhat/config';
import {testnetDeployConfig as config} from './config/config';

import {AuriOracle} from '../typechain';

task('oracle-deploy', 'deploy oracle').setAction(async (taskArgs, hre) => {
  const [deployer] = await hre.ethers.getSigners();
  console.log(`Deployer: ${deployer.address}`);

  const oracleFactory = await hre.ethers.getContractFactory('AuriOracle');
  const oracle = await oracleFactory.deploy(config.updator1!, config.updator2!, config.updator3!);
  await oracle.deployed();
  console.log(`AuriOracle deployed at address: ${oracle.address}`);
  console.log(`u1: ${config.updator1!}, u2: ${config.updator2!}, u3:${config.updator3!}`);
  console.log(`Please save it to deployment file`);
  process.exit(0);
});

task('oracle-setup', 'set underlying decimals and backup feeds').setAction(async (taskArgs, hre) => {
  const [deployer] = await hre.ethers.getSigners();
  const deployment = require(`../deployments/${config.EXPORT_FILENAME}`);
  const oracleAddress = deployment.oracle;
  console.log(`Deployer: ${deployer.address}, oracle = ${oracleAddress}`);

  const oracle: AuriOracle = await hre.ethers.getContractAt('AuriOracle', oracleAddress);
  const auTokenAddresses: string[] = [];
  const backupFeeds: string[] = [];
  const underlyingDecimals: number[] = [];
  for (const token of config.TOKENS) {
    if (token.name == 'PLY') continue;
    auTokenAddresses.push(deployment.auTokens[token.name]);
    backupFeeds.push(config.IS_MAINNET ? token.MAINNET_BACKUP_FEED : token.TESTNET_BACKUP_FEED);
    underlyingDecimals.push(token.UNDERLYING_DECIMAL);
  }
  await oracle.setBackupFeedAddr(auTokenAddresses, backupFeeds);
  await oracle.setUnderlyingDecimals(auTokenAddresses, underlyingDecimals);
  process.exit(0);
});
