// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Core.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {IPrngSystemContract} from "@hashgraph/smart-contracts/contracts/system-contracts/pseudo-random-number-generator/IPrngSystemContract.sol";
import "../HTS721Errors.sol";

/**
 * @dev Key neutralization (rotate selected keys to random Ed25519 public keys).
 */
abstract contract HTS721KeyNeutralizerRandom is HTS721Core {
    address internal constant PRNG_PRECOMPILE = address(0x169);

    event KeysNeutralized(uint256 mask, bytes32 rootSeed);

    struct Flags {
        bool admin;
        bool kyc;
        bool freeze;
        bool wipe;
        bool supply;
        bool fee;
        bool pause;
    }
    error NoKeysSelected();
    error NeedAdminConfirm();

    function neutralizeKeysRandom(
        Flags calldata f,
        bool confirmAdmin
    ) external onlyOwner onlyInit {
        uint256 count;
        if (f.admin) count++;
        if (f.kyc) count++;
        if (f.freeze) count++;
        if (f.wipe) count++;
        if (f.supply) count++;
        if (f.fee) count++;
        if (f.pause) count++;
        if (count == 0) revert NoKeysSelected();
        if (f.admin && !confirmAdmin) revert NeedAdminConfirm();

        (bool ok, bytes memory res) = PRNG_PRECOMPILE.call(
            abi.encodeWithSelector(
                IPrngSystemContract.getPseudorandomSeed.selector
            )
        );
        require(ok, "PRNG");
        bytes32 rootSeed = abi.decode(res, (bytes32));

        IHederaTokenService.TokenKey[]
            memory arr = new IHederaTokenService.TokenKey[](count);
        uint256 i;
        if (f.admin) arr[i++] = _deadKey(KEY_ADMIN, rootSeed, i);
        if (f.kyc) arr[i++] = _deadKey(KEY_KYC, rootSeed, i);
        if (f.freeze) arr[i++] = _deadKey(KEY_FREEZE, rootSeed, i);
        if (f.wipe) arr[i++] = _deadKey(KEY_WIPE, rootSeed, i);
        if (f.supply) arr[i++] = _deadKey(KEY_SUPPLY, rootSeed, i);
        if (f.fee) arr[i++] = _deadKey(KEY_FEE, rootSeed, i);
        if (f.pause) arr[i++] = _deadKey(KEY_PAUSE, rootSeed, i);

        (ok, res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.updateTokenKeys.selector,
                hederaTokenAddress,
                arr
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(
                IHederaTokenService.updateTokenKeys.selector,
                rc
            );

        uint256 mask;
        if (f.admin) mask |= KEY_ADMIN;
        if (f.kyc) mask |= KEY_KYC;
        if (f.freeze) mask |= KEY_FREEZE;
        if (f.wipe) mask |= KEY_WIPE;
        if (f.supply) mask |= KEY_SUPPLY;
        if (f.fee) mask |= KEY_FEE;
        if (f.pause) mask |= KEY_PAUSE;

        emit KeysNeutralized(mask, rootSeed);
    }

    function _deadKey(
        uint256 keyType,
        bytes32 rootSeed,
        uint256 slotIndex
    ) internal pure returns (IHederaTokenService.TokenKey memory tk) {
        bytes32 d = keccak256(abi.encodePacked(rootSeed, keyType, slotIndex));
        IHederaTokenService.KeyValue memory kv;
        kv.ed25519 = abi.encodePacked(d);
        tk.keyType = keyType;
        tk.key = kv;
    }
}
