// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockAerodromePool
 * @notice Simplified mock LP token for testing
 * @dev For real tests, use Anvil Base fork with actual Aerodrome contracts
 */
contract MockAerodromePool is ERC20 {
    address public token0;
    address public token1;

    constructor(
        string memory name,
        string memory symbol,
        address _token0,
        address _token1
    ) ERC20(name, symbol) {
        token0 = _token0;
        token1 = _token1;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}