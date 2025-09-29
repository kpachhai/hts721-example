// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/HTS721Initializable.sol";
import "./hts/extensions/HTS721Management.sol";
import "./hts/extensions/HTS721KeyNeutralizerRandom.sol";

/**
 * @title SimpleHTS721Managed
 * @notice Example managed HTS721 implementation with:
 *         - Two-phase initialization
 *         - Management (KYC / Freeze / Pause / Wipe / Fees)
 *         - Key neutralization via PRNG-based random Ed25519 rotation
 *
 * Usage Notes:
 *  - initialize(...) must be called once by owner after deployment.
 *  - addKeys(...) can introduce additional keys bound to this contract.
 *  - neutralizeKeysRandom(...) (from HTS721KeyNeutralizerRandom) irreversibly disables selected keys.
 *  - dropKeys(...) on the base is deprecated (no-op) to avoid INVALID_OPERATION errors from HTS.
 *  - Minting: owner calls mintTo() — user can later transfer natively or delegated via wrapper after approval.
 */
contract SimpleHTS721Managed is
    HTS721Initializable,
    HTS721Management,
    HTS721KeyNeutralizerRandom
{
    constructor() HTS721Initializable() {}

    function mintTo(
        address to,
        bytes calldata metadata
    ) external onlyOwner returns (uint256) {
        return _mint(to, metadata);
    }
}
