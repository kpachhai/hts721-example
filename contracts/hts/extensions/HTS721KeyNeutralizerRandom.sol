// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Initializable.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {IPrngSystemContract} from "@hashgraph/smart-contracts/contracts/system-contracts/pseudo-random-number-generator/IPrngSystemContract.sol";
import {HtsCallFailed, LengthMismatch, NotAuthorized} from "../HTS721Errors.sol";

/**
 * @title HTS721KeyNeutralizerRandom
 * @notice Neutralizes (irreversibly disables) selected HTS token keys by rotating them
 *         to unpredictable Ed25519 public keys derived from a single PRNG seed.
 *
 * SECURITY / IRREVERSIBILITY:
 *  - Once a key is rotated to a random Ed25519 public key for which no private key is known,
 *    that permission is effectively lost forever.
 *  - Neutralizing the ADMIN key prevents further rotations or fee / key updates (plan carefully).
 *
 * AUDITABILITY:
 *  - Emits rootSeed + mask so observers can recompute per-key derived PUBKEY = keccak256(rootSeed, keyType, index).
 *
 * GAS:
 *  - Single PRNG call; per-key derivations done with keccak256.
 *
 * SAFETY:
 *  - Admin key neutralization requires confirmAdmin=true.
 */
abstract contract HTS721KeyNeutralizerRandom is HTS721Initializable {
    event KeysNeutralizedRandom(uint256 mask, bytes32 rootSeed);

    address internal constant PRNG_PRECOMPILE = address(0x169);

    struct NeutralizeFlags {
        bool admin;
        bool kyc;
        bool freeze;
        bool wipe;
        bool supply;
        bool fee;
        bool pause;
    }

    error NoKeysSelected();
    error AdminNeutralizationRequiresConfirmation();

    /**
     * @notice Neutralize selected keys. This rotates each selected key to a fresh Ed25519 pubkey
     *         derived from a single PRNG root seed.
     *
     * @param f              Flags choosing which keys to neutralize.
     * @param confirmAdmin   Must be true if f.admin == true (explicit intent).
     */
    function neutralizeKeysRandom(
        NeutralizeFlags calldata f,
        bool confirmAdmin
    ) external onlyOwner onlyInitialized {
        uint256 count;
        if (f.admin) count++;
        if (f.kyc) count++;
        if (f.freeze) count++;
        if (f.wipe) count++;
        if (f.supply) count++;
        if (f.fee) count++;
        if (f.pause) count++;
        if (count == 0) revert NoKeysSelected();
        if (f.admin && !confirmAdmin)
            revert AdminNeutralizationRequiresConfirmation();

        // Fetch one root seed from PRNG system contract (call must succeed)
        (bool ok, bytes memory res) = PRNG_PRECOMPILE.call(
            abi.encodeWithSelector(
                IPrngSystemContract.getPseudorandomSeed.selector
            )
        );
        require(ok, "PRNG system call failed");
        bytes32 rootSeed = abi.decode(res, (bytes32));

        IHederaTokenService.TokenKey[]
            memory arr = new IHederaTokenService.TokenKey[](count);

        uint256 i;
        if (f.admin) arr[i++] = _deriveDeadEd25519(KEY_ADMIN, rootSeed, i);
        if (f.kyc) arr[i++] = _deriveDeadEd25519(KEY_KYC, rootSeed, i);
        if (f.freeze) arr[i++] = _deriveDeadEd25519(KEY_FREEZE, rootSeed, i);
        if (f.wipe) arr[i++] = _deriveDeadEd25519(KEY_WIPE, rootSeed, i);
        if (f.supply) arr[i++] = _deriveDeadEd25519(KEY_SUPPLY, rootSeed, i);
        if (f.fee) arr[i++] = _deriveDeadEd25519(KEY_FEE, rootSeed, i);
        if (f.pause) arr[i++] = _deriveDeadEd25519(KEY_PAUSE, rootSeed, i);

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

        emit KeysNeutralizedRandom(mask, rootSeed);
    }

    /**
     * @dev Builds a TokenKey with a pseudo-random Ed25519 public key derived from rootSeed + keyType + slotIndex.
     * @param keyType    Hedera key type bit (1,2,4,...)
     * @param rootSeed   PRNG seed
     * @param slotIndex  The sequential index among selected keys (1-based per insertion order)
     */
    function _deriveDeadEd25519(
        uint256 keyType,
        bytes32 rootSeed,
        uint256 slotIndex
    ) internal pure returns (IHederaTokenService.TokenKey memory tk) {
        bytes32 derived = keccak256(
            abi.encodePacked(rootSeed, keyType, slotIndex)
        );
        IHederaTokenService.KeyValue memory kv;
        kv.ed25519 = abi.encodePacked(derived); // 32 bytes
        tk.keyType = keyType;
        tk.key = kv;
    }
}
