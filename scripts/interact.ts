import { network } from "hardhat";

// Usage: npx hardhat run scripts/interact.ts --network testnet
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  // Replace with your deployed contract address
  const contractAddress = "0x0E6ca3F13DC4f47C8c16dd7c730136049E1D152A";

  const [caller] = await ethers.getSigners();
  console.log("Caller:", caller.address);
  console.log("Contract:", contractAddress);

  const c = await ethers.getContractAt("SimpleHTS721", contractAddress, caller);

  // NOTE: This simple contract was deployed with kyc:false (so no grant needed).
  const balBefore = await c.balanceOf(caller.address);
  console.log("Balance before mint:", balBefore.toString());

  // Mint new token
  // First, need to associate the token with caller's account on Hedera
  const assocTx = await c.associate();
  await assocTx.wait();
  console.log("Associated token with caller's account. Tx:", assocTx.hash);
  // Now mint
  const mintTx = await c.mintTo(caller.address, "0x", { gasLimit: 400_000 });
  await mintTx.wait();
  console.log("Minted token, tx:", mintTx.hash);

  const balAfter = await c.balanceOf(caller.address);
  console.log("Balance after mint:", balAfter.toString());
}

main().catch(console.error);
