// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockAerodromeRouter
 * @notice Mock DEX router for testing DeFi operations
 * @dev Simulates Aerodrome router functionality for integration tests
 */
contract MockAerodromeRouter {
    using SafeERC20 for IERC20;

    // Simulated slippage (in basis points, 100 = 1%)
    uint256 public slippagePercent = 50; // 0.5% default

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed to
    );

    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        address indexed to
    );

    event LiquidityRemoved(
        address indexed tokenA,
        address indexed tokenB,
        uint256 liquidity,
        address indexed to
    );

    /**
     * @notice Set slippage for testing
     */
    function setSlippage(uint256 _slippagePercent) external {
        require(_slippagePercent <= 1000, "Slippage too high");
        slippagePercent = _slippagePercent;
    }

    /**
     * @notice Swap exact tokens for tokens
     * @dev Simulates swap with slippage
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Transaction expired");
        require(path.length >= 2, "Invalid path");

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        // Transfer tokens from sender
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate output with simulated slippage
        uint256 amountOut = (amountIn * (10000 - slippagePercent)) / 10000;
        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Transfer tokens to recipient
        IERC20(tokenOut).safeTransfer(to, amountOut);

        // Return amounts array
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, to);
    }

    /**
     * @notice Add liquidity
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(block.timestamp <= deadline, "Transaction expired");

        // Use desired amounts (simplified for testing)
        amountA = amountADesired;
        amountB = amountBDesired;

        require(amountA >= amountAMin, "Insufficient A amount");
        require(amountB >= amountBMin, "Insufficient B amount");

        // Transfer tokens from sender
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        // Calculate liquidity (simplified: geometric mean)
        liquidity = sqrt(amountA * amountB);

        emit LiquidityAdded(tokenA, tokenB, amountA, amountB, to);

        return (amountA, amountB, liquidity);
    }

    /**
     * @notice Remove liquidity
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "Transaction expired");

        // Simplified calculation
        amountA = liquidity / 2;
        amountB = liquidity / 2;

        require(amountA >= amountAMin, "Insufficient A amount");
        require(amountB >= amountBMin, "Insufficient B amount");

        // Transfer tokens to recipient
        IERC20(tokenA).safeTransfer(to, amountA);
        IERC20(tokenB).safeTransfer(to, amountB);

        emit LiquidityRemoved(tokenA, tokenB, liquidity, to);

        return (amountA, amountB);
    }

    /**
     * @notice Get amounts out for a swap
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // Apply slippage to final amount
        amounts[path.length - 1] = (amountIn * (10000 - slippagePercent)) / 10000;

        return amounts;
    }

    /**
     * @notice Fund router with tokens for testing
     */
    function fundRouter(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Square root helper function
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}