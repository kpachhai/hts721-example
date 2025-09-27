import { network } from "hardhat";

// Usage: npx hardhat run scripts/interactBurnable.ts --network testnet
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  // Replace with your deployed contract address
  const contractAddress = "0x78e7051d688333d7FaF89633c047186db22F3d92";

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
  // Need to approve the contract because the burn function
  // uses transferFrom to move the token from owner to the contract address
  let currentApproved = await c.getApproved(1);
  console.log("Current approved for tokenId 1:", currentApproved);
  // Minimal ERC721 ABI for approvals
  // We need to call approve on the actual token contract, not the wrapper
  const erc721 = new ethers.Contract(
    await c.hederaTokenAddress(),
    ["function approve(address to, uint256 tokenId) external"],
    caller
  );
  const approveTx = await erc721.approve(contractAddress, 1, {
    gasLimit: 800_000
  });
  await approveTx.wait();
  console.log("Approved tokenId 1 to contract. Tx:", approveTx.hash);
  currentApproved = await c.getApproved(1);
  console.log("New approved for tokenId 1:", currentApproved);
  // Now burn
  const burnTx = await c.burnOwned(1, { gasLimit: 100_000 });
  await burnTx.wait();
  console.log("Burned tokenId 1. Tx:", burnTx.hash);
}

main().catch(console.error);
