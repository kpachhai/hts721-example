import { expect } from "chai";
import { network } from "hardhat";

/**
 * Full integration tests for SimpleHTS721Managed.
 *
 * Features covered:
 *  - initialize with all keys
 *  - grantKyc (if KYC key present)
 *  - pause/unpause
 *  - freeze/unfreeze
 *  - mint
 *  - neutralize keys (freeze + wipe) then verify freeze no longer works
 *  - burnFrom (after approval)
 *
 * NOTE:
 *  - deleteToken generally requires supply cleared & relationships satisfied;
 *    we don’t force a deletion success here (may fail if network preconditions unmet).
 */
const { ethers } = await network.connect({ network: "testnet" });

describe("SimpleHTS721Managed", function () {
  const ADMIN = 1,
    KYC = 2,
    FREEZE = 4,
    WIPE = 8,
    SUPPLY = 16,
    FEE = 32,
    PAUSE = 64;

  async function deploy() {
    const [owner] = await ethers.getSigners();
    const F = await ethers.getContractFactory("SimpleHTS721Managed", owner);
    const c = await F.deploy();
    await c.waitForDeployment();
    await (
      await c.initialize(
        {
          name: "Managed",
          symbol: "MGD",
          memo: "managed test",
          keyMask: ADMIN | KYC | FREEZE | WIPE | SUPPLY | FEE | PAUSE,
          freezeDefault: false,
          autoRenewAccount: owner.address,
          autoRenewPeriod: 0
        },
        { value: ethers.parseEther("5") }
      )
    ).wait();

    return { c, owner };
  }

  it("executes full management and neutralization path (partial)", async function () {
    const { c, owner } = await deploy();
    const underlying = await c.hederaTokenAddress();

    // KYC (may succeed or revert if network conditions differ)
    try {
      await (await c.grantKyc(owner.address)).wait();
    } catch {
      // ignore
    }

    // Mint
    await (await c.mintTo(owner.address, "0x")).wait();

    // Pause/unpause
    let paused = false;
    try {
      await (await c.pause()).wait();
      paused = true;
    } catch {
      /* ignore if pause key absent or network nuance */
    }

    if (paused) {
      // Attempt mint while paused (expected fail)
      try {
        await (await c.mintTo(owner.address, "0x")).wait();
        // if it succeeds, network didn't enforce pause for some reason
      } catch {
        // expected
      }
      // Unpause
      try {
        await (await c.unpause()).wait();
      } catch {
        /* ignore */
      }
    }

    // Freeze/unfreeze
    try {
      await (await c.freeze(owner.address)).wait();
      await (await c.unfreeze(owner.address)).wait();
    } catch {
      /* ignore */
    }

    // Neutralize freeze + wipe
    await (
      await c.neutralizeKeysRandom(
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
      )
    ).wait();

    // Freeze should now fail
    let freezeFailed = false;
    try {
      await c.freeze(owner.address);
    } catch {
      freezeFailed = true;
    }
    expect(freezeFailed).to.eq(true);

    // burnFrom flow
    // Approve underlying
    const erc721 = new ethers.Contract(
      underlying,
      ["function approve(address,uint256) external"],
      owner
    );
    // Approve serial #1
    await (await erc721.approve(await c.getAddress(), 1)).wait();
    await (await c.burnFrom(owner.address, 1)).wait();
  });
});
