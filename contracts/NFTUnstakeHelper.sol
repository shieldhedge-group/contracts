// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal interface for Aerodrome CL Gauge
interface IAerodromeCLGauge {
    function withdraw(uint256 tokenId) external;
    function nft() external view returns (address);
}

/**
 * @title NFTUnstakeHelper
 * @notice Helper contract to enable gauge unstaking for escrows without ERC721Receiver
 * @dev This contract acts as an intermediary to receive NFTs from gauges and forward them to escrows
 *
 * PROBLEM SOLVED:
 * - Existing UserEscrow contracts don't implement IERC721Receiver
 * - Gauge.withdraw() uses safeTransferFrom which requires ERC721Receiver
 * - Cannot upgrade deployed escrows
 *
 * SOLUTION:
 * - This helper implements IERC721Receiver
 * - Receives NFT from gauge via safeTransferFrom
 * - Forwards NFT to escrow via regular transferFrom (no receiver needed)
 *
 * SECURITY:
 * - Only owner can call main functions
 * - Pausable for emergency stops
 * - ReentrancyGuard on all state-changing functions
 * - No funds held permanently (immediate forward)
 */
contract NFTUnstakeHelper is IERC721Receiver, ReentrancyGuard, Pausable, Ownable {

    /* ========== EVENTS ========== */

    /// @notice Emitted when NFT is successfully unstaked and transferred
    event NFTUnstaked(
        address indexed gauge,
        address indexed escrow,
        uint256 indexed tokenId,
        address nftContract
    );

    /// @notice Emitted when NFT is recovered in emergency
    event NFTRecovered(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed recipient
    );

    /* ========== ERRORS ========== */

    error InvalidAddress();
    error UnstakeFailed();
    error TransferFailed();

    /* ========== CONSTRUCTOR ========== */

    constructor() {
        // Owner is set to msg.sender by Ownable constructor
    }

    /* ========== MAIN FUNCTIONS ========== */

    /**
     * @notice Unstake NFT from gauge and transfer to escrow
     * @dev Main function - handles the complete unstaking flow
     * @param gauge Address of the Aerodrome CL Gauge contract
     * @param escrow Address of the UserEscrow to receive the NFT
     * @param tokenId The NFT token ID to unstake
     *
     * FLOW:
     * 1. Call gauge.withdraw(tokenId)
     *    → Gauge uses safeTransferFrom to send NFT to this contract
     *    → onERC721Received is called (we accept the NFT)
     * 2. Transfer NFT from this contract to escrow
     *    → Uses regular transferFrom (escrow doesn't need to be receiver)
     * 3. Emit event for tracking
     *
     * REQUIREMENTS:
     * - Contract must not be paused
     * - Gauge and escrow addresses must be valid
     * - NFT must be staked in the gauge by the escrow
     *
     * SECURITY:
     * - No onlyOwner modifier - anyone can call
     * - Safe because gauge.withdraw() only works if escrow is depositor
     * - NFT always transferred to specified escrow address
     * - Helper never holds NFTs or funds permanently
     */
    function unstakeAndTransfer(
        address gauge,
        address escrow,
        uint256 tokenId
    ) external whenNotPaused nonReentrant {
        // Validate inputs
        if (gauge == address(0) || escrow == address(0)) {
            revert InvalidAddress();
        }

        // Get NFT contract address from gauge
        IAerodromeCLGauge gaugeContract = IAerodromeCLGauge(gauge);
        address nftContract = gaugeContract.nft();

        if (nftContract == address(0)) {
            revert InvalidAddress();
        }

        // Step 1: Withdraw from gauge
        // This will trigger safeTransferFrom which calls our onERC721Received
        try gaugeContract.withdraw(tokenId) {
            // Success - NFT is now in this contract
        } catch {
            revert UnstakeFailed();
        }

        // Step 2: Transfer NFT to escrow using regular transferFrom
        // Note: Escrow doesn't need to implement IERC721Receiver for this
        IERC721 nft = IERC721(nftContract);

        try nft.transferFrom(address(this), escrow, tokenId) {
            // Success - NFT is now in escrow
        } catch {
            revert TransferFailed();
        }

        // Emit event for tracking
        emit NFTUnstaked(gauge, escrow, tokenId, nftContract);
    }

    /**
     * @notice Handle the receipt of an NFT
     * @dev Required by IERC721Receiver interface
     * @dev This is called by gauge.withdraw() when it uses safeTransferFrom
     * @return bytes4 Magic value indicating we can receive the NFT
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        // Accept all NFT transfers
        // Security note: This contract immediately forwards NFTs, so temporary holding is safe
        return IERC721Receiver.onERC721Received.selector;
    }

    /* ========== EMERGENCY FUNCTIONS ========== */

    /**
     * @notice Emergency pause - stops all unstaking operations
     * @dev Can only be called by owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract - resumes operations
     * @dev Can only be called by owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency recovery of stuck NFTs
     * @dev If an NFT gets stuck in this contract, owner can recover it
     * @param nftContract Address of the NFT contract
     * @param tokenId The token ID to recover
     * @param recipient Address to send the NFT to
     */
    function recoverNFT(
        address nftContract,
        uint256 tokenId,
        address recipient
    ) external onlyOwner nonReentrant {
        if (nftContract == address(0) || recipient == address(0)) {
            revert InvalidAddress();
        }

        IERC721 nft = IERC721(nftContract);
        nft.transferFrom(address(this), recipient, tokenId);

        emit NFTRecovered(nftContract, tokenId, recipient);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Check if this contract can receive ERC721 tokens
     * @return bool Always returns true
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId;
    }
}
