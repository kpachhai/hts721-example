// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/HTS721Initializable.sol";
import "./hts/extensions/HTS721Enumerable.sol";

contract SimpleHTS721Enumerable is HTS721Initializable, HTS721Enumerable {
    constructor() HTS721Initializable() {}

    function mintTo(
        address to,
        bytes calldata metadata
    ) external onlyOwner returns (uint256) {
        return _mint(to, metadata);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(HTS721Initializable, HTS721Enumerable)
        returns (bool)
    {
        return HTS721Enumerable.supportsInterface(interfaceId);
    }
}
