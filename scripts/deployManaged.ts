import { network } from "hardhat";

// Usage: npx hardhat run scripts/deployManaged.ts --network testnet
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
  console.log("SimpleHTS721Managed contract:", await c.getAddress());

  // Include KYC key because we will grant KYC in the interaction script.
  const initTx = await c.initialize(
    "ManagedToken",
    "MGT",
    "managed demo",
    {
      admin: true,
      kyc: true,
      freeze: true,
      wipe: true,
      supply: true,
      fee: true,
      pause: true
    },
    false,
    ethers.ZeroAddress,
    0,
    { value: ethers.parseEther("15"), gasLimit: 400_000 }
  );
  await initTx.wait();
  console.log("Initialized token:", await c.hederaTokenAddress());

  console.log(
    "Deployment complete. Use interactManaged.ts to exercise management features."
  );
}

main().catch(console.error);
