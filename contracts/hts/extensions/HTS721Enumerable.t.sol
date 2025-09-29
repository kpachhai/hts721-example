// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../HTS721Core.sol";
import "../interfaces/IHTS721Core.sol";
import "./HTS721Enumerable.sol";
import "./HTS721MintBurn.sol";
import "../HTSCommon.sol";

/**
 * Local enumeration test:
 *  - Initialization fails (HTS absent)
 *  - tokenByIndex / tokensOfOwner revert due to NotInitialized
 */
contract HTS721EnumerableLocalTest is Test, HTSCommon {
    address internal owner = address(0xA11CE);
    EnumImpl internal en;

    function setUp() public {
        vm.prank(owner);
        en = new EnumImpl();
    }

    function test_EnumerationBeforeInit() public {
        vm.expectRevert(); // NotInitialized
        en.tokenByIndex(0);

        vm.expectRevert();
        en.tokensOfOwner(owner, 10);
    }

    function test_InitFailsLocal() public {
        IHTS721Core.InitConfig memory cfg = IHTS721Core.InitConfig({
            name: "E",
            symbol: "E",
            memo: "enum",
            keyMask: uint8(KEY_ADMIN | KEY_SUPPLY),
            freezeDefault: false,
            autoRenewAccount: address(0),
            autoRenewPeriod: 0
        });
        vm.prank(owner);
        vm.expectRevert();
        en.initialize(cfg);
    }
}

contract EnumImpl is HTS721Core, HTS721MintBurn, HTS721Enumerable {
    constructor() HTS721Core() {}
}
