import { network } from "hardhat";

/**
 * Interacts with SimpleHTS721 (core only).
 * Demonstrates absence of mint/management functions.
 * Usage: npx hardhat run scripts/interact_core.ts --network testnet
 */
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const contractAddress = "0xBb61e058d7BFdEF5F864867Dbc3bCCBcC223F813"; // replace with your deployed core contract address
  const [caller] = await ethers.getSigners();

  console.log("Caller:", caller.address);
  console.log("Core wrapper:", contractAddress);

  const c = await ethers.getContractAt("SimpleHTS721", contractAddress, caller);

  console.log("Initialized?", await c.initialized());
  console.log("Underlying HTS token:", await c.hederaTokenAddress());

  // Try calling non-existent function (mintTo) to prove core surface is minimal
  try {
    // @ts-ignore
    await c.mintTo(caller.address, "0x");
    console.log("Unexpected: mintTo exists.");
  } catch {
    console.log("As expected: mintTo not available on core-only contract.");
  }

  console.log("Core interaction complete.");
}

main().catch(console.error);
