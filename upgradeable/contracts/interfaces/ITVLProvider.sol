// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ITVLProvider
 * @notice Standard interface for DeFiLlama and other analytics tools
 * @dev Implements common TVL query patterns used by analytics platforms
 */
interface ITVLProvider {
    /**
     * @notice Get total value locked in USD (if oracle available) or native tokens
     * @return Total TVL across all escrows
     */
    function getTotalValueLocked() external view returns (uint256);

    /**
     * @notice Get TVL breakdown by token
     * @return tokens Array of token addresses
     * @return amounts Array of token amounts
     */
    function getTVLByToken() external view returns (
        address[] memory tokens,
        uint256[] memory amounts
    );

    /**
     * @notice Get all unique depositors/users
     * @return Array of user addresses
     */
    function getAllUsers() external view returns (address[] memory);

    /**
     * @notice Get TVL for a specific user
     * @param user User address
     * @return Total TVL for the user
     */
    function getUserTVL(address user) external view returns (uint256);
}
