// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

contract EscrowRegistry is Ownable {
    mapping(address => mapping(address => address)) public userPoolEscrows;
    mapping(address => address) public userEscrows;
    uint256 public totalEscrows;
    mapping(address => bool) public escrowExists;

    mapping(address => bool) public authorizedFactories;

    event EscrowRegistered(address indexed escrow, address indexed user, address indexed poolAddress);
    event FactoryAuthorized(address indexed factory, bool authorized);

    modifier onlyAuthorizedFactory() {
        require(authorizedFactories[msg.sender], "EscrowRegistry: unauthorized factory");
        _;
    }

    constructor() {}

    function setAuthorizedFactory(address factory, bool authorized) external onlyOwner {
        require(factory != address(0), "EscrowRegistry: zero factory");
        authorizedFactories[factory] = authorized;
        emit FactoryAuthorized(factory, authorized);
    }

    function registerEscrow(address escrow, address user, address poolAddress) external onlyAuthorizedFactory {
        require(escrow != address(0), "EscrowRegistry: zero escrow");
        require(user != address(0), "EscrowRegistry: zero user");
        require(!escrowExists[escrow], "EscrowRegistry: escrow already exists");

        escrowExists[escrow] = true;
        totalEscrows++;

        if (poolAddress == address(0)) {
            require(userEscrows[user] == address(0), "EscrowRegistry: legacy escrow exists");
            userEscrows[user] = escrow;
        } else {
            require(userPoolEscrows[user][poolAddress] == address(0), "EscrowRegistry: pool escrow exists");
            userPoolEscrows[user][poolAddress] = escrow;
        }

        emit EscrowRegistered(escrow, user, poolAddress);
    }

    function isRegisteredEscrow(address escrow) external view returns (bool) {
        return escrowExists[escrow];
    }

    function getTotalEscrowCount() external view returns (uint256) {
        return totalEscrows;
    }

    function getEscrowForPool(address user, address poolAddress) external view returns (address) {
        return userPoolEscrows[user][poolAddress];
    }

    function hasEscrowForPool(address user, address poolAddress) external view returns (bool) {
        return userPoolEscrows[user][poolAddress] != address(0);
    }

    function getLegacyEscrow(address user) external view returns (address) {
        return userEscrows[user];
    }
}