// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MockERC721
 * @dev Simple ERC721 token for testing NFT functionality
 */
contract MockERC721 is ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    /**
     * @dev Mint a new NFT to the specified address
     * @param to Address to mint to
     * @param tokenId Token ID to mint
     */
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    /**
     * @dev Burn an NFT
     * @param tokenId Token ID to burn
     */
    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }
}
