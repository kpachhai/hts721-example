// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/HTS721Core.sol";

/**
 * @dev Core-only deployment: just creation + ownership of keys; no management helpers,
 *      no mint/burn, no neutralization. Suited for very small supervisory wrappers.
 */
contract SimpleHTS721 is HTS721Core {
    constructor() HTS721Core() {}
}
