// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Core.sol";
import "../HTS721Errors.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @dev Provides naive enumeration by scanning serials up to _lastSerial.
 * Use ONLY for small collections; supply growth => raise EnumerationTooCostly.
 */
abstract contract HTS721Enumerable is HTS721Core {
    uint256 public enumerationScanLimit = 10_000;
    uint256 internal constant ENUM_HARD_CAP = 1_000_000;
    event EnumerationScanLimitUpdated(uint256 prev, uint256 next);

    function setEnumerationScanLimit(uint256 newLimit) external onlyOwner {
        if (newLimit == 0 || newLimit > ENUM_HARD_CAP)
            revert EnumerationTooCostly();
        uint256 prev = enumerationScanLimit;
        enumerationScanLimit = newLimit;
        emit EnumerationScanLimitUpdated(prev, newLimit);
    }

    function totalMinted() external view returns (uint256) {
        return _lastSerial;
    }

    // O(n) scan; do not use for large n on-chain.
    function tokenByIndex(uint256 index) external view returns (uint256) {
        if (_lastSerial > enumerationScanLimit) revert EnumerationTooCostly();
        uint256 count;
        for (uint256 s = 1; s <= _lastSerial; s++) {
            try IERC721(hederaTokenAddress).ownerOf(s) returns (address o) {
                if (o != address(0)) {
                    if (count == index) return s;
                    unchecked {
                        ++count;
                    }
                }
            } catch {}
        }
        revert IndexOutOfBounds();
    }

    function tokensOfOwner(
        address owner,
        uint256 maxScan
    ) external view returns (uint256[] memory found) {
        if (_lastSerial > enumerationScanLimit) revert EnumerationTooCostly();
        if (maxScan == 0 || maxScan > _lastSerial) maxScan = _lastSerial;
        uint256[] memory tmp = new uint256[](maxScan);
        uint256 k;
        for (uint256 s = 1; s <= maxScan; s++) {
            if (k == tmp.length) break;
            try IERC721(hederaTokenAddress).ownerOf(s) returns (address o) {
                if (o == owner) tmp[k++] = s;
            } catch {}
        }
        // trim
        assembly {
            mstore(tmp, k)
        }
        return tmp;
    }
}
