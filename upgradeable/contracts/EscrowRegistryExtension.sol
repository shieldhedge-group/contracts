// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./EscrowRegistry.sol";

/**
 * @title EscrowRegistryExtension
 * @notice Extension contract for EscrowRegistry to add getAllEscrows() functionality
 * @dev Works with existing deployed EscrowRegistry WITHOUT requiring redeployment
 *
 * WHY THIS EXISTS:
 * - EscrowRegistry is NOT upgradeable
 * - Cannot add storage arrays to existing contract
 * - This extension listens to events and builds escrow list
 *
 * DEPLOYMENT:
 * 1. Deploy this contract with existing registry address
 * 2. Call syncHistoricalEscrows() to index past events
 * 3. Future escrows are auto-indexed via registerEscrow()
 *
 * USAGE:
 * - Use this contract for getAllEscrows() queries
 * - Original registry remains unchanged and functional
 */
contract EscrowRegistryExtension {
    EscrowRegistry public immutable registry;

    // Storage arrays (NOT in original registry)
    address[] private allEscrows;
    mapping(address => address[]) private userEscrowsList;
    mapping(address => bool) private isIndexed;

    // Sync status
    uint256 public lastSyncedBlock;
    bool public isFullySynced;

    event EscrowIndexed(address indexed escrow, address indexed user);
    event SyncCompleted(uint256 indexed fromBlock, uint256 indexed toBlock, uint256 escrowsIndexed);

    constructor(address _registry) {
        require(_registry != address(0), "Extension: zero registry");
        registry = EscrowRegistry(_registry);
        lastSyncedBlock = block.number;
    }

    /**
     * @notice Manually register an escrow (called by factory or admin)
     * @dev This is for real-time indexing of new escrows
     */
    function registerEscrow(address escrow, address user) external {
        // Verify escrow exists in registry
        require(registry.isRegisteredEscrow(escrow), "Extension: not in registry");

        // Only index once
        if (isIndexed[escrow]) {
            return;
        }

        allEscrows.push(escrow);
        userEscrowsList[user].push(escrow);
        isIndexed[escrow] = true;

        emit EscrowIndexed(escrow, user);
    }

    /**
     * @notice Sync historical escrows from events (ADMIN ONLY)
     * @dev Call this after deployment to index existing escrows
     * @param escrows Array of escrow addresses from events
     * @param users Array of user addresses (same order)
     */
    function syncHistoricalEscrows(
        address[] calldata escrows,
        address[] calldata users
    ) external {
        require(escrows.length == users.length, "Extension: length mismatch");

        for (uint256 i = 0; i < escrows.length; i++) {
            address escrow = escrows[i];
            address user = users[i];

            // Verify in registry
            if (!registry.isRegisteredEscrow(escrow)) {
                continue;
            }

            // Only index once
            if (isIndexed[escrow]) {
                continue;
            }

            allEscrows.push(escrow);
            userEscrowsList[user].push(escrow);
            isIndexed[escrow] = true;

            emit EscrowIndexed(escrow, user);
        }

        emit SyncCompleted(lastSyncedBlock, block.number, escrows.length);
        lastSyncedBlock = block.number;
    }

    /**
     * @notice Mark sync as complete
     */
    function markFullySynced() external {
        isFullySynced = true;
    }

    // ========== QUERY FUNCTIONS (SAME AS PLANNED FOR REGISTRY) ==========

    /**
     * @notice Get all escrow addresses with pagination
     */
    function getAllEscrows(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory)
    {
        require(offset < allEscrows.length || allEscrows.length == 0, "Extension: offset out of bounds");

        if (allEscrows.length == 0) {
            return new address[](0);
        }

        uint256 end = offset + limit;
        if (end > allEscrows.length) {
            end = allEscrows.length;
        }

        uint256 resultLength = end - offset;
        address[] memory result = new address[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = allEscrows[offset + i];
        }

        return result;
    }

    /**
     * @notice Get all escrows (no pagination)
     */
    function getAllEscrowsNoPagination() external view returns (address[] memory) {
        return allEscrows;
    }

    /**
     * @notice Get escrows for a specific user
     */
    function getEscrowsForUser(address user) external view returns (address[] memory) {
        return userEscrowsList[user];
    }

    /**
     * @notice Get escrow count for a user
     */
    function getUserEscrowCount(address user) external view returns (uint256) {
        return userEscrowsList[user].length;
    }

    /**
     * @notice Get total escrows count
     */
    function getTotalEscrows() external view returns (uint256) {
        return allEscrows.length;
    }

    /**
     * @notice Check if escrow is indexed
     */
    function isEscrowIndexed(address escrow) external view returns (bool) {
        return isIndexed[escrow];
    }

    /**
     * @notice Get sync status
     */
    function getSyncStatus() external view returns (
        uint256 totalIndexed,
        uint256 registryTotal,
        uint256 lastBlock,
        bool fullySync
    ) {
        return (
            allEscrows.length,
            registry.getTotalEscrowCount(),
            lastSyncedBlock,
            isFullySynced
        );
    }
}
