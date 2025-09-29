// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../HTSCommon.sol";
import "../HTS721Errors.sol";
import "../HTS721Core.sol";
import "../interfaces/IHTS721Core.sol";
import "./HTS721Management.sol";

/**
 * Local test verifying onlyOwner gating for management calls BEFORE any successful HTS creation.
 * All HTS touching calls revert with HtsCallFailed (no system precompile).
 */
contract HTS721ManagementTest is Test, HTSCommon {
    address internal owner = address(0xA11CE);
    address internal user = address(0xB0B);
    Managed internal mgr;

    function setUp() public {
        vm.prank(owner);
        mgr = new Managed();
    }

    function test_ManagementOnlyOwner() public {
        // Attempt freeze from non-owner
        vm.prank(user);
        vm.expectRevert();
        mgr.freeze(user);
    }

    function test_InitializeThenGrantKyc_RevertsOnHTS() public {
        IHTS721Core.InitConfig memory cfg = IHTS721Core.InitConfig({
            name: "M",
            symbol: "M",
            memo: "test",
            keyMask: uint8(KEY_ADMIN | KEY_KYC | KEY_SUPPLY),
            freezeDefault: false,
            autoRenewAccount: address(0),
            autoRenewPeriod: 0
        });
        vm.prank(owner);
        vm.expectRevert(); // HtsCallFailed
        mgr.initialize(cfg);

        // Not initialized: grantKyc still fails (NotInitialized or HtsCallFailed path)
        vm.prank(owner);
        vm.expectRevert();
        mgr.grantKyc(user);
    }
}

contract Managed is HTS721Core, HTS721Management {
    constructor() HTS721Core() {}
}
