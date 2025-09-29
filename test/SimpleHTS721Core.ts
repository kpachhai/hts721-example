import { expect } from "chai";
import { network } from "hardhat";

/**
 * Integration tests for SimpleHTS721 (Core only).
 * These MUST be run against Hedera testnet (or a network that supports HTS precompiles).
 *
 * Usage:
 *   npx hardhat test test/SimpleHTS721Core.ts --network testnet
 *
 * NOTE:
 * - Core contract has no mint/burn/management functions.
 * - We only verify initialization and immutability (second initialize reverts).
 */
const { ethers } = await network.connect({ network: "testnet" });

describe("SimpleHTS721 (Core)", function () {
  const ADMIN = 1;
  const SUPPLY = 16;

  async function deployCore() {
    const [owner] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("SimpleHTS721", owner);
    const c = await Factory.deploy();
    await c.waitForDeployment();
    return { c, owner };
  }

  it("initializes underlying token exactly once", async function () {
    const { c, owner } = await deployCore();

    const init = await c.initialize(
      {
        name: "Core",
        symbol: "CORE",
        memo: "core test",
        keyMask: ADMIN | SUPPLY,
        freezeDefault: false,
        autoRenewAccount: owner.address,
        autoRenewPeriod: 0
      },
      {
        value: ethers.parseEther("5")
      }
    );
    await init.wait();

    const tokenAddr = await c.hederaTokenAddress();
    expect(tokenAddr).to.properAddress;
    expect(await c.initialized()).to.eq(true);

    // Re-initialize should revert (custom error AlreadyInitialized)
    await expect(
      c.initialize({
        name: "X",
        symbol: "X",
        memo: "x",
        keyMask: ADMIN | SUPPLY,
        freezeDefault: false,
        autoRenewAccount: owner.address,
        autoRenewPeriod: 0
      })
    ).to.be.reverted; // cannot easily pattern-match custom error signature in TS yet
  });
});
