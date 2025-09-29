import { network } from "hardhat";

/**
 * Interacts with SimpleHTS721Managed:
 *  - User association (underlying)
 *  - grantKyc / freeze / pause
 *  - mint, neutralize keys, burnFrom, delete attempt
 *
 * Usage: npx hardhat run scripts/interact_managed.ts --network testnet
 */
const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const contractAddress = "0xAf59D38509b5e6E064Aa41c3B19b07CDB71B4432"; // replace with your deployed managed contract address

  const [owner] = await ethers.getSigners();
  console.log("Owner:", owner.address);
  console.log("Managed contract:", contractAddress);

  const c = await ethers.getContractAt(
    "SimpleHTS721Managed",
    contractAddress,
    owner
  );
  const underlying = await c.hederaTokenAddress();
  console.log("Underlying HTS token:", underlying);

  // User associates directly with underlying token (IHRC719 associate())
  const userAssociate = new ethers.Contract(
    underlying,
    ["function associate() external returns (int32)"],
    owner
  );
  try {
    const assoc = await userAssociate.associate({ gasLimit: 800_000 });
    await assoc.wait();
    console.log("User associated underlying token:", assoc.hash);
  } catch (e: any) {
    console.log(
      "Associate skipped/failure (maybe already associated):",
      e.message || e
    );
  }

  // grantKyc (if KYC key present)
  try {
    const kycTx = await c.grantKyc(owner.address);
    await kycTx.wait();
    console.log("Granted KYC:", kycTx.hash);
  } catch (e: any) {
    console.log("grantKyc failed or not needed:", e.message || e);
  }

  // Mint serial #1 to user
  const mint1 = await c.mintTo(owner.address, "0x");
  await mint1.wait();
  console.log("Minted serial #1 to user:", mint1.hash);

  // Pause
  let paused = false;
  try {
    const p = await c.pause();
    await p.wait();
    paused = true;
    console.log("Paused collection:", p.hash);
  } catch (e: any) {
    console.log("pause() failed or key missing:", e.message || e);
  }

  // Attempt mint during pause (expect fail if paused)
  if (paused) {
    try {
      const m2 = await c.mintTo(owner.address, "0x");
      await m2.wait();
      console.log("Unexpected: mint succeeded while paused.");
    } catch {
      console.log("Mint while paused failed (expected).");
    }
  }

  // Unpause
  if (paused) {
    try {
      const up = await c.unpause();
      await up.wait();
      console.log("Unpaused:", up.hash);
    } catch (e: any) {
      console.log("unpause failed:", e.message || e);
    }
  }

  // Freeze/unfreeze user (if FREEZE key)
  try {
    const fr = await c.freeze(owner.address);
    await fr.wait();
    console.log("Froze user:", fr.hash);

    const uf = await c.unfreeze(owner.address);
    await uf.wait();
    console.log("Unfroze user:", uf.hash);
  } catch (e: any) {
    console.log("freeze/unfreeze skipped:", e.message || e);
  }

  // Neutralize wipe + freeze keys
  const neut = await c.neutralizeKeysRandom(
    {
      admin: false,
      kyc: false,
      freeze: true,
      wipe: true,
      supply: false,
      fee: false,
      pause: false
    },
    false
  );
  await neut.wait();
  console.log("Neutralized freeze & wipe keys:", neut.hash);

  // Try freeze again (should fail)
  try {
    await c.freeze(owner.address);
    console.log("Unexpected: freeze succeeded after neutralization.");
  } catch {
    console.log("freeze failed post-neutralization (expected).");
  }

  // burnFrom serial #1 (user must approve wrapper)
  const userToken = new ethers.Contract(
    underlying,
    ["function approve(address,uint256) external"],
    owner
  );
  await userToken.approve(contractAddress, 1);
  const burn1 = await c.burnFrom(owner.address, 1);
  await burn1.wait();
  console.log("burnFrom #1 complete:", burn1.hash);

  // Attempt deleteToken (will only succeed if all conditions satisfied)
  try {
    const del = await c.deleteToken();
    await del.wait();
    console.log("Token deleted:", del.hash);
  } catch (e: any) {
    console.log("deleteToken failed (likely expected):", e.message || e);
  }

  console.log("Managed interaction complete.");
}

main().catch(console.error);
