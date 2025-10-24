// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IEscrowRegistry {
    function registerEscrow(address escrow, address user, address poolAddress) external;
    function isRegisteredEscrow(address escrow) external view returns (bool);
    function getTotalEscrowCount() external view returns (uint256);
    function getEscrowForPool(address user, address poolAddress) external view returns (address);
    function hasEscrowForPool(address user, address poolAddress) external view returns (bool);
    function getLegacyEscrow(address user) external view returns (address);

    event EscrowRegistered(address indexed escrow, address indexed user, address indexed poolAddress);
}