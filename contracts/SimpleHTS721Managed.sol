// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/HTS721Initializable.sol";
import "./hts/extensions/HTS721Management.sol";

contract SimpleHTS721Managed is HTS721Initializable, HTS721Management {
    constructor() HTS721Initializable() {}

    function mintTo(
        address to,
        bytes calldata metadata
    ) external onlyOwner returns (uint256) {
        return _mint(to, metadata);
    }
}
