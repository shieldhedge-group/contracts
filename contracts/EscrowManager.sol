// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./UserEscrow.sol";
import "./interfaces/IEscrowFactory.sol";
import "./interfaces/IEscrowRegistry.sol";

/**
 * @title EscrowManager
 * @notice TVL aggregation + trigger / batch trigger for registered escrows
 *
 * @dev Bot Terminology Guide:
 * - `authorizedBots` (Manager Bots): Bots authorized by owner to execute batch operations
 *   These bots can execute signed transactions on behalf of multiple users
 *   Requires both: (1) owner authorization AND (2) individual user permission
 * - Different from Factory botAddress which only has emergency pause powers
 * - See botTriggerEscrowWithSignatures() for bot execution flow
 */
contract EscrowManager is ReentrancyGuard {
    IEscrowFactory public factory;
    IEscrowRegistry public escrowRegistry;
    address public owner;

    /// @notice Bot automation system for batch operations
    /// @dev Bots must be authorized by owner AND have user permission to execute
    mapping(address => bool) public authorizedBots;

    /// @notice Tracks which users have granted permission to which bots
    /// @dev user => bot => allowed
    mapping(address => mapping(address => bool)) public userBotPermissions;
    mapping(address => uint256) public botNonces; // prevent replay attacks
    uint256 public maxBotValue = 1 ether; // maximum ETH value bots can handle per transaction
    bool public botSystemEnabled = true;

    event EscrowTriggered(address indexed escrow, address indexed target, uint256 value);
    event BatchEscrowTriggered(uint256 count);
    event BotAuthorized(address indexed bot, bool authorized);
    event BotPermissionGranted(address indexed user, address indexed bot, bool granted);
    event BotTriggered(address indexed bot, address indexed escrow, address indexed target);

    struct TVLData {
        uint256 ethBal;
        uint256[] tokBals;
        uint256[] lp0;
        uint256[] lp1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "EscrowManager: caller is not the owner");
        _;
    }

    modifier onlyAuthorizedBot() {
        require(botSystemEnabled, "EscrowManager: bot system disabled");
        require(authorizedBots[msg.sender], "EscrowManager: unauthorized bot");
        _;
    }

    modifier botValueLimit(uint256 value) {
        require(value <= maxBotValue, "EscrowManager: value exceeds bot limit");
        _;
    }

    constructor(address factoryAddr, address registryAddr, address botAddr) {
        require(factoryAddr != address(0), "EscrowManager: factory address cannot be zero");
        require(registryAddr != address(0), "EscrowManager: registry address cannot be zero");
        factory = IEscrowFactory(factoryAddr);
        escrowRegistry = IEscrowRegistry(registryAddr);
        owner = msg.sender;

        // Auto-authorize bot during deployment if provided
        if (botAddr != address(0)) {
            authorizedBots[botAddr] = true;
            emit BotAuthorized(botAddr, true);
        }
    }

    /// @notice allow owner to update factory if needed
    function setFactory(address factoryAddr) external onlyOwner {
        require(factoryAddr != address(0), "EscrowManager: factory address cannot be zero");
        factory = IEscrowFactory(factoryAddr);
    }

    /// ========== Bot Authorization Management ==========
    /// @notice authorize/deauthorize bots (only owner)
    function setAuthorizedBot(address bot, bool authorized) external onlyOwner {
        require(bot != address(0), "EscrowManager: zero bot address");
        authorizedBots[bot] = authorized;
        emit BotAuthorized(bot, authorized);
    }


    /// @notice enable/disable bot system (only owner)
    function setBotSystemEnabled(bool enabled) external onlyOwner {
        botSystemEnabled = enabled;
    }

    /// @notice set maximum ETH value bots can handle per transaction (only owner)
    function setMaxBotValue(uint256 newMaxValue) external onlyOwner {
        require(newMaxValue > 0, "EscrowManager: invalid max value");
        maxBotValue = newMaxValue;
    }

    /// @notice user grants permission to specific bot to operate their escrow
    function grantBotPermission(address bot, bool granted) external {
        require(bot != address(0), "EscrowManager: zero bot address");
        require(authorizedBots[bot], "EscrowManager: bot not authorized");

        userBotPermissions[msg.sender][bot] = granted;
        emit BotPermissionGranted(msg.sender, bot, granted);
    }

    /// ========== TVL Aggregation ==========
    /// @notice aggregate TVL across registered escrows
    function getTotalTVLAllEscrows(
        address[] calldata escrows,
        address[] calldata tokens,
        address[] calldata lpPools
    )
        external
        view
        returns (
            uint256 totalETH,
            uint256[] memory totalTokens,
            uint256[] memory totalLP0,
            uint256[] memory totalLP1
        )
    {
        uint256 numEscrows = escrows.length;
        uint256 numTokens = tokens.length;
        uint256 numPools = lpPools.length;

        totalTokens = new uint256[](numTokens);
        totalLP0 = new uint256[](numPools);
        totalLP1 = new uint256[](numPools);

        unchecked {
            for (uint256 i = 0; i < numEscrows; ++i) {
                address esc = escrows[i];
                if (!escrowRegistry.isRegisteredEscrow(esc)) {
                    // skip non-registered - keep view function safe
                    continue;
                }

            (
                uint256 ethBal,
                uint256[] memory tokBals,
                , // tokenAddresses - unused, already known from input
                uint256[] memory lp0,
                uint256[] memory lp1
            ) = UserEscrow(payable(esc)).getTotalTVL(tokens, lpPools);

                totalETH += ethBal;

                // assume lengths match inputs (UserEscrow should guarantee this)
                for (uint256 j = 0; j < numTokens; ++j) {
                    totalTokens[j] += tokBals[j];
                }
                for (uint256 k = 0; k < numPools; ++k) {
                    totalLP0[k] += lp0[k];
                    totalLP1[k] += lp1[k];
                }
            }
        }

        return (totalETH, totalTokens, totalLP0, totalLP1);
    }

    /// ========== Trigger Single Escrow ==========
    function triggerEscrowWithSignatures(
        address payable escrowAddr,
        address target,
        uint256 value,
        bytes memory data,
        bytes[] calldata signatures,
        uint256 deadline
    ) public payable nonReentrant {
        require(escrowAddr != address(0), "EscrowManager: escrow address cannot be zero");
        require(escrowRegistry.isRegisteredEscrow(escrowAddr), "EscrowManager: escrow is not registered in registry");

        // FIXED: Only allow escrow owner to trigger their own escrow
        address escrowOwner = UserEscrow(escrowAddr).owner();
        require(
            msg.sender == escrowOwner,
            "EscrowManager: only escrow owner can trigger"
        );

        // Validate msg.value matches execution value
        require(msg.value == value, "EscrowManager: msg.value does not match execution value");

        // Forward ETH to escrow for execution
        UserEscrow(escrowAddr).executeWithSignatures{value: msg.value}(
            target,
            value,
            data,
            signatures,
            deadline
        );

        emit EscrowTriggered(escrowAddr, target, value);
    }





    /// ========== Batch Trigger ==========
    /// datas passed as memory so compatible with calldata bytes[] usage
    function batchTriggerEscrowWithSignatures(
        address payable[] calldata escrowAddrs,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] memory datas,
        bytes[][] calldata signaturesList,
        uint256[] calldata deadlines
    ) external payable nonReentrant {
        uint256 n = escrowAddrs.length;
        require(n > 0, "EscrowManager: cannot process empty escrow arrays");
        require(n <= 10, "EscrowManager: batch size exceeds maximum of 10 escrows"); // Prevent gas limit issues
        require(
            n == targets.length &&
            n == values.length &&
            n == datas.length &&
            n == signaturesList.length &&
            n == deadlines.length,
            "EscrowManager: all input arrays must have the same length"
        );

        // CRITICAL: Check overflow-safe total value calculation
        uint256 totalValue = 0;
        for (uint256 i = 0; i < n; ++i) {
            totalValue += values[i]; // Use checked math (Solidity 0.8+)
        }
        require(totalValue == msg.value, "EscrowManager: msg.value does not match batch total value");

        for (uint256 i = 0; i < n; ++i) {
            address payable esc = escrowAddrs[i];
            require(escrowRegistry.isRegisteredEscrow(esc), "EscrowManager: escrow in batch is not registered");

            // FIXED: Authorization check for EACH escrow - only escrow owner
            address escrowOwner = UserEscrow(esc).owner();
            require(
                msg.sender == escrowOwner,
                "EscrowManager: only escrow owner can batch trigger"
            );

            // CRITICAL: NO MORE AUTOMATIC DEPOSITS - too dangerous
            // Users must deposit separately to maintain authorization
            require(values[i] == 0 || values[i] <= esc.balance, "EscrowManager: insufficient balance in escrow for operation");

            // Execute with signatures, forwarding ETH if needed
            UserEscrow(esc).executeWithSignatures{value: values[i]}(
                targets[i],
                values[i],
                datas[i],
                signaturesList[i],
                deadlines[i]
            );
        }

        emit BatchEscrowTriggered(n);
    }


    /// ========== Pool-Based TVL Functions ==========

    /// @notice get TVL across all escrows for a specific pool
    function getTVLForPool(
        address poolAddress,
        address[] calldata users,
        address[] calldata tokens,
        address[] calldata lpPools
    )
        external
        view
        returns (
            uint256 totalETH,
            uint256[] memory totalTokens,
            uint256[] memory totalLP0,
            uint256[] memory totalLP1
        )
    {
        uint256 numUsers = users.length;
        uint256 numTokens = tokens.length;
        uint256 numPools = lpPools.length;

        totalTokens = new uint256[](numTokens);
        totalLP0 = new uint256[](numPools);
        totalLP1 = new uint256[](numPools);

        unchecked {
            for (uint256 i = 0; i < numUsers; ++i) {
                address escrowAddr = escrowRegistry.getEscrowForPool(users[i], poolAddress);
                if (escrowAddr == address(0)) {
                    continue; // Skip if user doesn't have escrow for this pool
                }

                (
                    uint256 ethBal,
                    uint256[] memory tokBals,
                    , // tokenAddresses - unused, already known from input
                    uint256[] memory lp0,
                    uint256[] memory lp1
                ) = UserEscrow(payable(escrowAddr)).getTotalTVL(tokens, lpPools);

                totalETH += ethBal;

                for (uint256 j = 0; j < numTokens; ++j) {
                    totalTokens[j] += tokBals[j];
                }
                for (uint256 k = 0; k < numPools; ++k) {
                    totalLP0[k] += lp0[k];
                    totalLP1[k] += lp1[k];
                }
            }
        }

        return (totalETH, totalTokens, totalLP0, totalLP1);
    }

    /// ========== Bot Automation Functions ==========
    /// @notice bot automated trigger for rebalancing LP, swaps, and DeFi operations
    function botTriggerEscrow(
        address escrowAddr,
        address target,
        uint256 value,
        bytes calldata data,
        bytes[] calldata signatures,
        uint256 deadline,
        uint256 nonce
    ) external payable nonReentrant onlyAuthorizedBot botValueLimit(value) {
        require(escrowAddr != address(0), "EscrowManager: escrow address cannot be zero");
        require(escrowRegistry.isRegisteredEscrow(escrowAddr), "EscrowManager: escrow is not registered in registry");

        // Get escrow owner
        address escrowOwner = UserEscrow(payable(escrowAddr)).owner();

        // CRITICAL: Check user granted permission to this bot
        require(
            userBotPermissions[escrowOwner][msg.sender],
            "EscrowManager: escrow owner has not granted permission to this bot"
        );

        // Prevent replay attacks
        require(
            botNonces[msg.sender] == nonce,
            "EscrowManager: invalid nonce - expected current bot nonce"
        );
        botNonces[msg.sender]++;

        // CRITICAL: Validate msg.value matches execution value
        require(msg.value == value, "EscrowManager: msg.value does not match execution value");

        // Execute the operation via escrow's signature system
        UserEscrow(payable(escrowAddr)).executeWithSignatures{value: msg.value}(
            target,
            value,
            data,
            signatures,
            deadline
        );

        emit BotTriggered(msg.sender, escrowAddr, target);
    }

    /// @notice bot automated trigger for multiple escrows (batch rebalancing)
    function botBatchTrigger(
        address[] calldata escrowAddrs,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes[][] calldata signaturesList,
        uint256[] calldata deadlines,
        uint256 nonce
    ) external payable nonReentrant onlyAuthorizedBot {
        uint256 n = escrowAddrs.length;
        require(n > 0, "EscrowManager: cannot process empty escrow arrays");
        require(n <= 5, "EscrowManager: batch size exceeds maximum of 5 escrows"); // Limit bot batch size
        require(
            n == targets.length &&
            n == values.length &&
            n == datas.length &&
            n == signaturesList.length &&
            n == deadlines.length,
            "EscrowManager: all input arrays must have the same length"
        );

        // Prevent replay attacks
        require(
            botNonces[msg.sender] == nonce,
            "EscrowManager: invalid nonce for batch operation"
        );
        botNonces[msg.sender]++;

        // Calculate and validate total value
        uint256 totalValue = 0;
        for (uint256 i = 0; i < n; ++i) {
            totalValue += values[i];
        }
        require(totalValue <= maxBotValue, "EscrowManager: batch total value exceeds maximum bot limit");
        require(totalValue == msg.value, "EscrowManager: msg.value does not match batch total value");

        // Process each escrow
        for (uint256 i = 0; i < n; ++i) {
            address escrowAddr = escrowAddrs[i];
            require(escrowAddr != address(0), "EscrowManager: escrow address in batch cannot be zero");
            require(escrowRegistry.isRegisteredEscrow(escrowAddr), "EscrowManager: escrow in batch is not registered");

            // Get escrow owner and check permissions
            address escrowOwner = UserEscrow(payable(escrowAddr)).owner();
            require(
                userBotPermissions[escrowOwner][msg.sender],
                "EscrowManager: escrow owner in batch has not granted bot permission"
            );

            // Execute operation with proper ETH forwarding
            UserEscrow(payable(escrowAddr)).executeWithSignatures{value: values[i]}(
                targets[i],
                values[i],
                datas[i],
                signaturesList[i],
                deadlines[i]
            );

            emit BotTriggered(msg.sender, escrowAddr, targets[i]);
        }

        emit BatchEscrowTriggered(n);
    }


    /// ========== Bot Security & View Functions ==========
    /// @notice check if user has granted permission to bot
    function hasUserGrantedBotPermission(address user, address bot) external view returns (bool) {
        return userBotPermissions[user][bot];
    }

    /// @notice get bot's current nonce
    function getBotNonce(address bot) external view returns (uint256) {
        return botNonces[bot];
    }

    /// @notice emergency: revoke all bot permissions for a user (called by user)
    function emergencyRevokeBotPermissions(address[] calldata bots) external {
        require(bots.length > 0, "EscrowManager: empty bots array");

        for (uint256 i = 0; i < bots.length; i++) {
            userBotPermissions[msg.sender][bots[i]] = false;
            emit BotPermissionGranted(msg.sender, bots[i], false);
        }
    }

    /// @notice emergency: disable entire bot system (only owner)
    function emergencyDisableBotSystem() external onlyOwner {
        botSystemEnabled = false;
    }

    /// @notice emergency: revoke bot authorization (only owner)
    function emergencyRevokeBot(address bot) external onlyOwner {
        require(bot != address(0), "EscrowManager: zero bot address");
        authorizedBots[bot] = false;
        emit BotAuthorized(bot, false);
    }

    /// @notice get bot system status and limits
    function getBotSystemInfo() external view returns (
        bool enabled,
        uint256 maxValue,
        uint256 totalAuthorizedBots
    ) {
        enabled = botSystemEnabled;
        maxValue = maxBotValue;
        // Note: totalAuthorizedBots would need additional tracking for exact count
        totalAuthorizedBots = 0; // Placeholder - could implement counter if needed
    }

    /// ========== Helper Functions ==========
}
