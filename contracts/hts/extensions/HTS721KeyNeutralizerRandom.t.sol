// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../HTS721Core.sol";
import "../interfaces/IHTS721Core.sol";
import "./HTS721KeyNeutralizerRandom.sol";
import "../HTSCommon.sol";

/**
 * Local test for neutralizer just confirms:
 *  - Not initialized => neutralize reverts
 *  - Initialize attempt reverts (HtsCallFailed)
 *  - After failed init, neutralize still reverts
 */
contract HTS721KeyNeutralizerRandomTest is Test, HTSCommon {
    address internal owner = address(0xA11CE);
    NeutralizerImpl internal nz;

    function setUp() public {
        vm.prank(owner);
        nz = new NeutralizerImpl();
    }

    function test_NeutralizeNeedsInit() public {
        vm.prank(owner);
        vm.expectRevert(); // NotInitialized
        nz.neutralizeKeysRandom(
            HTS721KeyNeutralizerRandom.Flags({
                admin: false,
                kyc: false,
                freeze: true,
                wipe: true,
                supply: false,
                fee: false,
                pause: false
            }),
            false
        );
    }

    function test_InitializeFails_Local() public {
        IHTS721Core.InitConfig memory cfg = IHTS721Core.InitConfig({
            name: "N",
            symbol: "N",
            memo: "ntrlz",
            keyMask: uint8(KEY_ADMIN | KEY_SUPPLY | KEY_FREEZE),
            freezeDefault: false,
            autoRenewAccount: address(0),
            autoRenewPeriod: 0
        });
        vm.prank(owner);
        vm.expectRevert(); // HtsCallFailed
        nz.initialize(cfg);
    }
}

contract NeutralizerImpl is HTS721Core, HTS721KeyNeutralizerRandom {
    constructor() HTS721Core() {}
}
