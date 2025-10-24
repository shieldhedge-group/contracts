// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing on Sepolia
 */
contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to any address (for testing)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Mint tokens to caller (for easy testing)
     */
    function faucet(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    /**
     * @notice Burn tokens
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}