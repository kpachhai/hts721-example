// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "./hts/HTS721Initializable.sol";

contract SimpleHTS721 is HTS721Initializable {
    constructor() HTS721Initializable() {}

    function mintTo(
        address to,
        bytes calldata metadata
    ) external onlyOwner returns (uint256) {
        return _mint(to, metadata);
    }

    function mintBatch(
        address[] calldata tos,
        bytes[] calldata metadatas
    ) external onlyOwner returns (uint256[] memory tokenIds) {
        if (!initialized) revert NotInitialized();
        if (tos.length != metadatas.length) revert LengthMismatch();
        uint256 n = tos.length;
        tokenIds = new uint256[](n);
        for (uint256 i; i < n; i++) {
            tokenIds[i] = _mint(tos[i], metadatas[i]);
        }
    }
}
