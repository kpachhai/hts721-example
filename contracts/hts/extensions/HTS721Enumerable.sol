// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Initializable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {EnumerationTooCostly, IndexOutOfBounds, HtsCallFailed} from "../HTS721Errors.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";

abstract contract HTS721Enumerable is HTS721Initializable, IERC721Enumerable {
    uint256 public enumerationScanLimit = 10_000;
    uint256 internal constant ENUMERATION_HARD_CAP = 1_000_000;

    event EnumerationScanLimitUpdated(uint256 prev, uint256 next);

    function setEnumerationScanLimit(uint256 newLimit) external onlyOwner {
        if (newLimit == 0 || newLimit > ENUMERATION_HARD_CAP)
            revert EnumerationTooCostly();
        uint256 prev = enumerationScanLimit;
        enumerationScanLimit = newLimit;
        emit EnumerationScanLimitUpdated(prev, newLimit);
    }

    function totalSupply()
        public
        view
        override
        onlyInitialized
        returns (uint256)
    {
        return IERC721Enumerable(hederaTokenAddress).totalSupply();
    }

    function tokenByIndex(
        uint256 index
    ) public view override onlyInitialized returns (uint256) {
        uint256 ts = totalSupply();
        if (index >= ts) revert IndexOutOfBounds();
        if (_lastMintedSerial > enumerationScanLimit)
            revert EnumerationTooCostly();
        uint256 count;
        for (uint256 serial = 1; serial <= _lastMintedSerial; serial++) {
            try IERC721(hederaTokenAddress).ownerOf(serial) returns (
                address o
            ) {
                if (o != address(0)) {
                    if (count == index) return serial;
                    unchecked {
                        ++count;
                    }
                }
            } catch {}
        }
        revert IndexOutOfBounds();
    }

    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) public view override onlyInitialized returns (uint256) {
        if (_lastMintedSerial > enumerationScanLimit)
            revert EnumerationTooCostly();
        uint256 count;
        for (uint256 serial = 1; serial <= _lastMintedSerial; serial++) {
            try IERC721(hederaTokenAddress).ownerOf(serial) returns (
                address o
            ) {
                if (o == owner) {
                    if (count == index) return serial;
                    unchecked {
                        ++count;
                    }
                }
            } catch {}
        }
        revert IndexOutOfBounds();
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(HTS721Initializable, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC721Enumerable).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
