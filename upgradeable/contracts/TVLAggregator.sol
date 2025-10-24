// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./interfaces/ITVLProvider.sol";
import "./EscrowRegistry.sol";
import "./EscrowRegistryExtension.sol";
import "./UserEscrowUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TVLAggregator
 * @notice DeFiLlama-compatible TVL aggregator for SolHedge protocol
 * @dev Implements standard interfaces for easy integration with analytics tools
 *
 * USAGE FOR DEFILLAMA:
 * 1. Query getTotalValueLocked() for total TVL
 * 2. Query getTVLByToken() for token breakdown
 * 3. Query getAllUsers() for unique user count
 *
 * SUBGRAPH EVENTS:
 * - EscrowRegistered (from EscrowRegistry)
 * - DepositedETH, DepositedToken (from UserEscrow)
 * - WithdrawnETH, WithdrawnToken (from UserEscrow)
 */
contract TVLAggregator is ITVLProvider {
    EscrowRegistry public immutable registry;
    EscrowRegistryExtension public immutable extension;

    // Known tokens to track (can be updated)
    address[] public trackedTokens;
    mapping(address => bool) public isTrackedToken;

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event TVLUpdated(uint256 totalTVL, uint256 timestamp);

    constructor(address _registry, address _extension, address[] memory _initialTokens) {
        require(_registry != address(0), "TVLAggregator: zero registry");
        require(_extension != address(0), "TVLAggregator: zero extension");
        registry = EscrowRegistry(_registry);
        extension = EscrowRegistryExtension(_extension);

        // Add initial tracked tokens
        for (uint256 i = 0; i < _initialTokens.length; i++) {
            if (_initialTokens[i] != address(0) && !isTrackedToken[_initialTokens[i]]) {
                trackedTokens.push(_initialTokens[i]);
                isTrackedToken[_initialTokens[i]] = true;
                emit TokenAdded(_initialTokens[i]);
            }
        }
    }

    /**
     * @notice Get total ETH locked across all escrows
     * @dev DeFiLlama uses this for TVL calculation
     */
    function getTotalValueLocked() external view override returns (uint256) {
        address[] memory escrows = extension.getAllEscrowsNoPagination();
        uint256 totalETH = 0;

        for (uint256 i = 0; i < escrows.length; i++) {
            totalETH += escrows[i].balance;
        }

        return totalETH;
    }

    /**
     * @notice Get TVL breakdown by token
     * @dev Returns all tracked tokens and their amounts
     */
    function getTVLByToken() external view override returns (
        address[] memory tokens,
        uint256[] memory amounts
    ) {
        address[] memory escrows = extension.getAllEscrowsNoPagination();

        tokens = new address[](trackedTokens.length + 1); // +1 for ETH
        amounts = new uint256[](trackedTokens.length + 1);

        // ETH (native token) at index 0
        tokens[0] = address(0);
        for (uint256 i = 0; i < escrows.length; i++) {
            amounts[0] += escrows[i].balance;
        }

        // ERC20 tokens
        for (uint256 j = 0; j < trackedTokens.length; j++) {
            tokens[j + 1] = trackedTokens[j];

            for (uint256 i = 0; i < escrows.length; i++) {
                amounts[j + 1] += IERC20(trackedTokens[j]).balanceOf(escrows[i]);
            }
        }

        return (tokens, amounts);
    }

    /**
     * @notice Get all unique users
     * @dev Extracts unique owners from all escrows
     */
    function getAllUsers() external view override returns (address[] memory) {
        address[] memory escrows = extension.getAllEscrowsNoPagination();
        address[] memory users = new address[](escrows.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < escrows.length; i++) {
            // Call owner() without casting to specific contract type
            (bool success, bytes memory data) = escrows[i].staticcall(abi.encodeWithSignature("owner()"));
            require(success && data.length > 0, "TVLAggregator: failed to get owner");
            address owner = abi.decode(data, (address));

            // Check if user already added
            bool exists = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (users[j] == owner) {
                    exists = true;
                    break;
                }
            }

            if (!exists) {
                users[uniqueCount] = owner;
                uniqueCount++;
            }
        }

        // Resize array to actual unique count
        address[] memory result = new address[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            result[i] = users[i];
        }

        return result;
    }

    /**
     * @notice Get TVL for a specific user
     * @param user User address
     */
    function getUserTVL(address user) external view override returns (uint256) {
        address[] memory userEscrows = extension.getEscrowsForUser(user);
        uint256 totalTVL = 0;

        for (uint256 i = 0; i < userEscrows.length; i++) {
            totalTVL += userEscrows[i].balance;

            // Add ERC20 token balances
            for (uint256 j = 0; j < trackedTokens.length; j++) {
                totalTVL += IERC20(trackedTokens[j]).balanceOf(userEscrows[i]);
            }
        }

        return totalTVL;
    }

    // ========== DEFILLAMA SPECIFIC HELPERS ==========

    /**
     * @notice Get TVL data in DeFiLlama adapter format
     * @return tokens Array of token addresses
     * @return balances Array of token amounts
     */
    function getTVLForDeFiLlama() external view returns (
        address[] memory tokens,
        uint256[] memory balances
    ) {
        return this.getTVLByToken();
    }

    /**
     * @notice Get total unique user count
     * @dev Used by analytics dashboards
     */
    function getTotalUsers() external view returns (uint256) {
        address[] memory escrows = extension.getAllEscrowsNoPagination();
        address[] memory tempUsers = new address[](escrows.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < escrows.length; i++) {
            // Call owner() without casting to specific contract type
            (bool success, bytes memory data) = escrows[i].staticcall(abi.encodeWithSignature("owner()"));
            require(success && data.length > 0, "TVLAggregator: failed to get owner");
            address owner = abi.decode(data, (address));

            bool exists = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempUsers[j] == owner) {
                    exists = true;
                    break;
                }
            }

            if (!exists) {
                tempUsers[uniqueCount] = owner;
                uniqueCount++;
            }
        }

        return uniqueCount;
    }

    /**
     * @notice Get protocol metadata for indexers
     */
    function getProtocolMetadata() external view returns (
        string memory name,
        string memory category,
        uint256 totalEscrows,
        uint256 totalUsers
    ) {
        return (
            "SolHedge",
            "Derivatives", // DeFiLlama category
            registry.getTotalEscrowCount(),
            this.getTotalUsers()
        );
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Add a token to track
     * @param token Token address
     */
    function addTrackedToken(address token) external {
        require(token != address(0), "TVLAggregator: zero token");
        require(!isTrackedToken[token], "TVLAggregator: already tracked");

        trackedTokens.push(token);
        isTrackedToken[token] = true;

        emit TokenAdded(token);
    }

    /**
     * @notice Get all tracked tokens
     */
    function getTrackedTokens() external view returns (address[] memory) {
        return trackedTokens;
    }
}
