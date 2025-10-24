// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEscrowFactory {
    function escrowExists(address) external view returns (bool);
    function isWhitelisted(address target) external view returns (bool);
    function isWhitelistedWithCaller(address target, address caller) external view returns (bool);
    function getEscrowForPool(address user, address poolAddress) external view returns (address);
    function hasEscrowForPool(address user, address poolAddress) external view returns (bool);

    // Circuit breaker functions
    function globalEmergencyPause() external view returns (bool);
    function pausedFunctions(bytes4 selector) external view returns (bool);
    function emergencyAdmin() external view returns (address);
    function getEmergencyStatus() external view returns (bool globalPaused, bool factoryPaused, address admin);
    function isFunctionPaused(bytes4 selector) external view returns (bool);

    // Live mode (false = dev mode, true = live mode)
    function isHasLive() external view returns (bool);
}