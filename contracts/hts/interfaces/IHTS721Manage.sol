// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface IHTS721Manage {
    // KYC
    function grantKyc(address account) external;
    function revokeKyc(address account) external;

    // Freeze
    function freeze(address account) external;
    function unfreeze(address account) external;

    // Pause
    function pause() external;
    function unpause() external;

    // Wipe NFTs (must supply serials)
    function wipe(address account, int64[] calldata serials) external;

    // Custom fees (Royalty/Fee arrays passed ABI-encoded externally)
    function updateNftRoyaltyFees(
        bytes calldata fixedFeesEncoded,
        bytes calldata royaltyFeesEncoded
    ) external;

    // Delete token (requires ADMIN key + HTS preconditions)
    function deleteToken() external;
}
