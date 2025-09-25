// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";

import {HTSManagement} from "./HTSManagement.sol";
import {ZeroAddress, InsufficientBalance, HtsCallFailed, TokenCreationFailed, InvalidScanLimit, EnumerationTooCostly, TransferCallerNotOwnerNorApproved, MetadataTooLarge, TokenNotCreated, CastOverflow} from "./HTS721Errors.sol";

/**
 * @title HTS-721: The Hedera Token Service-backed ERC-721 facade
 * @notice Abstract base that creates and manages a native HTS NFT while exposing an ERC-721-compatible API.
 */
abstract contract HTS721 is ERC165, IERC721, IERC721Metadata, HTSManagement {
    // Hedera SUCCESS response code (inherited also in HTSManagement)
    // int32 internal constant SUCCESS = 22; // already in HTSManagement

    // 90 days in seconds
    int32 internal constant DEFAULT_AUTO_RENEW_PERIOD = 7776000;

    // The address of the underlying HTS token this contract manages.
    address public immutable hederaTokenAddress;

    // Small non-empty default metadata (<=100 bytes as per HTS limit)
    bytes private constant DEFAULT_METADATA = hex"01";
    uint256 private constant INT64_MAX = 0x7fffffffffffffff;

    // Key type bit masks (same semantics as KeyHelper)
    uint256 internal constant KEY_ADMIN = 1;
    uint256 internal constant KEY_KYC = 2;
    uint256 internal constant KEY_FREEZE = 4;
    uint256 internal constant KEY_WIPE = 8;
    uint256 internal constant KEY_SUPPLY = 16;
    uint256 internal constant KEY_FEE = 32;
    uint256 internal constant KEY_PAUSE = 64;

    struct ManagementConfig {
        address controller; // if zero, defaults to address(this)
        bool admin;
        bool kyc;
        bool freeze;
        bool wipe;
        bool supply;
        bool feeSchedule;
        bool pause;
        address treasury; // defaults to this contract
        bool freezeDefault;
        address autoRenewAccount; // defaults to msg.sender if zero
        int32 autoRenewPeriod; // defaults to DEFAULT_AUTO_RENEW_PERIOD if zero
    }

    event HBARReceived(address indexed from, uint256 amount);
    event HBARWithdrawn(address indexed to, uint256 amount);
    event EnumerationScanLimitUpdated(uint256 previous, uint256 next);
    event MaxObservedSerialBumped(uint256 previous, uint256 next);

    /**
     * @notice Creates the underlying HTS Non-Fungible Token and configures this contract as its manager.
     * @dev Constructor is payable; forwards msg.value to the HTS precompile to cover token creation fees.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory memo_,
        ManagementConfig memory cfg
    ) payable {
        address controller = cfg.controller == address(0)
            ? address(this)
            : cfg.controller;

        uint256 n;
        if (cfg.admin) n++;
        if (cfg.kyc) n++;
        if (cfg.freeze) n++;
        if (cfg.wipe) n++;
        if (cfg.supply) n++;
        if (cfg.feeSchedule) n++;
        if (cfg.pause) n++;

        IHederaTokenService.TokenKey[]
            memory keys = new IHederaTokenService.TokenKey[](n);
        IHederaTokenService.KeyValue memory kv;
        kv.contractId = controller;

        uint256 i;
        if (cfg.admin) keys[i++] = IHederaTokenService.TokenKey(KEY_ADMIN, kv);
        if (cfg.kyc) keys[i++] = IHederaTokenService.TokenKey(KEY_KYC, kv);
        if (cfg.freeze)
            keys[i++] = IHederaTokenService.TokenKey(KEY_FREEZE, kv);
        if (cfg.wipe) keys[i++] = IHederaTokenService.TokenKey(KEY_WIPE, kv);
        if (cfg.supply)
            keys[i++] = IHederaTokenService.TokenKey(KEY_SUPPLY, kv);
        if (cfg.feeSchedule)
            keys[i++] = IHederaTokenService.TokenKey(KEY_FEE, kv);
        if (cfg.pause) keys[i++] = IHederaTokenService.TokenKey(KEY_PAUSE, kv);

        address treasury = cfg.treasury == address(0)
            ? address(this)
            : cfg.treasury;
        bool freezeDefault = cfg.freezeDefault;

        address autoRenewAccount = cfg.autoRenewAccount == address(0)
            ? msg.sender
            : cfg.autoRenewAccount;
        int32 autoRenewPeriod = cfg.autoRenewPeriod == int32(0)
            ? DEFAULT_AUTO_RENEW_PERIOD
            : cfg.autoRenewPeriod;

        IHederaTokenService.HederaToken memory hederaToken = IHederaTokenService
            .HederaToken({
                name: name_,
                symbol: symbol_,
                treasury: treasury,
                memo: memo_,
                tokenSupplyType: true, // INFINITE supply
                maxSupply: 0,
                freezeDefault: freezeDefault,
                tokenKeys: keys,
                expiry: IHederaTokenService.Expiry(
                    0,
                    autoRenewAccount,
                    autoRenewPeriod
                )
            });

        // Forward value to fund creation
        (bool ok, bytes memory result) = HTS_PRECOMPILE_ADDRESS.call{
            value: msg.value
        }(
            abi.encodeWithSelector(
                IHederaTokenService.createNonFungibleToken.selector,
                hederaToken
            )
        );
        if (!ok)
            revert HtsCallFailed(
                IHederaTokenService.createNonFungibleToken.selector,
                int32(-1)
            );

        (int32 rc, address tokenAddress) = abi.decode(result, (int32, address));
        if (!(rc == SUCCESS && tokenAddress != address(0)))
            revert TokenCreationFailed();

        hederaTokenAddress = tokenAddress;
    }

    // Expose token address for HTSManagement mixin
    function _hederaTokenAddress() internal view override returns (address) {
        return hederaTokenAddress;
    }

    // Accept accidental HBAR; allow sweeping via withdrawHBAR
    receive() external payable {
        emit HBARReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        emit HBARReceived(msg.sender, msg.value);
    }

    function withdrawHBAR(
        address payable to,
        uint256 amount
    ) external virtual onlyManagementAuth {
        if (to == address(0)) revert ZeroAddress();
        if (address(this).balance < amount) revert InsufficientBalance();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert HtsCallFailed(bytes4(0), int32(-1));
        emit HBARWithdrawn(to, amount);
    }

    // =========================================================================
    // ERC721 METADATA VIEW FUNCTIONS (IERC721Metadata)
    // =========================================================================

    function name() external view virtual override returns (string memory) {
        return IERC721Metadata(hederaTokenAddress).name();
    }

    function symbol() external view virtual override returns (string memory) {
        return IERC721Metadata(hederaTokenAddress).symbol();
    }

    function tokenURI(
        uint256 tokenId
    ) external view virtual override returns (string memory) {
        return IERC721Metadata(hederaTokenAddress).tokenURI(tokenId);
    }

    // =========================================================================
    // ERC721 VIEW FUNCTIONS (IERC721)
    // =========================================================================

    function balanceOf(
        address owner
    ) external view virtual override returns (uint256) {
        return IERC721(hederaTokenAddress).balanceOf(owner);
    }

    function ownerOf(
        uint256 tokenId
    ) external view virtual override returns (address) {
        return IERC721(hederaTokenAddress).ownerOf(tokenId);
    }

    function getApproved(
        uint256 tokenId
    ) external view virtual override returns (address) {
        return IERC721(hederaTokenAddress).getApproved(tokenId);
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) external view virtual override returns (bool) {
        return IERC721(hederaTokenAddress).isApprovedForAll(owner, operator);
    }

    // =========================================================================
    // ERC721 STATE-CHANGING FUNCTIONS (IERC721)
    // =========================================================================

    function approve(address to, uint256 tokenId) external virtual override {
        IERC721(hederaTokenAddress).approve(to, tokenId);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) external virtual override {
        IERC721(hederaTokenAddress).setApprovalForAll(operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        IERC721(hederaTokenAddress).transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external virtual override {
        this.safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory
    ) external virtual override {
        // Policy check
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert TransferCallerNotOwnerNorApproved();
        // The recipient must be associated (or have auto-association available).
        transferFrom(from, to, tokenId);
        // TODO: Enable onERC721Received when HTS precompile supports it.
    }

    // ========================================================================
    // ERC721 SAFE MINT-LIKE FLOW FOR CONTRACT OWNER
    // ========================================================================
    function _safeMint(address to) internal virtual {
        _safeMint(to, "");
    }

    function _safeMint(address to, bytes memory) internal virtual {
        _mint(to, DEFAULT_METADATA);
        // TODO: Enable receiver check once supported by HTS precompile
    }

    function _mint(address to) internal virtual returns (uint256) {
        return _mint(to, DEFAULT_METADATA);
    }

    /**
     * @notice Mints a new NFT to the treasury (this contract) and then transfers it to `to`.
     */
    function _mint(
        address to,
        bytes memory metadata
    ) internal virtual returns (uint256) {
        if (hederaTokenAddress == address(0)) revert TokenNotCreated();
        if (to == address(0)) revert ZeroAddress();
        if (metadata.length > 100) revert MetadataTooLarge();

        // 1) Mint to treasury (this contract)
        bytes[] memory metadataArray = new bytes[](1);
        metadataArray[0] = metadata;

        (bool ok, bytes memory result) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.mintToken.selector,
                hederaTokenAddress,
                int64(0),
                metadataArray
            )
        );
        if (!ok)
            revert HtsCallFailed(
                IHederaTokenService.mintToken.selector,
                int32(-1)
            );

        (int32 rc, , int64[] memory serialNumbers) = abi.decode(
            result,
            (int32, int64, int64[])
        );
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.mintToken.selector, rc);
        if (serialNumbers.length != 1)
            revert HtsCallFailed(IHederaTokenService.mintToken.selector, rc);

        uint256 tokenId = uint256(uint64(serialNumbers[0]));

        // 2) Transfer from treasury to recipient (requires association or auto-association)
        IERC721(hederaTokenAddress).transferFrom(address(this), to, tokenId);

        return tokenId;
    }

    // =========================================================================
    // INTERNAL & HELPER FUNCTIONS
    // =========================================================================

    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) internal view virtual returns (bool) {
        address owner = IERC721(hederaTokenAddress).ownerOf(tokenId);
        return (spender == owner ||
            IERC721(hederaTokenAddress).getApproved(tokenId) == spender ||
            IERC721(hederaTokenAddress).isApprovedForAll(owner, spender));
    }

    // =========================================================================
    // ERC165 SUPPORT
    // =========================================================================

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // --------------------- internal helpers ---------------------
    function _toI64(uint256 x) internal pure returns (int64) {
        if (x > INT64_MAX) revert CastOverflow();
        return int64(uint64(x));
    }

    function _htsTotalSupply() internal view returns (uint256) {
        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.staticcall(
            abi.encodeWithSelector(
                IHederaTokenService.getTokenInfo.selector,
                hederaTokenAddress
            )
        );
        if (!ok)
            revert HtsCallFailed(
                IHederaTokenService.getTokenInfo.selector,
                int32(-1)
            );
        (int32 rc, IHederaTokenService.TokenInfo memory info) = abi.decode(
            res,
            (int32, IHederaTokenService.TokenInfo)
        );
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.getTokenInfo.selector, rc);
        return uint256(uint64(info.totalSupply));
    }

    // Optional public totalSupply view for convenience (not claiming Enumerable)
    function totalSupply() external view virtual returns (uint256) {
        return _htsTotalSupply();
    }
}
