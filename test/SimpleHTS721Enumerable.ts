import { expect } from "chai";
import { network } from "hardhat";

/**
 * Integration tests for SimpleHTSEnumerable.
 * - Mint several tokens
 * - tokenByIndex enumeration
 * - tokensOfOwner
 *
 * CAUTION: Only suitable for small enumerations; naive scan logic.
 */
const { ethers } = await network.connect({ network: "testnet" });

describe("SimpleHTS721Enumerable", function () {
  const ADMIN = 1,
    SUPPLY = 16,
    FREEZE = 4,
    PAUSE = 64;

  async function deploy() {
    const [owner] = await ethers.getSigners();
    const F = await ethers.getContractFactory("SimpleHTS721Enumerable", owner);
    const c = await F.deploy();
    await c.waitForDeployment();
    await (
      await c.initialize(
        {
          name: "EnumTest",
          symbol: "ENUM",
          memo: "enumeration test",
          keyMask: ADMIN | SUPPLY | FREEZE | PAUSE,
          freezeDefault: false,
          autoRenewAccount: owner.address,
          autoRenewPeriod: 0
        },
        { value: ethers.parseEther("5") }
      )
    ).wait();
    return { c, owner };
  }

  it("enumerates first few serials", async function () {
    const { c, owner } = await deploy();

    for (let i = 0; i < 3; i++) {
      await (await c.mintTo(owner.address, "0x")).wait();
    }

    // tokenByIndex
    for (let i = 0; i < 3; i++) {
      const serial = await c.tokenByIndex(i);
      expect(Number(serial)).to.equal(i + 1);
    }

    // tokensOfOwner
    const tokens = await c.tokensOfOwner(owner.address, 10);
    expect(tokens.length).to.equal(3);
  });
});
