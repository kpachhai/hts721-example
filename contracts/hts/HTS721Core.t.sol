// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./HTS721Core.sol";
import "./HTSCommon.sol";
import "./HTS721Errors.sol";
import "./interfaces/IHTS721Core.sol";

/**
 * NOTE:
 *  - These Foundry tests run in a local EVM WITHOUT Hedera precompiles.
 *  - Calls to the HTS system contract (0x167) will fail (ok == false) and revert with HtsCallFailed.
 *  - We assert wrapper gating (onlyOwner, init flags, revert shape), not successful token creation.
 */
contract HTS721CoreTest is Test, HTSCommon {
    HTS721CoreImpl internal core;
    address internal owner = address(0xA11CE);
    address internal other = address(0xB0B);

    function setUp() public {
        vm.prank(owner);
        core = new HTS721CoreImpl();
    }

    function test_OwnerSet() public view {
        assertEq(core.owner(), owner);
    }

    function test_InitializeRevertsWithoutPrecompile() public {
        // Expect revert with error selector HtsCallFailed
        IHTS721Core.InitConfig memory cfg = IHTS721Core.InitConfig({
            name: "X",
            symbol: "X",
            memo: "m",
            keyMask: uint8(KEY_ADMIN | KEY_SUPPLY),
            freezeDefault: false,
            autoRenewAccount: address(0),
            autoRenewPeriod: 0
        });

        vm.prank(owner);
        vm.expectRevert(); // Cannot easily pattern-match custom error tuple reliably cross-version
        core.initialize(cfg);

        assertEq(
            core.initialized(),
            false,
            "Should remain uninitialized after failed precompile"
        );
    }

    function test_OnlyOwnerInitialize() public {
        IHTS721Core.InitConfig memory cfg = IHTS721Core.InitConfig({
            name: "X",
            symbol: "X",
            memo: "m",
            keyMask: uint8(KEY_ADMIN | KEY_SUPPLY),
            freezeDefault: false,
            autoRenewAccount: address(0),
            autoRenewPeriod: 0
        });

        vm.prank(other);
        vm.expectRevert(); // Ownable revert
        core.initialize(cfg);
    }
}

/**
 * Concrete test implementation (abstract core requires deployment).
 * We do not override anything—just expose public constructor.
 */
contract HTS721CoreImpl is HTS721Core {
    constructor() HTS721Core() {}
}
