// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./hts/HTS721.sol";
import {NotAuthorized, LengthMismatch} from "./hts/HTS721Errors.sol";

/**
 * @title SimpleHTS721
 * @notice Minimal, owner-governed HTS721 deployment wrapper (no Enumerable).
 */
contract SimpleHTS721 is HTS721, Ownable {
    event Minted(address indexed to, uint256 indexed tokenId);
    event BatchMinted(address indexed to, uint256 indexed tokenId);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory memo_
    )
        payable
        HTS721(name_, symbol_, memo_, _defaultConfig())
        Ownable(msg.sender)
    {}

    function mintTo(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = _mint(to);
        emit Minted(to, tokenId);
    }

    function mintToWithMetadata(
        address to,
        bytes calldata metadata
    ) external onlyOwner returns (uint256 tokenId) {
        tokenId = _mint(to, metadata);
        emit Minted(to, tokenId);
    }

    function mintBatch(
        address[] calldata tos,
        bytes[] calldata metadatas
    ) external onlyOwner returns (uint256[] memory tokenIds) {
        if (tos.length != metadatas.length) revert LengthMismatch();
        uint256 n = tos.length;
        tokenIds = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 id = _mint(tos[i], metadatas[i]);
            tokenIds[i] = id;
            emit BatchMinted(tos[i], id);
        }
    }

    function _requireManagementAuth() internal view override {
        if (msg.sender != owner()) revert NotAuthorized();
    }

    function _defaultConfig()
        internal
        view
        returns (ManagementConfig memory cfg)
    {
        cfg.controller = address(this);
        cfg.admin = true;
        cfg.kyc = true;
        cfg.freeze = true;
        cfg.wipe = true;
        cfg.supply = true;
        cfg.feeSchedule = true;
        cfg.pause = true;

        cfg.treasury = address(this);
        cfg.freezeDefault = false;

        cfg.autoRenewAccount = msg.sender;
        cfg.autoRenewPeriod = int32(0); // base uses default when 0
    }
}
