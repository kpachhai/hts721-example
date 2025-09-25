// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

error NotAuthorized();
error ZeroAddress();
error InsufficientBalance();
error HtsCallFailed(bytes4 selector, int32 rc);
error TokenCreationFailed();
error InvalidScanLimit();
error EnumerationTooCostly();
error IndexOutOfBounds();
error TransferCallerNotOwnerNorApproved();
error MetadataTooLarge();
error TokenNotCreated();
error ContractNotApprovedToTransfer();
error BurnFailed();
error CastOverflow();
error LengthMismatch();
error OnlyAccountCanAssociateItself();
error OnlyAccountCanDisassociateItself();
