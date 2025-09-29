// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";

import {ZeroAddress, HtsCallFailed, TokenCreationFailed, MetadataTooLarge, TokenNotCreated, CastOverflow, NotAuthorized, AlreadyInitialized, NotInitialized, LengthMismatch, WrapperApproveOnlyWhenContractOwns, WrapperTransferNotAuthorized, WrapperSetApprovalOnlyWhenContractOwns} from "./HTS721Errors.sol";
import {HTSCommon} from "./HTSCommon.sol";

/**
 * @title HTS721Initializable
 * @notice Hybrid Hedera HTS (NFT) wrapper:
 *  - Constructor does nothing HTS-specific
 *  - initialize() creates the underlying HTS NFT with keys mapped to this contract (CONTRACT_ID keys)
 *
 * Hybrid Strategy:
 *  - Underlying HTS token remains canonical for user ownership (users can transfer natively).
 *  - Wrapper provides mint (supply key), management hooks (via extensions), delegated transfers
 *    (after user approval), and controlled key neutralization (via external neutralizer mixin).
 *
 * Key Removal:
 *  - True deletion is not supported by HTS. Use the HTS721KeyNeutralizerRandom extension to “neutralize”
 *
 * Association / KYC:
 *  - associate() and dissociate() call the HTS precompile directly with msg.sender as account.
 */
abstract contract HTS721Initializable is
    ERC165,
    IERC721,
    IERC721Metadata,
    Ownable,
    HTSCommon
{
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    int32 internal constant DEFAULT_AUTO_RENEW_PERIOD = 7776000;
    uint256 internal constant MAX_METADATA_LEN = 100;
    uint256 private constant INT64_MAX = 0x7fffffffffffffff;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------
    address public hederaTokenAddress;
    bool public initialized;
    uint256 internal _lastMintedSerial;

    bytes private constant DEFAULT_METADATA = hex"01";

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event Initialized(address indexed token, string name, string symbol);
    event KeysAdded(uint256 mask);
    event TreasuryUpdated(address indexed newTreasury);
    event Minted(address indexed to, uint256 indexed tokenId);
    event TreasuryTransfer(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    );
    event WrapperOperatorSet(address indexed operator, bool approved);

    // ---------------------------------------------------------------------
    // Structs
    // ---------------------------------------------------------------------
    struct InitKeys {
        bool admin;
        bool kyc;
        bool freeze;
        bool wipe;
        bool supply;
        bool fee;
        bool pause;
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier onlyInitialized() {
        if (!initialized) revert NotInitialized();
        _;
    }
    modifier onlyNotInitialized() {
        if (initialized) revert AlreadyInitialized();
        _;
    }

    constructor() Ownable(msg.sender) {}

    // ---------------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------------
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

        // tokenSupplyType = false (infinite supply) for NFTs in HTS (0 = INFINITE, 1 = FINITE)
        IHederaTokenService.HederaToken memory token = IHederaTokenService
            .HederaToken({
                name: name_,
                symbol: symbol_,
                treasury: address(this),
                memo: memo_,
                tokenSupplyType: false,
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

    // ---------------------------------------------------------------------
    // Key Management (Add / Deprecated Drop)
    // ---------------------------------------------------------------------

    /**
     * @notice Add (rotate in) selected keys to point to this contract (CONTRACT_ID key variant).
     */
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

    /**
     * @notice Update treasury address (newTreasury must be associated & able to hold token).
     */
    function updateTreasury(
        address newTreasury
    ) external onlyOwner onlyInitialized {
        if (newTreasury == address(0)) revert ZeroAddress();

        IHederaTokenService.HederaToken memory partialTokenInfo;
        partialTokenInfo.treasury = newTreasury;
        partialTokenInfo.expiry = IHederaTokenService.Expiry(0, address(0), 0); // unchanged

        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.updateTokenInfo.selector,
                hederaTokenAddress,
                partialTokenInfo
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

    // ---------------------------------------------------------------------
    // Metadata Views
    // ---------------------------------------------------------------------
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

    // ---------------------------------------------------------------------
    // Core Views
    // ---------------------------------------------------------------------
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

    // ---------------------------------------------------------------------
    // Guarded State-Changing ERC721 Interface
    // ---------------------------------------------------------------------

    /**
     * @notice Owner-only; only when this contract (treasury) owns tokenId.
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
     * @notice Owner-only operator approval for treasury-held tokens (or future).
     * Optional pre-condition enforced (treasury must hold at least one).
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
     * @notice Owner-only delegated transfer:
     *  - If treasury owns tokenId: distribution from treasury.
     *  - If user owns tokenId: wrapper must be underlying-approved (approve(wrapper, tokenId) or operator).
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyInitialized onlyOwner {
        address actualOwner = IERC721(hederaTokenAddress).ownerOf(tokenId);

        if (actualOwner == address(this)) {
            if (from != address(this)) {
                from = address(this);
            }
            IERC721(hederaTokenAddress).transferFrom(from, to, tokenId);
            emit TreasuryTransfer(from, to, tokenId);
            return;
        }

        if (!_isWrapperAuthorized(tokenId)) {
            revert WrapperTransferNotAuthorized(tokenId, actualOwner);
        }
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

    // ---------------------------------------------------------------------
    // Association (Direct Precompile Calls with msg.sender Context)
    // ---------------------------------------------------------------------

    /**
     * @notice Associate caller with token (idempotent). Required before KYC grant / holding (if KYC enforced).
     */
    function associate() external onlyInitialized {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.associateToken.selector,
                msg.sender,
                hederaTokenAddress
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS && rc != TOKEN_ALREADY_ASSOCIATED) {
            revert HtsCallFailed(
                IHederaTokenService.associateToken.selector,
                rc
            );
        }
    }

    /**
     * @notice Dissociate caller from token (must have zero balance & no pending NFTs).
     */
    function dissociate() external onlyInitialized {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.dissociateToken.selector,
                msg.sender,
                hederaTokenAddress
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS) {
            revert HtsCallFailed(
                IHederaTokenService.dissociateToken.selector,
                rc
            );
        }
    }

    // ---------------------------------------------------------------------
    // Internal Mint
    // ---------------------------------------------------------------------
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

        // Transfer newly minted NFT from treasury (this) to recipient
        IERC721(hederaTokenAddress).transferFrom(address(this), to, tokenId);
        emit Minted(to, tokenId);
        return tokenId;
    }

    // ---------------------------------------------------------------------
    // Authorization Helpers
    // ---------------------------------------------------------------------
    function _isWrapperAuthorized(
        uint256 tokenId
    ) internal view returns (bool) {
        address owner_ = IERC721(hederaTokenAddress).ownerOf(tokenId);
        if (owner_ == address(this)) return true;
        address approved = IERC721(hederaTokenAddress).getApproved(tokenId);
        if (approved == address(this)) return true;
        if (IERC721(hederaTokenAddress).isApprovedForAll(owner_, address(this)))
            return true;
        return false;
    }

    /// @notice Underlying HTS token address (alias for integrators).
    function underlying() external view returns (address) {
        return hederaTokenAddress;
    }

    // ---------------------------------------------------------------------
    // Key Builders
    // ---------------------------------------------------------------------
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

    // ---------------------------------------------------------------------
    // ERC165
    // ---------------------------------------------------------------------
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------------
    // Utils
    // ---------------------------------------------------------------------
    function _toI64(uint256 x) internal pure returns (int64) {
        if (x > INT64_MAX) revert CastOverflow();
        return int64(uint64(x));
    }
}
