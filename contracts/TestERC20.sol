// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    uint8 private _decimals = 18;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}