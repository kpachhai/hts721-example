import { network } from "hardhat";

/**
 * Deploys SimpleHTS721 (core only).
 * Adds SUPPLY key to satisfy Hedera NFT creation requirement.
 * Usage: npx hardhat run scripts/deploy_core.ts --network testnet
 */
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const Factory = await ethers.getContractFactory("SimpleHTS721", deployer);
  const c = await Factory.deploy();
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log("SimpleHTS721 deployed at:", addr);

  // MUST include SUPPLY (16) for NFT token creation or Hedera returns rc=180 (TOKEN_HAS_NO_SUPPLY_KEY)
  const ADMIN = 1;
  const SUPPLY = 16;
  const keyMask = ADMIN | SUPPLY;

  const initTx = await c.initialize(
    {
      name: "CoreToken",
      symbol: "CORE",
      memo: "core wrapper",
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
  console.log("Core deploy complete.");
}

main().catch(console.error);
