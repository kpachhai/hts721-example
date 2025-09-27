import { network } from "hardhat";

// Usage: npx hardhat run scripts/interactManaged.ts --network testnet
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  // Replace with your deployed contract address
  const contractAddress = "0x6a59eA7DC16f25F8e47582c852fc50292Fc11c33";

  const [owner] = await ethers.getSigners();
  console.log("Owner:", owner.address);
  console.log("Managed contract:", contractAddress);
  const c = await ethers.getContractAt(
    "SimpleHTS721Managed",
    contractAddress,
    owner
  );

  // 1. Grant KYC to owner (if KYC key exists and required)
  //try {
  const kycTx = await c.grantKyc(owner.address, { gasLimit: 75_000 });
  await kycTx.wait();
  console.log("Granted KYC to owner. Tx:", kycTx.hash);
  /*   } catch (e) {
    console.log(
      "GrantKyc skipped or failed (maybe KYC key absent or not required):",
      (e as any).message
    );
  } */

  // 2. Mint first token
  // First, need to associate the token with caller's account on Hedera
  const assocTx = await c.associate();
  await assocTx.wait();
  console.log("Associated token with caller's account. Tx:", assocTx.hash);
  // Now mint
  const mint1 = await c.mintTo(owner.address, "0x", {
    gasLimit: 400_000
  });
  await mint1.wait();
  console.log("Minted tokenId 1. Tx:", mint1.hash);

  // 3. Pause the token
  try {
    const pauseTx = await c.pause();
    await pauseTx.wait();
    console.log("Paused token. Tx:", pauseTx.hash);
  } catch (e) {
    console.log(
      "Pause failed (pause key might not exist):",
      (e as any).message
    );
  }

  // 4. Attempt second mint while paused (expect failure if pause key works)
  let pausedMintFailed = false;
  try {
    const mintWhilePaused = await c.mintTo(owner.address, "0x", {
      gasLimit: 400_000
    });
    await mintWhilePaused.wait();
    console.log("Unexpected: Mint succeeded while paused.");
  } catch {
    pausedMintFailed = true;
    console.log("Mint while paused failed as expected.");
  }

  // 5. Unpause
  if (pausedMintFailed) {
    try {
      const unpauseTx = await c.unpause();
      await unpauseTx.wait();
      console.log("Unpaused token. Tx:", unpauseTx.hash);
    } catch (e) {
      console.log("Unpause failed:", (e as any).message);
    }
  }

  // 6. Mint second token
  const mint2 = await c.mintTo(owner.address, "0x", {
    gasLimit: 400_000
  });
  await mint2.wait();
  console.log("Minted tokenId 2. Tx:", mint2.hash);

  // 7. Freeze & unfreeze owner (if freeze key present)
  try {
    const freezeTx = await c.freeze(owner.address);
    await freezeTx.wait();
    console.log("Froze owner. Tx:", freezeTx.hash);

    const unfreezeTx = await c.unfreeze(owner.address);
    await unfreezeTx.wait();
    console.log("Unfroze owner. Tx:", unfreezeTx.hash);
  } catch (e) {
    console.log("Freeze/unfreeze skipped:", (e as any).message);
  }

  // 8. Demonstrate dropping keys (e.g., drop freeze and wipe for decentralization)
  try {
    const dropTx = await c.dropKeys({
      admin: false,
      kyc: false,
      freeze: true,
      wipe: true,
      supply: false,
      fee: false,
      pause: false
    });
    await dropTx.wait();
    console.log("Dropped freeze & wipe keys. Tx:", dropTx.hash);
  } catch (e) {
    console.log("dropKeys failed:", (e as any).message);
  }

  console.log("Managed interaction demo complete.");
}

main().catch(console.error);
