import { expect } from "chai";
import { network } from "hardhat";

/**
 * Comprehensive integration tests for SimpleHTS721 (Core only).
 * Run against Hedera testnet:
 *   npx hardhat test test/SimpleHTS721Core.ts --network testnet
 *
 * This contract only supports initialize(); no mint / management / neutralization.
 */
const { ethers } = await network.connect({ network: "testnet" });

describe("SimpleHTS721 (Core Only)", function () {
  const ADMIN = 1;
  const SUPPLY = 16; // required by HTS
  const KEY_MASK = ADMIN | SUPPLY;

  async function deploy() {
    const [owner, other] = await ethers.getSigners();
    const F = await ethers.getContractFactory("SimpleHTS721", owner);
    const c = await F.deploy();
    await c.waitForDeployment();
    return { c, owner, other };
  }

  it("initializes once and sets underlying token address", async () => {
    const { c, owner } = await deploy();
    const tx = await c.initialize(
      {
        name: "CoreToken",
        symbol: "CORE",
        memo: "core test",
        keyMask: KEY_MASK,
        freezeDefault: false,
        autoRenewAccount: owner.address,
        autoRenewPeriod: 0
      },
      {
        value: ethers.parseEther("5")
      }
    );
    await tx.wait();

    const token = await c.hederaTokenAddress();
    expect(token).to.properAddress;
    expect(await c.initialized()).to.eq(true);
  });

  it("rejects double initialization", async () => {
    const { c, owner } = await deploy();
    await (
      await c.initialize(
        {
          name: "A",
          symbol: "A",
          memo: "a",
          keyMask: KEY_MASK,
          freezeDefault: false,
          autoRenewAccount: owner.address,
          autoRenewPeriod: 0
        },
        { value: ethers.parseEther("5") }
      )
    ).wait();

    await expect(
      c.initialize({
        name: "B",
        symbol: "B",
        memo: "b",
        keyMask: KEY_MASK,
        freezeDefault: false,
        autoRenewAccount: owner.address,
        autoRenewPeriod: 0
      })
    ).to.be.reverted;
  });

  it("enforces onlyOwner on initialize", async () => {
    const { c, other, owner } = await deploy();
    await expect(
      c.connect(other).initialize({
        name: "X",
        symbol: "X",
        memo: "x",
        keyMask: KEY_MASK,
        freezeDefault: false,
        autoRenewAccount: owner.address,
        autoRenewPeriod: 0
      })
    ).to.be.reverted;
  });

  it("cannot mint or manage (surface is minimal)", async () => {
    const { c, owner } = await deploy();
    await (
      await c.initialize(
        {
          name: "CoreToken",
          symbol: "CORE",
          memo: "core test",
          keyMask: KEY_MASK,
          freezeDefault: false,
          autoRenewAccount: owner.address,
          autoRenewPeriod: 0
        },
        { value: ethers.parseEther("5") }
      )
    ).wait();

    // @ts-ignore deliberate negative test
    await expect(c.mintTo(owner.address, "0x")).to.be.reverted;
    // @ts-ignore
    await expect(c.pause()).to.be.reverted;
  });
});
