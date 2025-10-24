// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./EscrowRegistry.sol";
import "./WhitelistManager.sol";
import "./EscrowFactory.sol";
import "./EscrowManager.sol";

/**
 * @title BatchDeployer
 * @notice Deploys all SolHedge escrow system contracts in a single transaction
 * @dev This contract deploys EscrowRegistry, WhitelistManager, EscrowFactory, and EscrowManager
 *      All contracts are deployed with proper dependencies and ownership is transferred to the deployer
 */
contract BatchDeployer {

    struct DeploymentResult {
        address registry;
        address whitelist;
        address factory;
        address manager;
    }

    event ContractsDeployed(
        address indexed deployer,
        address registry,
        address whitelist,
        address factory,
        address manager,
        uint256 ownershipDelay,
        address botAddress
    );

    /**
     * @notice Deploy all escrow system contracts in one transaction
     * @param ownershipDelay Delay for ownership transfer in UserEscrow contracts
     * @param botAddress Bot address for automation system
     * @return result Struct containing all deployed contract addresses
     */
    function deployAll(
        uint256 ownershipDelay,
        address botAddress
    ) external returns (DeploymentResult memory result) {
        require(botAddress != address(0), "BatchDeployer: zero bot address");
        require(ownershipDelay > 0, "BatchDeployer: invalid ownership delay");

        // Step 1: Deploy EscrowRegistry
        EscrowRegistry registry = new EscrowRegistry();
        result.registry = address(registry);

        // Step 2: Deploy WhitelistManager with registry address
        WhitelistManager whitelist = new WhitelistManager(result.registry);
        result.whitelist = address(whitelist);

        // Step 3: Deploy EscrowFactory with all dependencies
        EscrowFactory factory = new EscrowFactory(
            ownershipDelay,
            result.registry,
            result.whitelist,
            botAddress
        );
        result.factory = address(factory);

        // Step 4: Deploy EscrowManager with factory and registry
        EscrowManager manager = new EscrowManager(
            result.factory,
            result.registry,
            botAddress
        );
        result.manager = address(manager);

        // Step 5: Authorize factory in registry (critical for escrow creation)
        registry.setAuthorizedFactory(result.factory, true);

        // Step 6: Transfer ownership of all contracts to deployer
        registry.transferOwnership(msg.sender);
        whitelist.transferOwnership(msg.sender);
        factory.transferOwnership(msg.sender);
        // Note: EscrowManager doesn't inherit Ownable, it has its own owner

        // Emit deployment event for tracking
        emit ContractsDeployed(
            msg.sender,
            result.registry,
            result.whitelist,
            result.factory,
            result.manager,
            ownershipDelay,
            botAddress
        );

        return result;
    }

    /**
     * @notice Get version of BatchDeployer
     * @return version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}