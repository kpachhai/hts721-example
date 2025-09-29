// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/**
 * @title IHTS721Core
 * @notice Minimal interface for creating an HTS-based NFT (non-fungible token) via a wrapper contract.
 *         This intentionally omits any ERC-721 passthrough (transfers / approvals / association).
 *
 * Key Mask Bits (match HTSCommon):
 *   1  = ADMIN
 *   2  = KYC
 *   4  = FREEZE
 *   8  = WIPE
 *   16 = SUPPLY
 *   32 = FEE
 *   64 = PAUSE
 *
 * Common keyMask examples:
 *   - Core only (admin):                1
 *   - Mint/Burn (admin + supply):       1 | 16
 *   - Full management (all):            127
 */
interface IHTS721Core {
    /**
     * @dev Packed initialization config (avoids stack-too-deep).
     * autoRenewAccount:
     *   - If zero address, the contract itself is used.
     * autoRenewPeriod:
     *   - If zero, implementation applies a default.
     */
    struct InitConfig {
        string name;
        string symbol;
        string memo;
        uint8 keyMask; // OR of KEY_* flags
        bool freezeDefault;
        address autoRenewAccount;
        int32 autoRenewPeriod;
    }

    /// Returns the underlying HTS token mirror address (valid only after initialize()).
    function hederaTokenAddress() external view returns (address);

    /// True once initialize() has run successfully.
    function initialized() external view returns (bool);

    /**
     * @notice Create the underlying HTS NFT per the supplied configuration.
     * @dev Must revert if already initialized.
     */
    function initialize(InitConfig calldata cfg) external payable;
}
