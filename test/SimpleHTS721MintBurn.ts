import { expect } from "chai";
import { network } from "hardhat";

/**
 * Integration tests for SimpleHTS721MintBurn (Mint/Burn only).
 * Run on Hedera testnet.
 *
 * Covers:
 *  - initialize
 *  - mintTo
 *  - burnFrom flow (requires underlying approval)
 */
const { ethers } = await network.connect({ network: "testnet" });

describe("SimpleHTS721MintBurn", function () {
  const ADMIN = 1;
  const SUPPLY = 16;

  async function deploy() {
    const [owner, user] = await ethers.getSigners();
    const F = await ethers.getContractFactory("SimpleHTS721MintBurn", owner);
    const c = await F.deploy();
    await c.waitForDeployment();
    await (
      await c.initialize(
        {
          name: "MintBurn",
          symbol: "MB",
          memo: "mint burn test",
          keyMask: ADMIN | SUPPLY,
          freezeDefault: false,
          autoRenewAccount: owner.address,
          autoRenewPeriod: 0
        },
        { value: ethers.parseEther("5") }
      )
    ).wait();

    return { c, owner, user };
  }

  it("mints and burns a serial (burnFrom pulls after approval)", async function () {
    const { c, owner } = await deploy();
    const underlying = await c.hederaTokenAddress();

    // Mint #1 to owner
    const mintTx = await c.mintTo(owner.address, "0x");
    await mintTx.wait();

    // Attempt burnFrom without approval -> expect revert
    await expect(c.burnFrom(owner.address, 1)).to.be.reverted;

    // Approve wrapper on underlying
    const erc721 = new ethers.Contract(
      underlying,
      ["function approve(address,uint256) external"],
      owner
    );
    await (await erc721.approve(await c.getAddress(), 1)).wait();

    // Now burnFrom succeeds
    await (await c.burnFrom(owner.address, 1)).wait();
  });
});
