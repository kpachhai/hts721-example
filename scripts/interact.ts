import { network } from "hardhat";

// Usage: npx hardhat run scripts/interact.ts --network testnet
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  // Replace with your deployed contract address
  const contractAddress = "0x7700d68a2fa53948Bef8AB9d42a15F04b05Ee024";

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

  // Let's try to transfer using the wrapper contract. This should fail because
  // the wrapper contract does not own the token.
  try {
    const transferTx = await c.transferFrom(
      caller.address,
      "0x4204932a79B59C0B79E460eA34376e5dD833667a",
      1
    );
    await transferTx.wait();
    console.log(
      "Transferred tokenId 1 to a random address. Tx:",
      transferTx.hash
    );
  } catch (e) {
    console.log("Transfer failed as expected. ");
    // Approve the wrapper contract to transfer the token on behalf of the caller
    console.log("Now let's approve first and try again.");

    const erc721 = new ethers.Contract(
      await c.hederaTokenAddress(),
      ["function approve(address to, uint256 tokenId) external"],
      caller
    );
    const approveTx = await erc721.approve(contractAddress, 1, {
      gasLimit: 800_000
    });
    await approveTx.wait();
    console.log("Approved tokenId 1 for caller. Tx:", approveTx.hash);

    const transferTx2 = await c.transferFrom(
      caller.address,
      "0x4204932a79B59C0B79E460eA34376e5dD833667a",
      1,
      { gasLimit: 75_000 }
    );
    await transferTx2.wait();
    console.log(
      "Transferred tokenId 1 to a reandom address after approval. Tx:",
      transferTx2.hash
    );
  }
}

main().catch(console.error);
