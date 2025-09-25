// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {HtsCallFailed, NotAuthorized, OnlyAccountCanAssociateItself, OnlyAccountCanDisassociateItself} from "./HTS721Errors.sol";

/**
 * @title HTSManagement
 * @notice A lightweight, reusable mixin for managing a single HTS token.
 *
 * - Inherit this from any contract that needs to manage one HTS token.
 * - The derived contract MUST implement _hederaTokenAddress() to return the token address.
 * - Authorization is up to the derived contract: override _requireManagementAuth().
 *
 * Notes:
 * - If HTS keys are CONTRACT_ID, the managing contract must be the caller.
 * - If HTS keys are EOA, the EOA must sign the transaction. You can still offer
 *   pass-through functions here; the precompile will enforce the required signatures.
 */
abstract contract HTSManagement {
    // HTS precompile address (v1)
    address internal constant HTS_PRECOMPILE_ADDRESS = address(0x167);

    // Optional: Derived contracts can emit after management ops.
    event HTSManagementAction(bytes4 indexed selector, address indexed token, bytes data);
    event HTSKeysUpdated(address indexed token);
    event HTSFeesUpdated(address indexed token);

    // Hedera SUCCESS response code
    int32 internal constant SUCCESS = 22;

    // Derived must provide the token address it manages.
    function _hederaTokenAddress() internal view virtual returns (address);

    // Override to add Ownable/AccessControl/etc. Default: no extra gating.
    function _requireManagementAuth() internal view virtual {}

    modifier onlyManagementAuth() {
        _requireManagementAuth();
        _;
    }

    // -------------------- Core management wrappers --------------------

    function grantKyc(address account) external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.grantTokenKyc.selector, _hederaTokenAddress(), account)
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.grantTokenKyc.selector, rc);
        emit HTSManagementAction(IHederaTokenService.grantTokenKyc.selector, _hederaTokenAddress(), abi.encode(account));
    }

    function revokeKyc(address account) external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.revokeTokenKyc.selector, _hederaTokenAddress(), account)
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.revokeTokenKyc.selector, rc);
        emit HTSManagementAction(IHederaTokenService.revokeTokenKyc.selector, _hederaTokenAddress(), abi.encode(account));
    }

    function freeze(address account) external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.freezeToken.selector, _hederaTokenAddress(), account)
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.freezeToken.selector, rc);
        emit HTSManagementAction(IHederaTokenService.freezeToken.selector, _hederaTokenAddress(), abi.encode(account));
    }

    function unfreeze(address account) external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.unfreezeToken.selector, _hederaTokenAddress(), account)
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.unfreezeToken.selector, rc);
        emit HTSManagementAction(IHederaTokenService.unfreezeToken.selector, _hederaTokenAddress(), abi.encode(account));
    }

    function pause() external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.pauseToken.selector, _hederaTokenAddress())
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.pauseToken.selector, rc);
        emit HTSManagementAction(IHederaTokenService.pauseToken.selector, _hederaTokenAddress(), "");
    }

    function unpause() external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.unpauseToken.selector, _hederaTokenAddress())
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.unpauseToken.selector, rc);
        emit HTSManagementAction(IHederaTokenService.unpauseToken.selector, _hederaTokenAddress(), "");
    }

    function wipe(address account, int64[] memory serialNumbers) external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.wipeTokenAccountNFT.selector,
                _hederaTokenAddress(),
                account,
                serialNumbers
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.wipeTokenAccountNFT.selector, rc);
        emit HTSManagementAction(
            IHederaTokenService.wipeTokenAccountNFT.selector,
            _hederaTokenAddress(),
            abi.encode(account, serialNumbers)
        );
    }

    // -------------------- Custom fee (royalty) management --------------------

    function updateNftRoyaltyFees(
        IHederaTokenService.FixedFee[] memory fixedFees,
        IHederaTokenService.RoyaltyFee[] memory royaltyFees
    ) external virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.updateNonFungibleTokenCustomFees.selector,
                _hederaTokenAddress(),
                fixedFees,
                royaltyFees
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.updateNonFungibleTokenCustomFees.selector, rc);
        emit HTSFeesUpdated(_hederaTokenAddress());
    }

    function getTokenCustomFeesView()
        external
        view
        virtual
        returns (
            IHederaTokenService.FixedFee[] memory fixedFees,
            IHederaTokenService.FractionalFee[] memory fractionalFees,
            IHederaTokenService.RoyaltyFee[] memory royaltyFees
        )
    {
        (bool ok, bytes memory result) = HTS_PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(IHederaTokenService.getTokenCustomFees.selector, _hederaTokenAddress())
        );
        if (ok) {
            (, fixedFees, fractionalFees, royaltyFees) = abi.decode(
                result,
                (
                    int32,
                    IHederaTokenService.FixedFee[],
                    IHederaTokenService.FractionalFee[],
                    IHederaTokenService.RoyaltyFee[]
                )
            );
        } else {
            fixedFees = new IHederaTokenService.FixedFee[](0);
            fractionalFees = new IHederaTokenService.FractionalFee[](0);
            royaltyFees = new IHederaTokenService.RoyaltyFee[](0);
        }
    }

    // -------------------- Optional status helpers (for UIs) --------------------

    function isKycGranted(address account) external view virtual returns (bool) {
        (bool ok, bytes memory result) = HTS_PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(IHederaTokenService.isKyc.selector, _hederaTokenAddress(), account)
        );
        if (ok) {
            (, bool kycGranted) = abi.decode(result, (int32, bool));
            return kycGranted;
        }
        return false;
    }

    function isAccountFrozen(address account) external view virtual returns (bool) {
        (bool ok, bytes memory result) = HTS_PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(IHederaTokenService.isFrozen.selector, _hederaTokenAddress(), account)
        );
        if (ok) {
            (, bool frozen) = abi.decode(result, (int32, bool));
            return frozen;
        }
        return false;
    }

    // -------------------- Keys rotation / assignment --------------------

    /**
     * @notice Directly forward a keys update to HTS. Requires Admin key on token.
     * @dev If Admin key is not set or not controlled by the caller, this will fail.
     */
    function updateTokenKeys(IHederaTokenService.TokenKey[] memory keys) public virtual onlyManagementAuth {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.updateTokenKeys.selector, _hederaTokenAddress(), keys)
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.updateTokenKeys.selector, rc);
        emit HTSKeysUpdated(_hederaTokenAddress());
    }

    /**
     * @notice Convenience to set any subset of Admin/KYC/Freeze/Wipe/Supply/Fee/Pause keys to a single controller as CONTRACT_ID keys.
     */
    function setControllerAsContractKeys(
        address controller,
        bool admin,
        bool kyc,
        bool freeze_,
        bool wipe_,
        bool supply,
        bool feeSchedule,
        bool pause_
    ) external virtual onlyManagementAuth {
        uint256 n;
        if (admin) n++;
        if (kyc) n++;
        if (freeze_) n++;
        if (wipe_) n++;
        if (supply) n++;
        if (feeSchedule) n++;
        if (pause_) n++;

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](n);
        uint256 i;

        IHederaTokenService.KeyValue memory kv;
        kv.contractId = controller;

        if (admin) keys[i++] = IHederaTokenService.TokenKey(1, kv); // ADMIN = 1
        if (kyc) keys[i++] = IHederaTokenService.TokenKey(2, kv); // KYC = 2
        if (freeze_) keys[i++] = IHederaTokenService.TokenKey(4, kv); // FREEZE = 4
        if (wipe_) keys[i++] = IHederaTokenService.TokenKey(8, kv); // WIPE = 8
        if (supply) keys[i++] = IHederaTokenService.TokenKey(16, kv); // SUPPLY = 16
        if (feeSchedule) keys[i++] = IHederaTokenService.TokenKey(32, kv); // FEE = 32
        if (pause_) keys[i++] = IHederaTokenService.TokenKey(64, kv); // PAUSE = 64

        updateTokenKeys(keys);
    }

    // -------------------- Optional account association helpers --------------------

    function associate(address account) external virtual {
        if (msg.sender != account) revert OnlyAccountCanAssociateItself();
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.associateToken.selector, account, _hederaTokenAddress())
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.associateToken.selector, rc);
    }

    function disassociate(address account) external virtual {
        if (msg.sender != account) revert OnlyAccountCanDisassociateItself();
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(IHederaTokenService.dissociateToken.selector, account, _hederaTokenAddress())
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) revert HtsCallFailed(IHederaTokenService.dissociateToken.selector, rc);
    }
}