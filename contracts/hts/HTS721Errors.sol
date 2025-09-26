// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

error ZeroAddress();
error HtsCallFailed(bytes4 selector, int32 rc);
error TokenCreationFailed();
error MetadataTooLarge();
error TokenNotCreated();
error CastOverflow();
error NotAuthorized();
error AlreadyInitialized();
error NotInitialized();
error LengthMismatch();
error EnumerationTooCostly();
error IndexOutOfBounds();
