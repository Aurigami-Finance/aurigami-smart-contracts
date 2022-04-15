import { Comptroller, Comptroller__factory, Ply, Ply__factory, PULP, PULP__factory } from "../../typechain";
import { ethers, waffle } from "hardhat";
import { BigNumber as BN } from "@ethersproject/bignumber/lib/bignumber";
const [admin, bob, charlie, dave, eve] = waffle.provider.getWallets();

export const T0 = BN.from(1651334400);

export class PulpFixtures {
  constructor(
    public comptroller: Comptroller,
    public pulp: PULP,
    public ply: Ply
  ) {
  }
}

export async function pulpFixture(): Promise<PulpFixtures> {
  const comptrollerFactory = (await ethers.getContractFactory("Comptroller")) as Comptroller__factory;
  const comptroller = await comptrollerFactory.deploy();

  await comptroller.setRewardClaimStart(T0);

  const plyFactory = (await ethers.getContractFactory("Ply")) as Ply__factory;
  const ply = await plyFactory.deploy(admin.address);

  const pulpFactory = (await ethers.getContractFactory("PULP")) as PULP__factory;
  const pulp = await pulpFactory.deploy(ply.address, comptroller.address);

  return { comptroller, ply, pulp };
}
