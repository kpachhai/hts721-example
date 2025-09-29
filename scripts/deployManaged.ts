import { network } from "hardhat";

/**
 * Deploys SimpleHTS721Managed (mint/burn + management + neutralizer).
 * Usage: npx hardhat run scripts/deploy_managed.ts --network testnet
 */
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const Factory = await ethers.getContractFactory(
    "SimpleHTS721Managed",
    deployer
  );
  const c = await Factory.deploy();
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log("SimpleHTS721Managed deployed at:", addr);

  const ADMIN = 1,
    KYC = 2,
    FREEZE = 4,
    WIPE = 8,
    SUPPLY = 16,
    FEE = 32,
    PAUSE = 64;
  const keyMask = ADMIN | KYC | FREEZE | WIPE | SUPPLY | FEE | PAUSE; // 127

  const initTx = await c.initialize(
    {
      name: "ManagedToken",
      symbol: "MGT",
      memo: "managed demo",
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
  console.log("Managed deploy complete.");
}

main().catch(console.error);
