import { AuriAirdrop, Comptroller, Comptroller__factory, Ply, Ply__factory, PULP, PULP__factory, ERC1967Proxy } from "../../typechain";
import hre, { ethers, waffle } from "hardhat";
import { BigNumber as BN } from "@ethersproject/bignumber/lib/bignumber";
import { constants, Contract } from "ethers";
const [admin, bob, charlie, dave, eve] = waffle.provider.getWallets();

export const T0 = BN.from(1651334400);

export class AirdropFixtures {
  constructor(
    public ply: Ply,
    public auriAirdrop: AuriAirdrop,
    public auriAirdropImpl:AuriAirdrop
  ) {
  }
}

export async function getContractAt<CType extends Contract>(abiType: string, address: string) {
  return (await hre.ethers.getContractAt(abiType, address)) as CType;
}

export async function airdropFixture(): Promise<AirdropFixtures> {
  const plyFactory = (await ethers.getContractFactory("Ply")) as Ply__factory;
  const ply = await plyFactory.deploy(admin.address);

  const auriAirdropFactory = await ethers.getContractFactory("AuriAirdrop");
  const auriAirdropImpl = await auriAirdropFactory.deploy();

  const proxyFactory = await ethers.getContractFactory("ERC1967Proxy");
  const proxy = await proxyFactory.deploy(auriAirdropImpl.address, []);

  const auriAirdrop = await getContractAt<AuriAirdrop>("AuriAirdrop", proxy.address);

  await auriAirdrop.initialize();

  return { ply, auriAirdrop, auriAirdropImpl };
}
