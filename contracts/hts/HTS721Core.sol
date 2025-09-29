// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";

import "./HTSCommon.sol";
import "./HTS721Errors.sol";
import "./interfaces/IHTS721Core.sol";

/**
 * @dev Minimal base for creating & holding HTS NFT keys.
 *      - No ERC721 passthrough (users interact with underlying mirror directly).
 */
abstract contract HTS721Core is Ownable, HTSCommon, IHTS721Core {
    int32 internal constant DEFAULT_RENEW = 7776000;
    uint256 internal constant MAX_META = 100;
    uint256 private constant INT64_MAX = 0x7fffffffffffffff;

    address public override hederaTokenAddress;
    bool public override initialized;
    uint256 internal _lastSerial;

    event Initialized(address token, string name, string symbol);
    event MintForward(uint256 serial, address to); // used by mint extension

    modifier onlyInit() {
        if (!initialized) revert NotInitialized();
        _;
    }
    modifier onlyNotInit() {
        if (initialized) revert AlreadyInitialized();
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @inheritdoc IHTS721Core
     */
    function initialize(
        IHTS721Core.InitConfig calldata cfg
    ) external payable override onlyOwner onlyNotInit {
        address tokenAddr = _createToken(cfg);
        hederaTokenAddress = tokenAddr;
        initialized = true;
        emit Initialized(tokenAddr, cfg.name, cfg.symbol);
    }

    // ------------------------------------------------------------------
    // Internal: Token Creation (isolated to reduce stack depth)
    // ------------------------------------------------------------------
    function _createToken(
        IHTS721Core.InitConfig calldata cfg
    ) internal returns (address tokenAddr) {
        IHederaTokenService.TokenKey[] memory tokenKeys = _buildKeys(
            cfg.keyMask
        );

        IHederaTokenService.HederaToken memory token;
        token.name = cfg.name;
        token.symbol = cfg.symbol;
        token.treasury = address(this);
        token.memo = cfg.memo;
        token.tokenSupplyType = false; // infinite supply
        token.maxSupply = 0;
        token.freezeDefault = cfg.freezeDefault;
        token.tokenKeys = tokenKeys;
        token.expiry = IHederaTokenService.Expiry(
            0,
            cfg.autoRenewAccount == address(0)
                ? address(this)
                : cfg.autoRenewAccount,
            cfg.autoRenewPeriod == int32(0)
                ? DEFAULT_RENEW
                : cfg.autoRenewPeriod
        );

        (bool ok, bytes memory result) = HTS_PRECOMPILE_ADDRESS.call{
            value: msg.value
        }(
            abi.encodeWithSelector(
                IHederaTokenService.createNonFungibleToken.selector,
                token
            )
        );
        if (!ok)
            revert HtsCallFailed(
                IHederaTokenService.createNonFungibleToken.selector,
                int32(-1)
            );
        (int32 rc, address created) = abi.decode(result, (int32, address));
        if (rc != SUCCESS || created == address(0))
            revert TokenCreationFailed();
        tokenAddr = created;
    }

    // ------------------------------------------------------------------
    // Internal primitive for mint metadata (used by mint extension)
    // ------------------------------------------------------------------
    function _mintPrimitive(
        bytes calldata metadata
    ) internal onlyInit returns (uint256 serial) {
        if (metadata.length > MAX_META) revert MetadataTooLarge();
        bytes[] memory metaArr = new bytes[](1);
        metaArr[0] = metadata.length == 0 ? bytes(hex"01") : metadata;

        (bool ok, bytes memory result) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.mintToken.selector,
                hederaTokenAddress,
                int64(0),
                metaArr
            )
        );
        if (!ok)
            revert HtsCallFailed(
                IHederaTokenService.mintToken.selector,
                int32(-1)
            );
        (int32 rc, , int64[] memory serials) = abi.decode(
            result,
            (int32, int64, int64[])
        );
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.mintToken.selector, rc);

        serial = uint256(uint64(serials[0]));
        _lastSerial = serial;
    }

    // ------------------------------------------------------------------
    // Utility
    // ------------------------------------------------------------------
    function _toI64(uint256 x) internal pure returns (int64) {
        if (x > INT64_MAX) revert CastOverflow();
        return int64(uint64(x));
    }

    function _buildKeys(
        uint8 mask
    ) internal view returns (IHederaTokenService.TokenKey[] memory arr) {
        uint8 count;
        if (mask & uint8(KEY_ADMIN) != 0) count++;
        if (mask & uint8(KEY_KYC) != 0) count++;
        if (mask & uint8(KEY_FREEZE) != 0) count++;
        if (mask & uint8(KEY_WIPE) != 0) count++;
        if (mask & uint8(KEY_SUPPLY) != 0) count++;
        if (mask & uint8(KEY_FEE) != 0) count++;
        if (mask & uint8(KEY_PAUSE) != 0) count++;

        arr = new IHederaTokenService.TokenKey[](count);
        IHederaTokenService.KeyValue memory kv;
        kv.contractId = address(this);

        uint8 i;
        if (mask & uint8(KEY_ADMIN) != 0)
            arr[i++] = IHederaTokenService.TokenKey(KEY_ADMIN, kv);
        if (mask & uint8(KEY_KYC) != 0)
            arr[i++] = IHederaTokenService.TokenKey(KEY_KYC, kv);
        if (mask & uint8(KEY_FREEZE) != 0)
            arr[i++] = IHederaTokenService.TokenKey(KEY_FREEZE, kv);
        if (mask & uint8(KEY_WIPE) != 0)
            arr[i++] = IHederaTokenService.TokenKey(KEY_WIPE, kv);
        if (mask & uint8(KEY_SUPPLY) != 0)
            arr[i++] = IHederaTokenService.TokenKey(KEY_SUPPLY, kv);
        if (mask & uint8(KEY_FEE) != 0)
            arr[i++] = IHederaTokenService.TokenKey(KEY_FEE, kv);
        if (mask & uint8(KEY_PAUSE) != 0)
            arr[i++] = IHederaTokenService.TokenKey(KEY_PAUSE, kv);
    }
}
