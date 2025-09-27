// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Initializable.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {TokenNotCreated, HtsCallFailed} from "../HTS721Errors.sol";

/**
 * @title HTS721Burnable
 */
abstract contract HTS721Burnable is HTS721Initializable {
    event Burned(uint256 indexed tokenId);

    function _burn(uint256 tokenId) internal onlyInitialized {
        if (hederaTokenAddress == address(0)) revert TokenNotCreated();
        transferFrom(msg.sender, address(this), tokenId);

        int64[] memory serials = new int64[](1);
        serials[0] = _toI64(tokenId);

        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.burnToken.selector,
                hederaTokenAddress,
                int64(0),
                serials
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.burnToken.selector, rc);
        emit Burned(tokenId);
    }
}
