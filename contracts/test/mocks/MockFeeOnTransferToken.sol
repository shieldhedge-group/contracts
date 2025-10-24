// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockFeeOnTransferToken
 * @notice Mock ERC20 token that charges a fee on transfers
 * @dev Used for testing edge cases with fee-on-transfer tokens like PAXG
 */
contract MockFeeOnTransferToken is ERC20, Ownable {
    uint256 public transferFeePercent; // Fee in basis points (100 = 1%)
    address public feeCollector;

    event FeeCollected(address indexed from, address indexed to, uint256 amount);
    event FeePercentUpdated(uint256 oldFee, uint256 newFee);

    constructor(
        string memory name,
        string memory symbol,
        uint256 _transferFeePercent
    ) ERC20(name, symbol) {
        require(_transferFeePercent <= 1000, "Fee too high"); // Max 10%
        transferFeePercent = _transferFeePercent;
        feeCollector = msg.sender;
    }

    /**
     * @notice Set transfer fee percentage
     * @param _feePercent Fee in basis points (100 = 1%)
     */
    function setTransferFee(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 1000, "Fee too high"); // Max 10%
        uint256 oldFee = transferFeePercent;
        transferFeePercent = _feePercent;
        emit FeePercentUpdated(oldFee, _feePercent);
    }

    /**
     * @notice Set fee collector address
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Invalid collector");
        feeCollector = _feeCollector;
    }

    /**
     * @notice Mint tokens for testing
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Override transfer to apply fee
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (transferFeePercent > 0 && from != address(0) && to != address(0)) {
            // Calculate fee
            uint256 fee = (amount * transferFeePercent) / 10000;
            uint256 amountAfterFee = amount - fee;

            // Transfer to recipient (after fee)
            super._transfer(from, to, amountAfterFee);

            // Transfer fee to collector
            if (fee > 0) {
                super._transfer(from, feeCollector, fee);
                emit FeeCollected(from, to, fee);
            }
        } else {
            super._transfer(from, to, amount);
        }
    }
}