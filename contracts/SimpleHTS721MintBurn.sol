// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/extensions/HTS721MintBurn.sol";
import "./hts/extensions/HTS721Management.sol";

/**
 * @dev Adds supply key driven mint/burn + management operations.
 * Ensure keyMask includes SUPPLY (and other needed keys) during initialize().
 */
contract SimpleHTS721MintBurn is HTS721MintBurn, HTS721Management {
    constructor() HTS721Core() {}

    // Example convenience:
    function mintBase64URI(
        address to,
        string calldata b64Json
    ) external onlyOwner returns (uint256) {
        return this.mintTo(to, bytes(b64Json));
    }
}
