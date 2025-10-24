// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./UserEscrowUpgradeable.sol";
import "./interfaces/IEscrowRegistry.sol";
import "./interfaces/IWhitelistManager.sol";

/**
 * @title EscrowFactoryUpgradeable
 * @notice Factory for creating upgradeable UserEscrow instances via proxies
 * @dev Uses TransparentUpgradeableProxy pattern for all new escrows
 *
 * KEY FEATURES:
 * - Creates escrows as TransparentUpgradeableProxy
 * - Centralized implementation management
 * - Upgradeable escrow logic without user migration
 * - Governance-controlled upgrades via ProxyAdmin
 */
contract EscrowFactoryUpgradeable is Ownable, Pausable {

    /* ========== STATE VARIABLES ========== */

    IEscrowRegistry public escrowRegistry;
    IWhitelistManager public whitelistManager;
    uint256 public immutable ownershipDelay;

    /// @notice Current implementation contract for escrows
    address public escrowImplementation;

    /// @notice ProxyAdmin that controls all proxy upgrades
    ProxyAdmin public proxyAdmin;

    /// @notice Default bot address assigned to all newly created escrows
    address public botAddress;

    /// @notice Emergency admin for circuit breaker
    address public emergencyAdmin;

    /// @notice Live mode flag
    bool public isHasLive = false;

    /// @notice Base network USDC address
    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /* ========== EVENTS ========== */

    event EscrowCreated(address indexed user, address indexed escrow, address indexed proxy);
    event EscrowCreatedForPool(address indexed user, address indexed pool, address indexed proxy);
    event ImplementationUpgraded(address indexed oldImplementation, address indexed newImplementation);
    event ProxyAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event EscrowRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event BotAddressUpdated(address indexed oldBot, address indexed newBot);
    event LiveModeUpdated(bool indexed isLive, address indexed updatedBy);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initialize the factory
     * @param _ownershipDelay Delay for ownership transfers
     * @param _escrowRegistry Registry contract
     * @param _whitelistManager Whitelist manager contract
     * @param _botAddress Default bot address
     * @param _escrowImplementation Initial implementation
     */
    constructor(
        uint256 _ownershipDelay,
        address _escrowRegistry,
        address _whitelistManager,
        address _botAddress,
        address _escrowImplementation
    ) {
        require(_escrowRegistry != address(0), "zero registry");
        require(_whitelistManager != address(0), "zero whitelist");
        require(_botAddress != address(0), "zero bot");
        require(_escrowImplementation != address(0), "zero implementation");

        ownershipDelay = _ownershipDelay;
        escrowRegistry = IEscrowRegistry(_escrowRegistry);
        whitelistManager = IWhitelistManager(_whitelistManager);
        botAddress = _botAddress;
        escrowImplementation = _escrowImplementation;
        emergencyAdmin = _botAddress;

        // Deploy ProxyAdmin for managing all proxies
        proxyAdmin = new ProxyAdmin();
    }

    /* ========== FACTORY FUNCTIONS ========== */

    /**
     * @notice Create a new upgradeable escrow via proxy
     * @param poolAddress Pool address for this escrow
     * @param approvers Initial approvers
     * @param threshold Signature threshold
     * @param maxCalls Max multicall operations
     * @return Proxy address (user's escrow)
     */
    function createEscrow(
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls
    ) external whenNotPaused returns (address) {
        return _createEscrow(poolAddress, approvers, threshold, maxCalls, true);
    }

    /**
     * @notice Create escrow without auto-adding bot
     * @param poolAddress Pool address
     * @param approvers Initial approvers
     * @param threshold Signature threshold
     * @param maxCalls Max multicall operations
     * @return Proxy address
     */
    function createEscrowWithoutBot(
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls
    ) external whenNotPaused returns (address) {
        return _createEscrow(poolAddress, approvers, threshold, maxCalls, false);
    }

    /**
     * @notice Internal escrow creation with proxy deployment
     * @dev Creates TransparentUpgradeableProxy pointing to implementation
     */
    function _createEscrow(
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls,
        bool addBot
    ) internal returns (address) {
        require(poolAddress != address(0), "zero pool");
        require(!escrowRegistry.hasEscrowForPool(msg.sender, poolAddress), "pool escrow exists");
        require(approvers.length >= threshold && threshold > 0, "invalid threshold");

        // Add bot if requested
        address[] memory finalApprovers = approvers;
        bool botIncluded = false;

        for (uint256 i = 0; i < approvers.length; i++) {
            if (approvers[i] == botAddress) {
                botIncluded = true;
                break;
            }
        }

        if (!botIncluded && botAddress != address(0) && addBot) {
            finalApprovers = new address[](approvers.length + 1);
            for (uint256 i = 0; i < approvers.length; i++) {
                finalApprovers[i] = approvers[i];
            }
            finalApprovers[approvers.length] = botAddress;
        }

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            UserEscrowUpgradeable.initialize.selector,
            msg.sender,              // owner
            poolAddress,             // poolAddress
            finalApprovers,          // approvers
            threshold,               // threshold
            maxCalls,                // maxCalls
            ownershipDelay,          // ownershipDelay
            address(this),           // factory
            address(whitelistManager), // whitelist
            getNetworkUSDC()         // usdc
        );

        // Deploy TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            escrowImplementation,  // logic contract
            address(proxyAdmin),   // admin
            initData               // initialization call
        );

        address proxyAddress = address(proxy);

        // Register in registry
        escrowRegistry.registerEscrow(proxyAddress, msg.sender, poolAddress);

        emit EscrowCreatedForPool(msg.sender, poolAddress, proxyAddress);
        return proxyAddress;
    }

    /* ========== UPGRADE MANAGEMENT ========== */

    /**
     * @notice Upgrade the implementation for ALL future escrows
     * @dev Existing escrows keep current implementation until individually upgraded
     * @param newImplementation Address of new UserEscrowUpgradeable
     */
    function upgradeImplementation(address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "zero implementation");
        require(newImplementation != escrowImplementation, "same implementation");

        address oldImplementation = escrowImplementation;
        escrowImplementation = newImplementation;

        emit ImplementationUpgraded(oldImplementation, newImplementation);
    }

    /**
     * @notice Upgrade a specific escrow proxy to new implementation
     * @dev Can only be called by ProxyAdmin owner (should be timelock)
     * @param proxyAddress Address of the escrow proxy to upgrade
     * @param newImplementation New implementation address
     */
    function upgradeEscrowProxy(address proxyAddress, address newImplementation) external onlyOwner {
        require(escrowRegistry.isRegisteredEscrow(proxyAddress), "not registered");
        require(newImplementation != address(0), "zero implementation");

        // ProxyAdmin.upgrade() will verify ownership
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(proxyAddress),
            newImplementation
        );
    }

    /**
     * @notice Batch upgrade multiple escrow proxies
     * @dev Useful for migrating all users to new version
     * @param proxies Array of proxy addresses
     * @param newImplementation New implementation for all
     */
    function batchUpgradeEscrows(
        address[] calldata proxies,
        address newImplementation
    ) external onlyOwner {
        require(newImplementation != address(0), "zero implementation");

        for (uint256 i = 0; i < proxies.length; i++) {
            if (escrowRegistry.isRegisteredEscrow(proxies[i])) {
                proxyAdmin.upgrade(
                    ITransparentUpgradeableProxy(proxies[i]),
                    newImplementation
                );
            }
        }
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /**
     * @notice Transfer ProxyAdmin ownership (CRITICAL!)
     * @dev Should transfer to TimelockController for governance
     * @param newAdmin Address of new ProxyAdmin owner
     */
    function transferProxyAdminOwnership(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "zero address");

        address oldAdmin = proxyAdmin.owner();
        proxyAdmin.transferOwnership(newAdmin);

        emit ProxyAdminUpdated(oldAdmin, newAdmin);
    }

    function setEscrowRegistry(address _escrowRegistry) external onlyOwner {
        require(_escrowRegistry != address(0), "zero registry");
        address oldRegistry = address(escrowRegistry);
        escrowRegistry = IEscrowRegistry(_escrowRegistry);
        emit EscrowRegistryUpdated(oldRegistry, _escrowRegistry);
    }

    function setBotAddress(address _botAddress) external onlyOwner {
        require(_botAddress != address(0), "zero bot");
        address oldBot = botAddress;
        botAddress = _botAddress;
        emit BotAddressUpdated(oldBot, _botAddress);
    }

    function setLiveMode(bool _isLive) external onlyOwner {
        isHasLive = _isLive;
        emit LiveModeUpdated(_isLive, msg.sender);
    }

    /**
     * @notice Authorize this factory in the registry
     * @dev Only callable by owner. Useful for post-deployment setup.
     */
    function authorizeFactoryInRegistry() external onlyOwner {
        IEscrowRegistry(escrowRegistry).setAuthorizedFactory(address(this), true);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getNetworkUSDC() public pure returns (address) {
        return USDC_BASE;
    }

    function getTotalEscrowCount() external view returns (uint256) {
        return escrowRegistry.getTotalEscrowCount();
    }

    function isRegisteredEscrow(address escrow) external view returns (bool) {
        return escrowRegistry.isRegisteredEscrow(escrow);
    }

    function getEscrowForPool(address user, address poolAddress) external view returns (address) {
        return escrowRegistry.getEscrowForPool(user, poolAddress);
    }

    function hasEscrowForPool(address user, address poolAddress) external view returns (bool) {
        return escrowRegistry.hasEscrowForPool(user, poolAddress);
    }

    function getLegacyEscrow(address user) external view returns (address) {
        return escrowRegistry.getLegacyEscrow(user);
    }

    /**
     * @notice Get implementation address for a specific proxy
     * @param proxy Proxy address
     * @return Implementation address
     */
    function getProxyImplementation(address proxy) external view returns (address) {
        return proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(proxy));
    }

    /**
     * @notice Get current ProxyAdmin address
     * @return ProxyAdmin address
     */
    function getProxyAdmin() external view returns (address) {
        return address(proxyAdmin);
    }

    /* ========== PAUSE/UNPAUSE ========== */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ========== EMERGENCY CONTROLS ========== */
    // Reuse same emergency controls from original factory

    bool public globalEmergencyPause;
    mapping(bytes4 => bool) public pausedFunctions;
    uint256 public globalEmergencyStartTime;
    uint256 public constant EMERGENCY_PAUSE_DURATION = 7 days;
    mapping(bytes4 => uint256) public functionPauseStartTime;

    event GlobalEmergencySet(bool indexed paused, address indexed admin);
    event FunctionPaused(bytes4 indexed selector, bool indexed paused, address indexed admin);
    event EmergencyAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event EmergencyPauseExpired(string pauseType);

    modifier onlyEmergencyControl() {
        require(
            msg.sender == owner() || msg.sender == emergencyAdmin,
            "not emergency control"
        );
        _;
    }

    function setGlobalEmergency(bool _paused) external onlyEmergencyControl {
        globalEmergencyPause = _paused;
        if (_paused) {
            globalEmergencyStartTime = block.timestamp;
        } else {
            globalEmergencyStartTime = 0;
        }
        emit GlobalEmergencySet(_paused, msg.sender);
    }

    function checkAndClearExpiredGlobalEmergency() external {
        require(globalEmergencyPause, "not in emergency");
        require(
            block.timestamp >= globalEmergencyStartTime + EMERGENCY_PAUSE_DURATION,
            "emergency not expired"
        );

        globalEmergencyPause = false;
        globalEmergencyStartTime = 0;
        emit EmergencyPauseExpired("global");
        emit GlobalEmergencySet(false, msg.sender);
    }

    function pauseFunction(bytes4 selector, bool _paused) external onlyEmergencyControl {
        pausedFunctions[selector] = _paused;
        if (_paused) {
            functionPauseStartTime[selector] = block.timestamp;
        } else {
            functionPauseStartTime[selector] = 0;
        }
        emit FunctionPaused(selector, _paused, msg.sender);
    }

    function setEmergencyAdmin(address _emergencyAdmin) external onlyOwner {
        address oldAdmin = emergencyAdmin;
        emergencyAdmin = _emergencyAdmin;
        emit EmergencyAdminUpdated(oldAdmin, _emergencyAdmin);
    }

    /// @notice Check and clear expired function pause
    /// @param selector Function selector to check
    function checkAndClearExpiredFunctionPause(bytes4 selector) external {
        require(pausedFunctions[selector], "EscrowFactory: function not paused");
        require(
            block.timestamp >= functionPauseStartTime[selector] + EMERGENCY_PAUSE_DURATION,
            "EscrowFactory: function pause not expired"
        );

        pausedFunctions[selector] = false;
        functionPauseStartTime[selector] = 0;
        emit EmergencyPauseExpired("function");
        emit FunctionPaused(selector, false, msg.sender);
    }

    /// @notice Batch pause multiple functions
    /// @param selectors Array of function selectors
    /// @param _paused Whether to pause the functions
    function pauseFunctions(bytes4[] calldata selectors, bool _paused) external onlyEmergencyControl {
        for (uint256 i = 0; i < selectors.length; i++) {
            pausedFunctions[selectors[i]] = _paused;
            if (_paused) {
                functionPauseStartTime[selectors[i]] = block.timestamp;
            } else {
                functionPauseStartTime[selectors[i]] = 0;
            }
            emit FunctionPaused(selectors[i], _paused, msg.sender);
        }
    }

    /// @notice Check if a specific function is paused
    /// @param selector Function selector to check
    /// @return bool True if function is paused
    function isFunctionPaused(bytes4 selector) external view returns (bool) {
        return pausedFunctions[selector];
    }

    /// @notice Get comprehensive emergency status
    /// @return globalPaused Global emergency state
    /// @return factoryPaused Factory creation pause state
    /// @return admin Current emergency admin
    function getEmergencyStatus() external view returns (
        bool globalPaused,
        bool factoryPaused,
        address admin
    ) {
        return (globalEmergencyPause, paused(), emergencyAdmin);
    }

    /// @notice Emergency function to pause critical operations
    /// @dev Pauses execute, multicall, and executeWithSignatures
    function emergencyPauseCriticalFunctions() external onlyEmergencyControl {
        bytes4[3] memory criticalSelectors = [
            bytes4(keccak256("execute(address,uint256,bytes)")),
            bytes4(keccak256("multicall(address[],uint256[],bytes[])")),
            bytes4(keccak256("executeWithSignatures(address,uint256,bytes,bytes[],uint256)"))
        ];

        for (uint256 i = 0; i < criticalSelectors.length; i++) {
            pausedFunctions[criticalSelectors[i]] = true;
            functionPauseStartTime[criticalSelectors[i]] = block.timestamp;
            emit FunctionPaused(criticalSelectors[i], true, msg.sender);
        }
    }

    /// @notice Emergency function to unpause critical operations
    function emergencyUnpauseCriticalFunctions() external onlyEmergencyControl {
        bytes4[3] memory criticalSelectors = [
            bytes4(keccak256("execute(address,uint256,bytes)")),
            bytes4(keccak256("multicall(address[],uint256[],bytes[])")),
            bytes4(keccak256("executeWithSignatures(address,uint256,bytes,bytes[],uint256)"))
        ];

        for (uint256 i = 0; i < criticalSelectors.length; i++) {
            pausedFunctions[criticalSelectors[i]] = false;
            functionPauseStartTime[criticalSelectors[i]] = 0;
            emit FunctionPaused(criticalSelectors[i], false, msg.sender);
        }
    }

    /**
     * @notice Update whitelist through WhitelistManager (factory owns it)
     * @param target Address to whitelist or remove from whitelist
     * @param whitelisted True to whitelist, false to remove
     */
    function updateWhitelist(address target, bool whitelisted) external onlyOwner {
        whitelistManager.setWhitelist(target, whitelisted);
    }

    /**
     * @notice Batch update whitelist
     * @param targets Array of addresses to update
     * @param whitelisted Array of whitelist statuses
     */
    function batchUpdateWhitelist(address[] calldata targets, bool[] calldata whitelisted) external onlyOwner {
        require(targets.length == whitelisted.length, "length mismatch");
        whitelistManager.batchSetWhitelist(targets, whitelisted);
    }
}
