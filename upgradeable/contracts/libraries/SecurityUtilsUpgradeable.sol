// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

/// @title SecurityUtilsUpgradeable
/// @notice Library for security validation functions (upgradeable version)
library SecurityUtilsUpgradeable {
    using ECDSAUpgradeable for bytes32;

    /// @notice Validate withdrawal target to prevent malicious contracts
    function isValidWithdrawalTarget(address target, address owner, address whitelistManager)
        internal
        view
        returns (bool)
    {
        // Allow owner or whitelisted addresses
        if (target == owner) return true;

        // Check whitelist via static call to avoid adding dependency
        (bool success, bytes memory data) = whitelistManager.staticcall(
            abi.encodeWithSignature("isWhitelisted(address)", target)
        );

        return success && data.length >= 32 && abi.decode(data, (bool));
    }

    /// @notice Validate token contract to prevent malicious tokens
    function isValidTokenContract(address token) internal view returns (bool) {
        // Basic validation: must be a contract with proper ERC20 interface
        if (token.code.length == 0) return false;

        try IERC20Upgradeable(token).totalSupply() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Enhanced signature validation with anti-malleability protection
    function validateSignature(
        bytes32 messageHash,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool) {
        if (signature.length != 65) return false;

        // Extract signature components
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Check for signature malleability (OpenZeppelin ECDSA protection)
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return false;
        }

        // Recover signer and validate
        address recovered = ecrecover(messageHash, v, r, s);
        return recovered == expectedSigner && recovered != address(0);
    }

    /// @notice Safe math operations to prevent overflow/underflow
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a + b >= a, "SecurityUtils: addition overflow");
        return a + b;
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SecurityUtils: subtraction underflow");
        return a - b;
    }

    /// @notice Gas limit check to prevent DoS attacks
    function checkGasLimit(uint256 requiredGas) internal view {
        require(gasleft() >= requiredGas, "SecurityUtils: insufficient gas");
    }

    /// @notice Enhanced ETH transfer with reentrancy protection
    function secureETHTransfer(address payable to, uint256 amount, address whitelistManager) internal {
        if (to.code.length == 0) {
            // EOA - use transfer() which limits gas to 2300
            to.transfer(amount);
        } else {
            // Contract - ensure it's whitelisted and use limited gas call
            require(isValidWithdrawalTarget(to, address(this), whitelistManager), "SecurityUtils: invalid target");
            (bool ok, ) = to.call{value: amount, gas: 10000}("");
            require(ok, "SecurityUtils: ETH transfer failed");
        }
    }
}
