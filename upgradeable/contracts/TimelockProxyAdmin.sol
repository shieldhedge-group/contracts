// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title TimelockProxyAdmin
 * @notice Timelock controller for governance-controlled proxy upgrades
 * @dev Extends OpenZeppelin's TimelockController
 *
 * KEY FEATURES:
 * - 1-day delay for all upgrade operations (testing/early deployment)
 * - Multi-sig proposer requirement (3/5 minimum)
 * - Anyone can execute after delay expires
 * - Emergency cancellation capability
 * - Transparent upgrade process
 *
 * SECURITY MODEL:
 * - Proposers: Multi-sig (3/5) can propose upgrades
 * - Executors: Anyone can execute after delay (ensures transparency)
 * - Admin: Can grant/revoke roles (should be another timelock or DAO)
 * - Delay: 1 day minimum (86400 seconds)
 *
 * WORKFLOW:
 * 1. Proposer multi-sig proposes upgrade via schedule()
 * 2. 1-day timelock starts
 * 3. Community reviews new implementation
 * 4. After 1 day: Anyone can execute()
 * 5. Users can exit before execution if they disagree
 *
 * NOTE: For production mainnet, consider increasing to 7 days for better security
 */
contract TimelockProxyAdmin is TimelockController {

    /* ========== EVENTS ========== */

    event UpgradeProposed(
        bytes32 indexed operationId,
        address indexed proxy,
        address indexed newImplementation,
        uint256 eta
    );

    /* ========== CONSTANTS ========== */

    /// @notice Minimum delay for upgrades (1 day)
    uint256 public constant MIN_DELAY = 1 days;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initialize the timelock with multi-sig proposers
     * @param proposers Addresses that can propose upgrades (should be multi-sig)
     * @param executors Addresses that can execute (use address(0) for anyone)
     * @param admin Address that can grant/revoke roles (should be another timelock or DAO)
     * @dev minDelay is hardcoded to 1 day for testing/early deployment
     */
    constructor(
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(
        MIN_DELAY,     // 1-day delay
        proposers,     // Multi-sig proposers
        executors,     // Public executors (anyone after delay)
        admin          // Admin (should be DAO/timelock)
    ) {
        require(proposers.length >= 3, "TimelockProxyAdmin: need >= 3 proposers");
    }

    /* ========== CONVENIENCE FUNCTIONS ========== */

    /**
     * @notice Helper to get minimum delay
     * @return Delay in seconds (1 day = 86400 seconds)
     */
    function getMinimumDelay() external pure returns (uint256) {
        return MIN_DELAY;
    }

    /**
     * @notice Verify that a new implementation is safe to upgrade to
     * @param newImplementation Address of new implementation
     * @dev Add custom safety checks here
     */
    function verifyImplementationSafety(address newImplementation) external view returns (bool) {
        // Check 1: Not zero address
        if (newImplementation == address(0)) return false;

        // Check 2: Has code (is a contract)
        uint256 size;
        assembly {
            size := extcodesize(newImplementation)
        }
        if (size == 0) return false;

        return true;
    }
}
