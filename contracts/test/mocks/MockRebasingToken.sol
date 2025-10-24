// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockRebasingToken
 * @notice Mock ERC20 token that rebases (changes balance without transfers)
 * @dev Used for testing edge cases with rebasing tokens like AMPL, stETH
 */
contract MockRebasingToken is ERC20, Ownable {
    // Multiplier for rebase calculation (scaled by 1e18)
    uint256 public rebaseMultiplier = 1e18;

    // Mapping to track base balances (before rebase)
    mapping(address => uint256) private _baseBalances;
    uint256 private _baseTotalSupply;

    event Rebased(uint256 oldMultiplier, uint256 newMultiplier, int256 supplyDelta);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /**
     * @notice Mint tokens (base amount)
     */
    function mint(address to, uint256 amount) external {
        _baseBalances[to] += amount;
        _baseTotalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Perform a positive rebase (increase balances)
     * @param percent Percentage increase (100 = 1%)
     */
    function rebaseUp(uint256 percent) external onlyOwner {
        require(percent > 0 && percent <= 10000, "Invalid percent");
        uint256 oldMultiplier = rebaseMultiplier;
        rebaseMultiplier = (rebaseMultiplier * (10000 + percent)) / 10000;

        int256 supplyDelta = int256(totalSupply()) - int256((_baseTotalSupply * oldMultiplier) / 1e18);
        emit Rebased(oldMultiplier, rebaseMultiplier, supplyDelta);
    }

    /**
     * @notice Perform a negative rebase (decrease balances)
     * @param percent Percentage decrease (100 = 1%)
     */
    function rebaseDown(uint256 percent) external onlyOwner {
        require(percent > 0 && percent < 10000, "Invalid percent");
        uint256 oldMultiplier = rebaseMultiplier;
        rebaseMultiplier = (rebaseMultiplier * (10000 - percent)) / 10000;

        int256 supplyDelta = int256(totalSupply()) - int256((_baseTotalSupply * oldMultiplier) / 1e18);
        emit Rebased(oldMultiplier, rebaseMultiplier, supplyDelta);
    }

    /**
     * @notice Get balance (applies rebase multiplier)
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return (_baseBalances[account] * rebaseMultiplier) / 1e18;
    }

    /**
     * @notice Get total supply (applies rebase multiplier)
     */
    function totalSupply() public view virtual override returns (uint256) {
        return (_baseTotalSupply * rebaseMultiplier) / 1e18;
    }

    /**
     * @notice Transfer (converts to base amounts)
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");

        // Convert amount to base units
        uint256 baseAmount = (amount * 1e18) / rebaseMultiplier;

        uint256 fromBalance = _baseBalances[from];
        require(fromBalance >= baseAmount, "ERC20: transfer amount exceeds balance");

        unchecked {
            _baseBalances[from] = fromBalance - baseAmount;
            _baseBalances[to] += baseAmount;
        }

        emit Transfer(from, to, amount);
    }

    /**
     * @notice Get base balance (before rebase multiplier)
     */
    function baseBalanceOf(address account) external view returns (uint256) {
        return _baseBalances[account];
    }

    /**
     * @notice Get base total supply
     */
    function baseTotalSupply() external view returns (uint256) {
        return _baseTotalSupply;
    }
}