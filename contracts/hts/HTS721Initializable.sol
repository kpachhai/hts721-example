// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import {IHRC719} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHRC719.sol";

import {ZeroAddress, HtsCallFailed, TokenCreationFailed, MetadataTooLarge, TokenNotCreated, CastOverflow, NotAuthorized, AlreadyInitialized, NotInitialized, LengthMismatch, WrapperApproveOnlyWhenContractOwns, WrapperTransferNotAuthorized, WrapperSetApprovalOnlyWhenContractOwns} from "./HTS721Errors.sol";
import {HTSCommon} from "./HTSCommon.sol";

/**
 * @title HTS721Initializable
 * @notice Two-phase HTS NFT base:
 *         1) Deploy (constructor does nothing HTS-specific)
 *         2) initialize() creates the underlying HTS NFT with selected contract-held keys & treasury
 *
 * IMPORTANT (Hedera nuance):
 * - State-changing ERC721 calls forwarded here run with msg.sender = this wrapper when
 *   they reach the underlying HTS token. So approval/transfer succeed ONLY if:
 *     (a) The wrapper already owns the token (treasury custody), OR
 *     (b) The wrapper has been approved on the underlying (user called underlying.approve(wrapper, tokenId)), OR
 *     (c) The wrapper is an operator via underlying.setApprovalForAll(owner, true).
 * - We add guardrails that give explicit errors instead of opaque underlying reverts.
 */
abstract contract HTS721Initializable is
    ERC165,
    IERC721,
    IERC721Metadata,
    Ownable,
    HTSCommon
{
    int32 internal constant DEFAULT_AUTO_RENEW_PERIOD = 7776000;
    uint256 internal constant MAX_METADATA_LEN = 100;
    uint256 private constant INT64_MAX = 0x7fffffffffffffff;

    address public hederaTokenAddress;
    bool public initialized;

    // For optional enumeration extensions
    uint256 internal _lastMintedSerial;

    bytes private constant DEFAULT_METADATA = hex"01";

    event Initialized(address indexed token, string name, string symbol);
    event KeysAdded(uint256 mask);
    event KeysDropped(uint256 mask);
    event TreasuryUpdated(address indexed newTreasury);
    event Minted(address indexed to, uint256 indexed tokenId);
    event TreasuryTransfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );
    event WrapperOperatorSet(address indexed operator, bool approved);

    struct InitKeys {
        bool admin;
        bool kyc;
        bool freeze;
        bool wipe;
        bool supply;
        bool fee;
        bool pause;
    }

    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }
    modifier onlyNotInitialized() {
        if (initialized) revert AlreadyInitialized();
        _;
    }

    constructor() Ownable(msg.sender) {}

    /* =========================================================
                                INIT
       ========================================================= */
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory memo_,
        InitKeys memory keys,
        bool freezeDefault,
        address autoRenewAccount,
        int32 autoRenewPeriod
    ) external payable onlyOwner onlyNotInitialized {
        IHederaTokenService.TokenKey[] memory tokenKeys = _buildContractKeys(
            keys
        );

        IHederaTokenService.HederaToken memory token = IHederaTokenService
            .HederaToken({
                name: name_,
                symbol: symbol_,
                treasury: address(this),
                memo: memo_,
                tokenSupplyType: false, // infinite supply
                maxSupply: 0,
                freezeDefault: freezeDefault,
                tokenKeys: tokenKeys,
                expiry: IHederaTokenService.Expiry(
                    0,
                    autoRenewAccount == address(0)
                        ? address(this)
                        : autoRenewAccount,
                    autoRenewPeriod == int32(0)
                        ? DEFAULT_AUTO_RENEW_PERIOD
                        : autoRenewPeriod
                )
            });

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

        (int32 rc, address tokenAddress) = abi.decode(result, (int32, address));
        if (rc != SUCCESS || tokenAddress == address(0))
            revert TokenCreationFailed();

        hederaTokenAddress = tokenAddress;
        initialized = true;

        emit Initialized(tokenAddress, name_, symbol_);
    }

    /* =========================================================
                          KEY & TREASURY MGMT
       ========================================================= */
    function addKeys(
        InitKeys memory addCfg
    ) external onlyOwner onlyInitialized {
        (
            uint256 mask,
            IHederaTokenService.TokenKey[] memory arr
        ) = _buildSubsetContractKeys(addCfg);
        if (mask == 0) return;
        _updateTokenKeys(arr);
        emit KeysAdded(mask);
    }

    function dropKeys(
        InitKeys memory dropCfg
    ) external onlyOwner onlyInitialized {
        (
            uint256 mask,
            IHederaTokenService.TokenKey[] memory arr
        ) = _buildSubsetEmptyKeys(dropCfg);
        if (mask == 0) return;
        _updateTokenKeys(arr);
        emit KeysDropped(mask);
    }

    function updateTreasury(
        address newTreasury
    ) external onlyOwner onlyInitialized {
        if (newTreasury == address(0)) revert ZeroAddress();

        IHederaTokenService.HederaToken memory partialInfo;
        partialInfo.treasury = newTreasury;
        partialInfo.expiry = IHederaTokenService.Expiry(0, address(0), 0);

        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.updateTokenInfo.selector,
                hederaTokenAddress,
                partialInfo
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(
                IHederaTokenService.updateTokenInfo.selector,
                rc
            );

        emit TreasuryUpdated(newTreasury);
    }

    /* =========================================================
                          METADATA (VIEWS)
       ========================================================= */
    function name()
        external
        view
        override
        onlyInitialized
        returns (string memory)
    {
        return IERC721Metadata(hederaTokenAddress).name();
    }
    function symbol()
        external
        view
        override
        onlyInitialized
        returns (string memory)
    {
        return IERC721Metadata(hederaTokenAddress).symbol();
    }
    function tokenURI(
        uint256 tokenId
    ) external view override onlyInitialized returns (string memory) {
        return IERC721Metadata(hederaTokenAddress).tokenURI(tokenId);
    }

    /* =========================================================
                          CORE VIEWS
       ========================================================= */
    function balanceOf(
        address owner
    ) external view override onlyInitialized returns (uint256) {
        return IERC721(hederaTokenAddress).balanceOf(owner);
    }
    function ownerOf(
        uint256 tokenId
    ) external view override onlyInitialized returns (address) {
        return IERC721(hederaTokenAddress).ownerOf(tokenId);
    }
    function getApproved(
        uint256 tokenId
    ) external view override onlyInitialized returns (address) {
        return IERC721(hederaTokenAddress).getApproved(tokenId);
    }
    function isApprovedForAll(
        address owner,
        address operator
    ) external view override onlyInitialized returns (bool) {
        return IERC721(hederaTokenAddress).isApprovedForAll(owner, operator);
    }

    /* =========================================================
                        STATE: GUARDED WRITES
       ========================================================= */

    /**
     * @dev Owner-only. Valid ONLY when the treasury (this contract) owns tokenId.
     * Users will *never* call this; they approve the underlying token directly.
     */
    function approve(
        address to,
        uint256 tokenId
    ) external override onlyInitialized onlyOwner {
        address currentOwner = IERC721(hederaTokenAddress).ownerOf(tokenId);
        if (currentOwner != address(this)) {
            revert WrapperApproveOnlyWhenContractOwns(tokenId, currentOwner);
        }
        IERC721(hederaTokenAddress).approve(to, tokenId);
    }

    /**
     * @dev Owner-only operator approval for treasury-held (or future) tokens.
     * Optional policy: forbid pre-approval if treasury empty (uncomment guard).
     */
    function setApprovalForAll(
        address operator,
        bool approved
    ) external override onlyInitialized onlyOwner {
        if (IERC721(hederaTokenAddress).balanceOf(address(this)) == 0) {
            revert WrapperSetApprovalOnlyWhenContractOwns();
        }
        IERC721(hederaTokenAddress).setApprovalForAll(operator, approved);
        emit WrapperOperatorSet(operator, approved);
    }

    /**
     * @dev Owner-only orchestrated transfer:
     *  - If treasury owns token: direct distribution (from must be address(this)).
     *  - If user owns token: wrapper must have underlying approval/operator already.
     * Users do *not* call this themselves; they simply approve underlying,
     * then backend / owner triggers this.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyInitialized onlyOwner {
        address actualOwner = IERC721(hederaTokenAddress).ownerOf(tokenId);

        if (actualOwner == address(this)) {
            // Treasury distribution
            if (from != address(this)) {
                // Normalize / enforce correct "from"
                from = address(this);
            }
            IERC721(hederaTokenAddress).transferFrom(from, to, tokenId);
            emit TreasuryTransfer(from, to, tokenId);
            return;
        }

        // User-owned path: require wrapper authorized (underlying approval/operator)
        if (!_isWrapperAuthorized(tokenId)) {
            revert WrapperTransferNotAuthorized(tokenId, actualOwner);
        }

        // 'from' must be the actual owner in this branch
        if (from != actualOwner) {
            revert WrapperTransferNotAuthorized(tokenId, actualOwner);
        }

        IERC721(hederaTokenAddress).transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external override onlyInitialized {
        // Delegate to guarded transfer (still owner-only because transferFrom is owner-only)
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory
    ) external override onlyInitialized {
        transferFrom(from, to, tokenId);
    }

    /* =========================================================
                         HTS NATIVE (ASSOC)
       ========================================================= */

    function associate() external onlyInitialized {
        int32 rc = int32(uint32(IHRC719(hederaTokenAddress).associate()));
        if (rc != SUCCESS && rc != TOKEN_ALREADY_ASSOCIATED)
            revert HtsCallFailed(IHRC719.associate.selector, rc);
    }

    function dissociate() external onlyInitialized {
        int32 rc = int32(uint32(IHRC719(hederaTokenAddress).dissociate()));
        // TOKEN_NOT_ASSOCIATED is network-specific; treat any non-success except that as failure
        // If you have a constant, use it. Here we allow rc == SUCCESS only.
        if (rc != SUCCESS)
            revert HtsCallFailed(IHRC719.dissociate.selector, rc);
    }

    /* =========================================================
                              INTERNAL MINT
       ========================================================= */
    function _mint(
        address to,
        bytes calldata metadata
    ) internal onlyInitialized returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        if (metadata.length > MAX_METADATA_LEN) revert MetadataTooLarge();

        bytes memory m = metadata.length == 0
            ? DEFAULT_METADATA
            : bytes(metadata);
        bytes[] memory metaArr = new bytes[](1);
        metaArr[0] = m;

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

        uint256 tokenId = uint256(uint64(serials[0]));
        _lastMintedSerial = tokenId;

        // Treasury owns it first; then we decide to transfer.
        IERC721(hederaTokenAddress).transferFrom(address(this), to, tokenId);

        emit Minted(to, tokenId);
        return tokenId;
    }

    /* =========================================================
                            AUTH HELPERS
       ========================================================= */

    /**
     * @dev Returns true if the wrapper (this contract) is authorized to move tokenId at the underlying layer.
     *      Equivalent concept to "isApprovedOrOwner(wrapper, tokenId)".
     */
    function _isWrapperAuthorized(
        uint256 tokenId
    ) internal view returns (bool) {
        address owner_ = IERC721(hederaTokenAddress).ownerOf(tokenId);
        if (owner_ == address(this)) return true; // treasury owned
        // direct approval
        address approved = IERC721(hederaTokenAddress).getApproved(tokenId);
        if (approved == address(this)) return true;
        // operator approval
        if (IERC721(hederaTokenAddress).isApprovedForAll(owner_, address(this)))
            return true;
        return false;
    }

    /**
     * @notice Convenience helper for integrators (underlying token address).
     */
    function underlying() external view returns (address) {
        return hederaTokenAddress;
    }

    /* =========================================================
                          KEY BUILDERS
       ========================================================= */
    function _buildContractKeys(
        InitKeys memory cfg
    ) internal view returns (IHederaTokenService.TokenKey[] memory arr) {
        uint256 count;
        if (cfg.admin) count++;
        if (cfg.kyc) count++;
        if (cfg.freeze) count++;
        if (cfg.wipe) count++;
        if (cfg.supply) count++;
        if (cfg.fee) count++;
        if (cfg.pause) count++;

        arr = new IHederaTokenService.TokenKey[](count);
        IHederaTokenService.KeyValue memory kv;
        kv.contractId = address(this);

        uint256 i;
        if (cfg.admin) arr[i++] = IHederaTokenService.TokenKey(KEY_ADMIN, kv);
        if (cfg.kyc) arr[i++] = IHederaTokenService.TokenKey(KEY_KYC, kv);
        if (cfg.freeze) arr[i++] = IHederaTokenService.TokenKey(KEY_FREEZE, kv);
        if (cfg.wipe) arr[i++] = IHederaTokenService.TokenKey(KEY_WIPE, kv);
        if (cfg.supply) arr[i++] = IHederaTokenService.TokenKey(KEY_SUPPLY, kv);
        if (cfg.fee) arr[i++] = IHederaTokenService.TokenKey(KEY_FEE, kv);
        if (cfg.pause) arr[i++] = IHederaTokenService.TokenKey(KEY_PAUSE, kv);
    }

    function _buildSubsetContractKeys(
        InitKeys memory addCfg
    )
        internal
        view
        returns (uint256 mask, IHederaTokenService.TokenKey[] memory arr)
    {
        mask = _computeMask(addCfg);
        if (mask == 0) return (0, new IHederaTokenService.TokenKey[](0));

        uint256 count;
        if (addCfg.admin) count++;
        if (addCfg.kyc) count++;
        if (addCfg.freeze) count++;
        if (addCfg.wipe) count++;
        if (addCfg.supply) count++;
        if (addCfg.fee) count++;
        if (addCfg.pause) count++;

        arr = new IHederaTokenService.TokenKey[](count);
        IHederaTokenService.KeyValue memory kv;
        kv.contractId = address(this);

        uint256 i;
        if (addCfg.admin)
            arr[i++] = IHederaTokenService.TokenKey(KEY_ADMIN, kv);
        if (addCfg.kyc) arr[i++] = IHederaTokenService.TokenKey(KEY_KYC, kv);
        if (addCfg.freeze)
            arr[i++] = IHederaTokenService.TokenKey(KEY_FREEZE, kv);
        if (addCfg.wipe) arr[i++] = IHederaTokenService.TokenKey(KEY_WIPE, kv);
        if (addCfg.supply)
            arr[i++] = IHederaTokenService.TokenKey(KEY_SUPPLY, kv);
        if (addCfg.fee) arr[i++] = IHederaTokenService.TokenKey(KEY_FEE, kv);
        if (addCfg.pause)
            arr[i++] = IHederaTokenService.TokenKey(KEY_PAUSE, kv);
    }

    function _buildSubsetEmptyKeys(
        InitKeys memory dropCfg
    )
        internal
        pure
        returns (uint256 mask, IHederaTokenService.TokenKey[] memory arr)
    {
        mask = _computeMask(dropCfg);
        if (mask == 0) return (0, new IHederaTokenService.TokenKey[](0));

        uint256 count;
        if (dropCfg.admin) count++;
        if (dropCfg.kyc) count++;
        if (dropCfg.freeze) count++;
        if (dropCfg.wipe) count++;
        if (dropCfg.supply) count++;
        if (dropCfg.fee) count++;
        if (dropCfg.pause) count++;

        arr = new IHederaTokenService.TokenKey[](count);
        IHederaTokenService.KeyValue memory emptyKV;

        uint256 i;
        if (dropCfg.admin)
            arr[i++] = IHederaTokenService.TokenKey(KEY_ADMIN, emptyKV);
        if (dropCfg.kyc)
            arr[i++] = IHederaTokenService.TokenKey(KEY_KYC, emptyKV);
        if (dropCfg.freeze)
            arr[i++] = IHederaTokenService.TokenKey(KEY_FREEZE, emptyKV);
        if (dropCfg.wipe)
            arr[i++] = IHederaTokenService.TokenKey(KEY_WIPE, emptyKV);
        if (dropCfg.supply)
            arr[i++] = IHederaTokenService.TokenKey(KEY_SUPPLY, emptyKV);
        if (dropCfg.fee)
            arr[i++] = IHederaTokenService.TokenKey(KEY_FEE, emptyKV);
        if (dropCfg.pause)
            arr[i++] = IHederaTokenService.TokenKey(KEY_PAUSE, emptyKV);
    }

    function _computeMask(
        InitKeys memory k
    ) internal pure returns (uint256 mask) {
        if (k.admin) mask |= KEY_ADMIN;
        if (k.kyc) mask |= KEY_KYC;
        if (k.freeze) mask |= KEY_FREEZE;
        if (k.wipe) mask |= KEY_WIPE;
        if (k.supply) mask |= KEY_SUPPLY;
        if (k.fee) mask |= KEY_FEE;
        if (k.pause) mask |= KEY_PAUSE;
    }

    function _updateTokenKeys(
        IHederaTokenService.TokenKey[] memory keys
    ) internal {
        if (keys.length == 0) return;
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.updateTokenKeys.selector,
                hederaTokenAddress,
                keys
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(
                IHederaTokenService.updateTokenKeys.selector,
                rc
            );
    }

    /* =========================================================
                             ERC165
       ========================================================= */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /* =========================================================
                             UTIL
       ========================================================= */
    function _toI64(uint256 x) internal pure returns (int64) {
        if (x > INT64_MAX) revert CastOverflow();
        return int64(uint64(x));
    }
}
