// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/HTS721Initializable.sol";
import "./hts/extensions/HTS721Burnable.sol";

contract SimpleHTS721Burnable is HTS721Initializable, HTS721Burnable {
    constructor() HTS721Initializable() {}

    function mintTo(
        address to,
        bytes calldata metadata
    ) external onlyOwner returns (uint256) {
        return _mint(to, metadata);
    }

    function burnOwned(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }
}
