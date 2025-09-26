// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Initializable.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {HtsCallFailed, NotAuthorized} from "../HTS721Errors.sol";

/**
 * @title HTS721Management
 * @notice Operational controls: KYC, Freeze, Pause, Wipe, Royalty Fees
 */
abstract contract HTS721Management is HTS721Initializable {
    modifier onlyManagementAuth() {
        _requireManagementAuth();
        _;
    }

    function _requireManagementAuth() internal view virtual {
        if (msg.sender != owner()) revert NotAuthorized();
    }

    function grantKyc(address a) external onlyInitialized onlyManagementAuth {
        _call(
            IHederaTokenService.grantTokenKyc.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function revokeKyc(address a) external onlyInitialized onlyManagementAuth {
        _call(
            IHederaTokenService.revokeTokenKyc.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function freeze(address a) external onlyInitialized onlyManagementAuth {
        _call(
            IHederaTokenService.freezeToken.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function unfreeze(address a) external onlyInitialized onlyManagementAuth {
        _call(
            IHederaTokenService.unfreezeToken.selector,
            abi.encode(hederaTokenAddress, a)
        );
    }
    function pause() external onlyInitialized onlyManagementAuth {
        _call(
            IHederaTokenService.pauseToken.selector,
            abi.encode(hederaTokenAddress)
        );
    }
    function unpause() external onlyInitialized onlyManagementAuth {
        _call(
            IHederaTokenService.unpauseToken.selector,
            abi.encode(hederaTokenAddress)
        );
    }
    function wipe(
        address a,
        int64[] calldata serials
    ) external onlyInitialized onlyManagementAuth {
        _call(
            IHederaTokenService.wipeTokenAccountNFT.selector,
            abi.encode(hederaTokenAddress, a, serials)
        );
    }

    function updateNftRoyaltyFees(
        IHederaTokenService.FixedFee[] calldata fixedFees,
        IHederaTokenService.RoyaltyFee[] calldata royaltyFees
    ) external onlyInitialized onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.updateNonFungibleTokenCustomFees.selector,
                hederaTokenAddress,
                fixedFees,
                royaltyFees
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(
                IHederaTokenService.updateNonFungibleTokenCustomFees.selector,
                rc
            );
    }

    function _call(bytes4 sel, bytes memory args) internal {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodePacked(sel, args)
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(sel, rc);
    }
}
