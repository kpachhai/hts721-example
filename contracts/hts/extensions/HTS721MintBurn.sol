// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "../HTS721Core.sol";
import "../interfaces/IHTS721MintBurn.sol";
import "../HTS721Errors.sol";
import {IHederaTokenService} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-token-service/IHederaTokenService.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @dev Mint (treasury->recipient) + burn utilities.
 * Requires SUPPLY key on this contract.
 */
abstract contract HTS721MintBurn is HTS721Core, IHTS721MintBurn {
    event Burn(uint256 serial, address owner);

    function mintTo(
        address to,
        bytes calldata metadata
    ) external onlyOwner returns (uint256) {
        if (to == address(0)) revert ZeroAddress();
        uint256 serial = _mintPrimitive(metadata);
        // Move newly minted serial (treasury -> to)
        IERC721(hederaTokenAddress).transferFrom(address(this), to, serial);
        emit MintForward(serial, to);
        return serial;
    }

    function burn(uint256 serial) external onlyOwner {
        _burnTreasuryOwned(serial);
    }

    function burnFrom(address owner_, uint256 serial) external onlyOwner {
        // Pull if user-owned
        if (IERC721(hederaTokenAddress).ownerOf(serial) != address(this)) {
            IERC721(hederaTokenAddress).transferFrom(
                owner_,
                address(this),
                serial
            );
        }
        _burnTreasuryOwned(serial);
    }

    function _burnTreasuryOwned(uint256 serial) internal onlyInit {
        if (hederaTokenAddress == address(0)) revert TokenNotCreated();
        // Ensure now owned by treasury
        if (IERC721(hederaTokenAddress).ownerOf(serial) != address(this)) {
            revert TokenNotCreated(); // using existing error to stay minimal
        }
        int64[] memory serials = new int64[](1);
        serials[0] = _toI64(serial);

        (bool ok, bytes memory res) = HTS_PRECOMPILE_ADDRESS.call(
            abi.encodeWithSelector(
                IHederaTokenService.burnToken.selector,
                hederaTokenAddress,
                int64(0),
                serials
            )
        );
        int32 rc = ok ? abi.decode(res, (int32)) : int32(-1);
        if (rc != SUCCESS)
            revert HtsCallFailed(IHederaTokenService.burnToken.selector, rc);
        emit Burn(serial, address(this));
    }
}
