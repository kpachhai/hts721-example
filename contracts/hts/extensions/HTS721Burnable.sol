// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {HTS721} from "../HTS721.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {TokenNotCreated, TransferCallerNotOwnerNorApproved, ContractNotApprovedToTransfer, BurnFailed, HtsCallFailed} from "../HTS721Errors.sol";

abstract contract HTS721Burnable is HTS721 {
    function burn(uint256 tokenId) internal virtual {
        if (hederaTokenAddress == address(0)) revert TokenNotCreated();
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert TransferCallerNotOwnerNorApproved();

        address owner_ = IERC721(hederaTokenAddress).ownerOf(tokenId);

        // If not already in treasury, ensure this contract is approved to pull the token and then pull it
        if (owner_ != address(this)) {
            bool contractApproved = (IERC721(hederaTokenAddress).getApproved(
                tokenId
            ) == address(this)) ||
                IERC721(hederaTokenAddress).isApprovedForAll(
                    owner_,
                    address(this)
                );
            if (!contractApproved) revert ContractNotApprovedToTransfer();
            IERC721(hederaTokenAddress).transferFrom(
                owner_,
                address(this),
                tokenId
            );
        }

        // Burn via HTS (requires token to be in treasury)
        int64[] memory serialNumbers = new int64[](1);
        serialNumbers[0] = _toI64(tokenId);

        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.burnToken.selector,
                hederaTokenAddress,
                int64(0),
                serialNumbers
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.burnToken.selector, rc);
    }
}
