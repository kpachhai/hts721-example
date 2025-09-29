import { network } from "hardhat";

/**
 * Interacts with SimpleHTS721MintBurn:
 *  - Mint to users
 *  - Attempt burnFrom without approval
 *  - Approve & burnFrom
 *  - Direct burn (treasury-owned scenario simulated via pull)
 *
 * Usage: npx hardhat run scripts/interact_mint_burn.ts --network testnet
 */
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const contractAddress = "0x5e1c2E82C8BDB565c41F4452102b67F479ad5025"; // replace with your deployed mint/burn contract address

  const [owner] = await ethers.getSigners();
  console.log("Owner:", owner.address);
  console.log("MintBurn contract:", contractAddress);

  const c = await ethers.getContractAt(
    "SimpleHTS721MintBurn",
    contractAddress,
    owner
  );
  const underlying = await c.hederaTokenAddress();
  console.log("Underlying HTS token:", underlying);

  // Mint #1 to owner and burn via burnFrom
  const tx1 = await c.mintTo(owner.address, "0x");
  await tx1.wait();
  console.log("Minted serial #1 to owner:", tx1.hash);

  // Attempt burnFrom (should fail, no approval)
  try {
    await c.burnFrom(owner.address, 1);
    console.log("Unexpected: burnFrom succeeded without approval.");
  } catch {
    console.log("burnFrom failed (no approval) as expected.");
  }

  // Owner approves wrapper (still needed because wrapper pulls)
  const ownerToken = new ethers.Contract(
    underlying,
    ["function approve(address,uint256) external"],
    owner
  );
  await ownerToken.approve(contractAddress, 1);

  const burn1 = await c.burnFrom(owner.address, 1);
  await burn1.wait();
  console.log("Burned serial #1:", burn1.hash);

  console.log("Mint/Burn interaction complete.");
}

main().catch(console.error);
