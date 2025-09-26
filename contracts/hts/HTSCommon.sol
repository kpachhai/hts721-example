// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

abstract contract HTSCommon {
    // Hedera Token Service (v1) system contract address
    address internal constant HTS_PRECOMPILE_ADDRESS = address(0x167);

    // Common response codes
    int32 internal constant SUCCESS = 22;
    int32 internal constant TOKEN_ALREADY_ASSOCIATED = 194;
    int32 internal constant TOKEN_NOT_ASSOCIATED = 184;

    // Key bit masks (one per key type for clarity)
    uint256 internal constant KEY_ADMIN = 1;
    uint256 internal constant KEY_KYC = 2;
    uint256 internal constant KEY_FREEZE = 4;
    uint256 internal constant KEY_WIPE = 8;
    uint256 internal constant KEY_SUPPLY = 16;
    uint256 internal constant KEY_FEE = 32;
    uint256 internal constant KEY_PAUSE = 64;
}
