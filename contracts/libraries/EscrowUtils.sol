// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../UserEscrow.sol";

library EscrowUtils {
    // Custom errors
    error EscrowExists();
    error EscrowExistsForPool();
    error InvalidPoolAddress();
    error ZeroAddress();
    error ArrayLengthMismatch();
    error EmptyArray();

    function validateCreateEscrow(address user, mapping(address => address) storage userEscrows) internal view {
        if (userEscrows[user] != address(0)) revert EscrowExists();
    }

    function validateCreateEscrowForPool(
        address poolAddress,
        address user,
        mapping(address => mapping(address => address)) storage userPoolEscrows
    ) internal view {
        if (poolAddress == address(0)) revert InvalidPoolAddress();
        if (userPoolEscrows[user][poolAddress] != address(0)) revert EscrowExistsForPool();
    }

    function validateWhitelistParams(address target) internal pure {
        if (target == address(0)) revert ZeroAddress();
    }

    function validateBatchWhitelistParams(
        address[] calldata targets,
        bool[] calldata whitelisted
    ) internal pure {
        if (targets.length != whitelisted.length) revert ArrayLengthMismatch();
        if (targets.length == 0) revert EmptyArray();
    }

    function validateBatchAddParams(address[] calldata targets) internal pure {
        if (targets.length == 0) revert EmptyArray();
    }

    function validateAddressInLoop(address target) internal pure {
        if (target == address(0)) revert ZeroAddress();
    }

    function createAndRegisterEscrow(
        address owner,
        uint256 ownershipDelay,
        address factory,
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls,
        address usdcAddress,
        mapping(address => bool) storage escrowExists,
        uint256 totalEscrows
    ) internal returns (address escrowAddr, uint256 newTotalEscrows) {
        UserEscrow escrow = new UserEscrow(
            owner,          // _owner
            poolAddress,    // _poolAddress
            approvers,      // _approvers
            threshold,      // _threshold
            maxCalls,       // _maxCalls
            ownershipDelay, // _ownershipDelay
            factory,        // _factory
            factory,        // _whitelist (Use factory as whitelistManager for backward compatibility)
            usdcAddress     // _usdc
        );

        escrowAddr = address(escrow);
        escrowExists[escrowAddr] = true;
        unchecked { newTotalEscrows = totalEscrows + 1; }
    }
}