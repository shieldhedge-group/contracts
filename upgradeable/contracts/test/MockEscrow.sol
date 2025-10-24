// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockEscrow
 * @notice Simple escrow contract for testing analytics
 * @dev Does not use upgradeable pattern - just for testing
 */
contract MockEscrow {
    address private _owner;
    address public poolAddress;

    event DepositedETH(address indexed from, uint256 amount);
    event DepositedToken(address indexed token, address indexed from, uint256 amount);

    constructor(address owner_, address _poolAddress) {
        _owner = owner_;
        poolAddress = _poolAddress;
    }

    receive() external payable {
        emit DepositedETH(msg.sender, msg.value);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function depositETH() external payable {
        emit DepositedETH(msg.sender, msg.value);
    }

    function depositToken(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit DepositedToken(token, msg.sender, amount);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
