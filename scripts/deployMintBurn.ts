import { network } from "hardhat";

/**
 * Deploys SimpleHTS721MintBurn (mint/burn only).
 * Usage: npx hardhat run scripts/deploy_mint_burn.ts --network testnet
 */
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const Factory = await ethers.getContractFactory(
    "SimpleHTS721MintBurn",
    deployer
  );
  const c = await Factory.deploy();
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log("SimpleHTS721MintBurn deployed at:", addr);

  const ADMIN = 1;
  const SUPPLY = 16;
  const keyMask = ADMIN | SUPPLY;

  const initTx = await c.initialize(
    {
      name: "MintBurnToken",
      symbol: "MBT",
      memo: "mint burn demo",
      keyMask,
      freezeDefault: false,
      autoRenewAccount: deployer.address,
      autoRenewPeriod: 0
    },
    {
      value: ethers.parseEther("10"),
      gasLimit: 400_000
    }
  );
  await initTx.wait();
  console.log("Underlying HTS token:", await c.hederaTokenAddress());
  console.log("Mint/Burn deploy complete.");
}

main().catch(console.error);
