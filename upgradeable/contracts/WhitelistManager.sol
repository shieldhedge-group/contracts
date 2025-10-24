// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IEscrowRegistry.sol";

contract WhitelistManager is Ownable {
    mapping(address => bool) public whitelist;
    IEscrowRegistry public escrowRegistry;

    event TargetWhitelisted(address indexed target, bool whitelisted);
    event EscrowRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    constructor(address _escrowRegistry) {
        require(_escrowRegistry != address(0), "WhitelistManager: zero registry");
        escrowRegistry = IEscrowRegistry(_escrowRegistry);
    }

    function setEscrowRegistry(address _escrowRegistry) external onlyOwner {
        require(_escrowRegistry != address(0), "WhitelistManager: zero registry");
        address oldRegistry = address(escrowRegistry);
        escrowRegistry = IEscrowRegistry(_escrowRegistry);
        emit EscrowRegistryUpdated(oldRegistry, _escrowRegistry);
    }

    function setWhitelist(address target, bool whitelisted) external onlyOwner {
        require(target != address(0), "WhitelistManager: zero address");
        whitelist[target] = whitelisted;
        emit TargetWhitelisted(target, whitelisted);
    }

    function batchSetWhitelist(address[] calldata targets, bool[] calldata whitelisted) external onlyOwner {
        require(targets.length == whitelisted.length, "WhitelistManager: length mismatch");
        require(targets.length > 0, "WhitelistManager: empty array");

        for (uint256 i = 0; i < targets.length; i++) {
            require(targets[i] != address(0), "WhitelistManager: zero address");
            whitelist[targets[i]] = whitelisted[i];
            emit TargetWhitelisted(targets[i], whitelisted[i]);
        }
    }

    function batchAddToWhitelist(address[] calldata targets) external onlyOwner {
        require(targets.length > 0, "WhitelistManager: empty array");

        for (uint256 i = 0; i < targets.length; i++) {
            require(targets[i] != address(0), "WhitelistManager: zero address");
            whitelist[targets[i]] = true;
            emit TargetWhitelisted(targets[i], true);
        }
    }

    /// @notice Check if target is whitelisted (second parameter kept for interface compatibility)
    /// @param target The address to check
    /// @return bool True if target is whitelisted
    /// @dev Second parameter (caller) is unused but kept for backward compatibility
    function isWhitelistedWithCaller(address target, address /* caller */) external view returns (bool) {
        // Only allow explicitly whitelisted targets
        // Self-call bypass removed for security - UserEscrow.sol:231 already blocks self-calls
        return whitelist[target];
    }

    /// @notice Check if an address is whitelisted
    /// @param target The address to check
    /// @return bool True if the target is whitelisted
    function isWhitelisted(address target) external view returns (bool) {
        return whitelist[target];
    }

    /// @notice Same as isWhitelisted, kept for explicit clarity
    /// @param target The address to check
    /// @return bool True if the target is explicitly whitelisted
    function isExplicitlyWhitelisted(address target) external view returns (bool) {
        return whitelist[target];
    }
}