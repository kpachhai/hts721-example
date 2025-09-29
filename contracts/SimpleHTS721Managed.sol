// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/extensions/HTS721MintBurn.sol";
import "./hts/extensions/HTS721Management.sol";
import "./hts/extensions/HTS721KeyNeutralizerRandom.sol";

/**
 * @dev Full-feature example: mint/burn + management + key neutralization.
 * Pick keyMask in initialize to include required keys (e.g. ADMIN | SUPPLY | PAUSE | FREEZE | WIPE).
 */
contract SimpleHTS721Managed is
    HTS721MintBurn,
    HTS721Management,
    HTS721KeyNeutralizerRandom
{
    constructor() HTS721Core() {}
}
