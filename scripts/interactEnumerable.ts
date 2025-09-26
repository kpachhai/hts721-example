import { network } from "hardhat";

// Usage: npx hardhat run scripts/interactEnumerable.ts --network testnet
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  // Replace with your deployed contract address
  const contractAddress = "0x7B25813e06B9195e081D3C6728933c54d581b146";

  const [caller] = await ethers.getSigners();
  console.log("Caller:", caller.address);
  console.log("Contract:", contractAddress);

  const c = await ethers.getContractAt(
    "SimpleHTS721Enumerable",
    contractAddress,
    caller
  );

  // Mint a few tokens
  // Mint new token
  // First, need to associate the token with caller's account on Hedera
  const assocTx = await c.associate();
  await assocTx.wait();
  console.log("Associated token with caller's account. Tx:", assocTx.hash);

  // Now mint
  for (let i = 0; i < 3; i++) {
    const tx = await c.mintTo(caller.address, "0x", {
      gasLimit: 400_000
    });
    await tx.wait();
    console.log(`Minted #${i + 1} tx:`, tx.hash);
  }

  const total = await c.totalSupply();
  console.log("totalSupply:", total.toString());

  for (let i = 0; i < Number(total); i++) {
    const tokenId = await c.tokenByIndex(i);
    console.log("tokenByIndex", i, "=>", tokenId.toString());
  }
}

main().catch(console.error);
