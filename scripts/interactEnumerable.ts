import { network } from "hardhat";

/**
 * Interacts with SimpleHTSEnumerable:
 *  - Mint several tokens
 *  - Enumerate via tokenByIndex
 *  - tokensOfOwner sampling
 *  - Underlying transfer effect on enumeration
 *
 * Usage: npx hardhat run scripts/interact_enumerable.ts --network testnet
 */
const { ethers } = await network.connect({ network: "testnet" });

const CONTRACT_NAME = "SimpleHTS721Enumerable";

async function main() {
  const contractAddress = "0xaC0828a087CAb75eb371DD81EB06045049e9d2eA"; // replace with your deployed mint/burn contract address
  const [owner] = await ethers.getSigners();

  console.log("Owner:", owner.address);
  console.log(`${CONTRACT_NAME}:`, contractAddress);

  const c = await ethers.getContractAt(CONTRACT_NAME, contractAddress, owner);
  const underlying = await c.hederaTokenAddress();
  console.log("Underlying HTS token:", underlying);

  // Mint 3 to owner
  for (let i = 0; i < 3; i++) {
    const tx = await c.mintTo(owner.address, "0x");
    await tx.wait();
    console.log(`Minted serial #${i + 1} to owner:`, tx.hash);
  }

  // Enumerate first 3 (tokenByIndex)
  for (let i = 0; i < 3; i++) {
    try {
      const id = await c.tokenByIndex(i);
      console.log(`tokenByIndex(${i}) => serial ${id.toString()}`);
    } catch {
      console.log(`tokenByIndex(${i}) failed (stop).`);
      break;
    }
  }

  // tokensOfOwner for owner (scan limit example: 50)
  const tokensA = await c.tokensOfOwner(owner.address, 50);
  console.log(
    "tokensOfOwner(owner):",
    tokensA.map((x: any) => x.toString())
  );

  // Optional pause test (if PAUSE key included)
  try {
    const p = await c.pause();
    await p.wait();
    console.log("Paused collection:", p.hash);
  } catch (e: any) {
    console.log("pause() failed or not keyed:", e.message || e);
  }

  console.log("Enumerable interaction complete.");
}

main().catch(console.error);
