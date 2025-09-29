// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

error NotOwner();
error AlreadyInitialized();
error NotInitialized();
error ZeroAddress();
error TokenCreationFailed();
error HtsCallFailed(bytes4 sel, int32 rc);
error MetadataTooLarge();
error CastOverflow();
error TokenNotCreated();
error EnumerationTooCostly();
error IndexOutOfBounds();
