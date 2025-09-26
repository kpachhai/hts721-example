import { network } from "hardhat";

// Usage: npx hardhat run scripts/interactBurnable.ts --network testnet
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  // Replace with your deployed contract address
  const contractAddress = "0xe99C6f1b21D665b28CDaEbf6004D23b9297a33db";

  const [caller] = await ethers.getSigners();
  console.log("Caller:", caller.address);
  console.log("Contract:", contractAddress);

  const c = await ethers.getContractAt(
    "SimpleHTS721Burnable",
    contractAddress,
    caller
  );

  // Mint new token
  // First, need to associate the token with caller's account on Hedera
  const assocTx = await c.associate();
  await assocTx.wait();
  console.log("Associated token with caller's account. Tx:", assocTx.hash);
  // Now mint
  const mintTx = await c.mintTo(caller.address, "0x", { gasLimit: 400_000 });
  await mintTx.wait();
  console.log("Minted tokenId 1 (assuming first serial). Tx:", mintTx.hash);

  // Burn tokenId = 1
  // Need to approve the contract to transfer the token first
  const currentApproved = await c.getApproved(1);
  console.log("Current approved for tokenId 1:", currentApproved);
  const approveTx = await c.approve(contractAddress, 1, { gasLimit: 800_000 });
  await approveTx.wait();
  console.log("Approved tokenId 1 to contract. Tx:", approveTx.hash);
  // Now burn
  const burnTx = await c.burnOwned(1, { gasLimit: 400_000 });
  await burnTx.wait();
  console.log("Burned tokenId 1. Tx:", burnTx.hash);
}

main().catch(console.error);
