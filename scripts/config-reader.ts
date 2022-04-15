import { AuriConfigReader } from "../typechain";
import * as mainnet from "../deployments/aurora_mainnet.json";
import { Env, getContractAt, JSONReplacerBigNum } from "./helpers/helpers";
import { BigNumber } from "ethers";
import fs from "fs";
import hre from "hardhat";
import * as config from "./config/config";

export function toJSON(object: any): any {
  let data: Record<string, string> = {};
  for (let keys of Object.keys(object)) {
    if (keys.match(/^[0-9]+$/) == null) {
      data[keys] = object[keys];
    }
  }
  return data;
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  let env = new Env(deployer, config.mainnetDeployConfig);
  await env.init(mainnet);


  let output: string[] = [];
  let comptrollerDataRaw = await env.configReader.readComptroller();
  output.push(toJSON(comptrollerDataRaw));

  let allAuTokensImmutable = await env.configReader.readAllAuTokensImmutable();
  for(let ele of allAuTokensImmutable) {
    output.push(toJSON(ele));
  }

  let allAuTokensVolatile = await env.configReader.readAllAuTokensVolatile();
  for(let ele of allAuTokensVolatile) {
    output.push(toJSON(ele));
  }

  fs.writeFileSync("config.json", JSON.stringify(output, JSONReplacerBigNum));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
