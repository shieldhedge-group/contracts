// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./UserEscrow.sol";
import "./interfaces/IEscrowRegistry.sol";
import "./interfaces/IWhitelistManager.sol";

/**
 * @title EscrowFactory
 * @notice Factory contract for creating and managing UserEscrow instances
 *
 * @dev Bot Terminology Guide:
 * - `botAddress` (Factory Bot): Default bot address assigned to all new escrows
 *   Used for emergency pause/unpause on individual escrows
 * - See EscrowManager.sol for authorized bots that can execute batch operations
 * - See UserEscrow.sol for per-escrow bot that has emergency pause powers
 */
contract EscrowFactory is Ownable, Pausable {

    IEscrowRegistry public escrowRegistry;
    IWhitelistManager public whitelistManager;
    uint256 public immutable ownershipDelay;

    /// @notice Default bot address assigned to all newly created escrows
    /// @dev This bot has emergency pause/unpause powers on individual escrows
    address public botAddress;

    // Emergency admin for circuit breaker
    address public emergencyAdmin;

    // Live mode - when false, only whitelisted addresses can deposit (dev mode)
    // when true, all addresses can deposit (production mode)
    bool public isHasLive = false;

    // Base network USDC address
    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    event EscrowCreated(address indexed user, address indexed escrow);
    event EscrowCreatedForPool(address indexed user, address indexed pool, address indexed escrow);
    event EscrowRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event BotAddressUpdated(address indexed oldBot, address indexed newBot);
    event LiveModeUpdated(bool indexed isLive, address indexed updatedBy);

    constructor(uint256 _ownershipDelay, address _escrowRegistry, address _whitelistManager, address _botAddress) {
        require(_escrowRegistry != address(0), "EscrowFactory: zero registry");
        require(_whitelistManager != address(0), "EscrowFactory: zero whitelist manager");
        require(_botAddress != address(0), "EscrowFactory: zero bot address");
        ownershipDelay = _ownershipDelay;
        escrowRegistry = IEscrowRegistry(_escrowRegistry);
        whitelistManager = IWhitelistManager(_whitelistManager);
        botAddress = _botAddress;
        emergencyAdmin = _botAddress; // Set bot as initial emergency admin
    }

    function setEscrowRegistry(address _escrowRegistry) external onlyOwner {
        require(_escrowRegistry != address(0), "EscrowFactory: zero registry");
        address oldRegistry = address(escrowRegistry);
        escrowRegistry = IEscrowRegistry(_escrowRegistry);
        emit EscrowRegistryUpdated(oldRegistry, _escrowRegistry);
    }

    function setBotAddress(address _botAddress) external onlyOwner {
        require(_botAddress != address(0), "EscrowFactory: zero bot address");
        address oldBot = botAddress;
        botAddress = _botAddress;
        emit BotAddressUpdated(oldBot, _botAddress);
    }

    /// @notice Toggle live mode (only owner)
    /// @dev When isHasLive is false (dev mode), only whitelisted addresses can deposit
    /// @dev When isHasLive is true (live mode), all addresses can deposit
    /// @param _isLive New live mode state
    function setLiveMode(bool _isLive) external onlyOwner {
        isHasLive = _isLive;
        emit LiveModeUpdated(_isLive, msg.sender);
    }

    function createEscrow(
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls
    ) external whenNotPaused returns (address) {
        return _createEscrow(poolAddress, approvers, threshold, maxCalls, true);
    }

    /// @notice Create escrow with option to exclude bot from approvers
    /// @param poolAddress Pool address for this escrow
    /// @param approvers Initial approver addresses
    /// @param threshold Signature threshold required
    /// @param maxCalls Maximum calls per multicall
    function createEscrowWithoutBot(
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls
    ) external whenNotPaused returns (address) {
        return _createEscrow(poolAddress, approvers, threshold, maxCalls, false);
    }

    function _createEscrow(
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls,
        bool addBot
    ) internal returns (address) {
        require(poolAddress != address(0), "EscrowFactory: zero pool address");
        require(!escrowRegistry.hasEscrowForPool(msg.sender, poolAddress), "EscrowFactory: pool escrow exists");

        // SECURITY FIX: Validate threshold BEFORE auto-adding bot
        require(approvers.length >= threshold && threshold > 0, "invalid threshold");

        // Automatically add bot address to approvers if requested and not already included
        address[] memory finalApprovers = approvers;
        bool botIncluded = false;

        // Check if bot is already in the approvers list
        for (uint256 i = 0; i < approvers.length; i++) {
            if (approvers[i] == botAddress) {
                botIncluded = true;
                break;
            }
        }

        // If bot not included and addBot requested, create new array with bot added
        if (!botIncluded && botAddress != address(0) && addBot) {
            finalApprovers = new address[](approvers.length + 1);
            for (uint256 i = 0; i < approvers.length; i++) {
                finalApprovers[i] = approvers[i];
            }
            finalApprovers[approvers.length] = botAddress;
        }

        UserEscrow escrow = new UserEscrow(
            msg.sender,         // _owner
            poolAddress,        // _poolAddress
            finalApprovers,     // _approvers
            threshold,          // _threshold
            maxCalls,           // _maxCalls
            ownershipDelay,     // _ownershipDelay
            address(this),      // _factory
            address(whitelistManager), // _whitelist
            getNetworkUSDC()    // _usdc
        );

        address escrowAddr = address(escrow);
        escrowRegistry.registerEscrow(escrowAddr, msg.sender, poolAddress);

        emit EscrowCreatedForPool(msg.sender, poolAddress, escrowAddr);
        return escrowAddr;
    }


    /// @notice Get the appropriate USDC address for current network
    function getNetworkUSDC() public pure returns (address) {
        // For now, always return Base USDC since we're Base-focused
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

    /* ========== PAUSE/UNPAUSE ========== */

    /// @notice Pause escrow creation
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause escrow creation
    function unpause() external onlyOwner {
        _unpause();
    }

    /* ========== CIRCUIT BREAKER EMERGENCY CONTROLS ========== */

    // Global emergency pause state
    bool public globalEmergencyPause;

    // Function-specific pause control (function selector => paused)
    mapping(bytes4 => bool) public pausedFunctions;

    // SECURITY FIX: Emergency pause time limits
    uint256 public globalEmergencyStartTime;
    uint256 public constant EMERGENCY_PAUSE_DURATION = 7 days; // Maximum emergency pause duration
    mapping(bytes4 => uint256) public functionPauseStartTime;

    // Emergency admin with limited emergency powers (declared above)

    // Events for transparency
    event GlobalEmergencySet(bool indexed paused, address indexed admin);
    event FunctionPaused(bytes4 indexed selector, bool indexed paused, address indexed admin);
    event EmergencyAdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event EmergencyPauseExpired(string pauseType);

    // Emergency response modifiers
    modifier onlyEmergencyControl() {
        require(
            msg.sender == owner() || msg.sender == emergencyAdmin,
            "EscrowFactory: not emergency control"
        );
        _;
    }

    /// @notice Set global emergency pause state
    /// @dev Can be called by owner or emergency admin for rapid response
    /// @dev SECURITY FIX: Emergency pause auto-expires after EMERGENCY_PAUSE_DURATION
    function setGlobalEmergency(bool _paused) external onlyEmergencyControl {
        globalEmergencyPause = _paused;
        if (_paused) {
            globalEmergencyStartTime = block.timestamp;
        } else {
            globalEmergencyStartTime = 0;
        }
        emit GlobalEmergencySet(_paused, msg.sender);
    }

    /// @notice Check if global emergency pause has expired and auto-unpause
    /// @dev Anyone can call this to unpause after expiry - safety mechanism
    function checkAndClearExpiredGlobalEmergency() external {
        require(globalEmergencyPause, "EscrowFactory: not in emergency");
        require(
            block.timestamp >= globalEmergencyStartTime + EMERGENCY_PAUSE_DURATION,
            "EscrowFactory: emergency not expired"
        );

        globalEmergencyPause = false;
        globalEmergencyStartTime = 0;
        emit EmergencyPauseExpired("global");
        emit GlobalEmergencySet(false, msg.sender);
    }

    /// @notice Pause/unpause specific functions by selector
    /// @param selector Function selector to control
    /// @param _paused Whether to pause the function
    /// @dev SECURITY FIX: Function pause auto-expires after EMERGENCY_PAUSE_DURATION
    function pauseFunction(bytes4 selector, bool _paused) external onlyEmergencyControl {
        pausedFunctions[selector] = _paused;
        if (_paused) {
            functionPauseStartTime[selector] = block.timestamp;
        } else {
            functionPauseStartTime[selector] = 0;
        }
        emit FunctionPaused(selector, _paused, msg.sender);
    }

    /// @notice Check if function pause has expired and auto-unpause
    /// @param selector Function selector to check
    /// @dev Anyone can call this to unpause after expiry - safety mechanism
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

    /// @notice Set emergency admin address
    /// @dev Only owner can set emergency admin
    function setEmergencyAdmin(address _emergencyAdmin) external onlyOwner {
        address oldAdmin = emergencyAdmin;
        emergencyAdmin = _emergencyAdmin;
        emit EmergencyAdminUpdated(oldAdmin, _emergencyAdmin);
    }

    /// @notice Check if a function is currently paused
    /// @param selector Function selector to check
    /// @return Whether the function is paused
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
            emit FunctionPaused(criticalSelectors[i], false, msg.sender);
        }
    }
}