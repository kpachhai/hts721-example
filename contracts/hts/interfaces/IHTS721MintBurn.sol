// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface IHTS721MintBurn {
    function mintTo(
        address to,
        bytes calldata metadata
    ) external returns (uint256);
    function burn(uint256 serial) external;
    function burnFrom(address owner, uint256 serial) external;
}
