// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../HTS721Core.sol";
import "../interfaces/IHTS721Core.sol";
import "./HTS721MintBurn.sol";
import "../HTSCommon.sol";

/**
 * Tests gating & revert semantics for MintBurn extension locally.
 * HTS calls revert due to absent precompile (expected).
 */
contract HTS721MintBurnTest is Test, HTSCommon {
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    MintBurnImpl internal mb;

    function setUp() public {
        vm.prank(owner);
        mb = new MintBurnImpl();
    }

    function test_MintRequiresInitialized() public {
        vm.prank(owner);
        vm.expectRevert(); // NotInitialized or HtsCallFailed after attempt
        mb.mintTo(user, bytes(""));

        IHTS721Core.InitConfig memory cfg = IHTS721Core.InitConfig({
            name: "MB",
            symbol: "MB",
            memo: "mintburn",
            keyMask: uint8(KEY_ADMIN | KEY_SUPPLY),
            freezeDefault: false,
            autoRenewAccount: address(0),
            autoRenewPeriod: 0
        });

        vm.prank(owner);
        vm.expectRevert(); // creation fails
        mb.initialize(cfg);
    }

    function test_BurnRequiresOwner() public {
        vm.expectRevert();
        mb.burn(1);
    }
}

contract MintBurnImpl is HTS721Core, HTS721MintBurn {
    constructor() HTS721Core() {}
}
