import { network } from "hardhat";

// Usage: npx hardhat run scripts/deployBurnable.ts --network testnet
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const Factory = await ethers.getContractFactory(
    "SimpleHTS721Burnable",
    deployer
  );
  const c = await Factory.deploy();
  await c.waitForDeployment();
  console.log("SimpleHTS721Burnable contract:", await c.getAddress());

  const initTx = await c.initialize(
    "BurnableToken",
    "BRN",
    "burn demo",
    {
      admin: true,
      kyc: false,
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
    "Deployment & initialization complete. Use interactBurnable.ts to mint & burn."
  );
}

main().catch(console.error);
