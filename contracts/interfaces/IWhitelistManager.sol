// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IWhitelistManager {
    function isWhitelistedWithCaller(address target, address caller) external view returns (bool);
    function isWhitelisted(address target) external view returns (bool);
    function isExplicitlyWhitelisted(address target) external view returns (bool);

    event TargetWhitelisted(address indexed target, bool whitelisted);
}