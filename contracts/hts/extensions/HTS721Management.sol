// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Core.sol";
import "../interfaces/IHTS721Manage.sol";
import "../HTS721Errors.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";

/**
 * @dev Management (KYC/Freeze/Pause/Wipe/Royalties/Delete).
 */
abstract contract HTS721Management is HTS721Core, IHTS721Manage {
    modifier onlyMgr() {
        if (msg.sender != owner()) revert NotOwner();
        _;
    }

    function grantKyc(address a) external onlyInit onlyMgr {
        _call(
            IHederaTokenService.grantTokenKyc.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function revokeKyc(address a) external onlyInit onlyMgr {
        _call(
            IHederaTokenService.revokeTokenKyc.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function freeze(address a) external onlyInit onlyMgr {
        _call(
            IHederaTokenService.freezeToken.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function unfreeze(address a) external onlyInit onlyMgr {
        _call(
            IHederaTokenService.unfreezeToken.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function pause() external onlyInit onlyMgr {
        _call(
            IHederaTokenService.pauseToken.selector,
            abi.encode(hederaTokenAddress)
        );
    }
    function unpause() external onlyInit onlyMgr {
        _call(
            IHederaTokenService.unpauseToken.selector,
            abi.encode(hederaTokenAddress)
        );
    }
    function wipe(
        address a,
        int64[] calldata serials
    ) external onlyInit onlyMgr {
        _call(
            IHederaTokenService.wipeTokenAccountNFT.selector,
            abi.encode(hederaTokenAddress, a, serials)
        );
    }

    function updateNftRoyaltyFees(
        bytes calldata fixedFeesEncoded,
        bytes calldata royaltyFeesEncoded
    ) external onlyInit onlyMgr {
        IHederaTokenService.FixedFee[] memory f = abi.decode(
            fixedFeesEncoded,
            (IHederaTokenService.FixedFee[])
        );
        IHederaTokenService.RoyaltyFee[] memory r = abi.decode(
            royaltyFeesEncoded,
            (IHederaTokenService.RoyaltyFee[])
        );

        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.updateNonFungibleTokenCustomFees.selector,
                hederaTokenAddress,
                f,
                r
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(
                IHederaTokenService.updateNonFungibleTokenCustomFees.selector,
                rc
            );
    }

    function deleteToken() external onlyInit onlyMgr {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.deleteToken.selector,
                hederaTokenAddress
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.deleteToken.selector, rc);
    }

    function _call(bytes4 sel, bytes memory args) internal {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodePacked(sel, args)
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(sel, rc);
    }
}
