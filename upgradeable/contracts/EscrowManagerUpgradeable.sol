// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./UserEscrowUpgradeable.sol";
import "./interfaces/IEscrowFactory.sol";
import "./interfaces/IEscrowRegistry.sol";

/**
 * @title EscrowManagerUpgradeable
 * @notice Upgradeable version of EscrowManager for TVL aggregation + batch operations
 *
 * @dev Bot Terminology Guide:
 * - `authorizedBots` (Manager Bots): Bots authorized by owner to execute batch operations
 *   These bots can execute signed transactions on behalf of multiple users
 *   Requires both: (1) owner authorization AND (2) individual user permission
 * - Different from Factory botAddress which only has emergency pause powers
 * - See botTriggerEscrowWithSignatures() for bot execution flow
 */
contract EscrowManagerUpgradeable is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    IEscrowFactory public factory;
    IEscrowRegistry public escrowRegistry;

    /// @notice Bot automation system for batch operations
    /// @dev Bots must be authorized by owner AND have user permission to execute
    mapping(address => bool) public authorizedBots;

    /// @notice Tracks which users have granted permission to which bots
    /// @dev user => bot => allowed
    mapping(address => mapping(address => bool)) public userBotPermissions;
    mapping(address => uint256) public botNonces; // prevent replay attacks
    uint256 public maxBotValue; // maximum ETH value bots can handle per transaction
    bool public botSystemEnabled;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor)
     * @param factoryAddr Address of EscrowFactory
     * @param registryAddr Address of EscrowRegistry
     * @param initialOwner Address of contract owner
     * @param botAddr Address of bot to auto-authorize (can be zero)
     */
    function initialize(
        address factoryAddr,
        address registryAddr,
        address initialOwner,
        address botAddr
    ) public initializer {
        require(factoryAddr != address(0), "EscrowManager: factory address cannot be zero");
        require(registryAddr != address(0), "EscrowManager: registry address cannot be zero");
        require(initialOwner != address(0), "EscrowManager: owner address cannot be zero");

        __ReentrancyGuard_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        // Transfer ownership to initialOwner
        _transferOwnership(initialOwner);

        factory = IEscrowFactory(factoryAddr);
        escrowRegistry = IEscrowRegistry(registryAddr);
        maxBotValue = 1 ether;
        botSystemEnabled = true;

        // Auto-authorize bot during initialization if provided
        if (botAddr != address(0)) {
            authorizedBots[botAddr] = true;
            emit BotAuthorized(botAddr, true);
        }
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

    /// @notice Allow owner to update factory if needed
    function setFactory(address factoryAddr) external onlyOwner {
        require(factoryAddr != address(0), "EscrowManager: invalid factory");
        factory = IEscrowFactory(factoryAddr);
    }

    /// @notice Allow owner to update registry if needed
    function setRegistry(address registryAddr) external onlyOwner {
        require(registryAddr != address(0), "EscrowManager: invalid registry");
        escrowRegistry = IEscrowRegistry(registryAddr);
    }

    /// @notice Authorize or revoke a bot
    function setBotAuthorization(address bot, bool authorized) external onlyOwner {
        require(bot != address(0), "EscrowManager: invalid bot address");
        authorizedBots[bot] = authorized;
        emit BotAuthorized(bot, authorized);
    }

    /// @notice Users grant or revoke permission for a bot to act on their behalf
    function grantBotPermission(address bot, bool granted) external {
        require(authorizedBots[bot], "EscrowManager: bot not authorized by owner");
        userBotPermissions[msg.sender][bot] = granted;
        emit BotPermissionGranted(msg.sender, bot, granted);
    }

    /// @notice Owner can enable/disable the entire bot system
    function setBotSystemEnabled(bool enabled) external onlyOwner {
        botSystemEnabled = enabled;
    }

    /// @notice Owner can adjust the maximum value bots can handle
    function setMaxBotValue(uint256 newMax) external onlyOwner {
        maxBotValue = newMax;
    }

    /// @notice Bot executes a transaction on behalf of a user with signatures
    function botTriggerEscrowWithSignatures(
        address escrow,
        address target,
        uint256 value,
        bytes calldata data,
        bytes[] calldata signatures,
        uint256 deadline
    ) external onlyAuthorizedBot botValueLimit(value) nonReentrant {
        address user = UserEscrowUpgradeable(payable(escrow)).owner();
        require(userBotPermissions[user][msg.sender], "EscrowManager: user hasn't granted bot permission");

        UserEscrowUpgradeable(payable(escrow)).executeWithSignatures(
            target,
            value,
            data,
            signatures,
            deadline
        );

        emit BotTriggered(msg.sender, escrow, target);
    }

    /// @notice Get TVL across all provided escrows (caller must provide list)
    /// @dev Since registry doesn't have getAllEscrows, TVL must be calculated by caller providing escrow list
    function getTotalTVL(address[] memory escrows, address[] memory tokenAddresses) external view returns (uint256 totalETH, uint256[] memory totalTokens) {
        totalTokens = new uint256[](tokenAddresses.length);

        for (uint256 i = 0; i < escrows.length; i++) {
            address escrow = escrows[i];
            totalETH += escrow.balance;

            for (uint256 j = 0; j < tokenAddresses.length; j++) {
                totalTokens[j] += IERC20(tokenAddresses[j]).balanceOf(escrow);
            }
        }

        return (totalETH, totalTokens);
    }

    /// ========== Comprehensive TVL Functions ==========
    /// @notice Aggregate TVL across registered escrows with LP token tracking
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
                    continue;
                }

            (
                uint256 ethBal,
                uint256[] memory tokBals,
                , // tokenAddresses - unused
                uint256[] memory lp0,
                uint256[] memory lp1
            ) = UserEscrowUpgradeable(payable(esc)).getTotalTVL(tokens, lpPools);

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

    /// @notice Get TVL across all escrows for a specific pool
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
                    continue;
                }

                (
                    uint256 ethBal,
                    uint256[] memory tokBals,
                    ,
                    uint256[] memory lp0,
                    uint256[] memory lp1
                ) = UserEscrowUpgradeable(payable(escrowAddr)).getTotalTVL(tokens, lpPools);

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

    /// ========== User Trigger Functions ==========
    /// @notice Single escrow trigger by owner
    function triggerEscrowWithSignatures(
        address payable escrowAddr,
        address target,
        uint256 value,
        bytes memory data,
        bytes[] calldata signatures,
        uint256 deadline
    ) public payable nonReentrant {
        require(escrowAddr != address(0), "EscrowManager: escrow address cannot be zero");
        require(escrowRegistry.isRegisteredEscrow(escrowAddr), "EscrowManager: escrow is not registered");

        address escrowOwner = UserEscrowUpgradeable(escrowAddr).owner();
        require(
            msg.sender == escrowOwner,
            "EscrowManager: only escrow owner can trigger"
        );

        require(msg.value == value, "EscrowManager: msg.value does not match execution value");

        UserEscrowUpgradeable(escrowAddr).executeWithSignatures{value: msg.value}(
            target,
            value,
            data,
            signatures,
            deadline
        );

        emit EscrowTriggered(escrowAddr, target, value);
    }

    /// @notice Batch trigger multiple escrows by owner
    function batchTriggerEscrowWithSignatures(
        address payable[] calldata escrowAddrs,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] memory datas,
        bytes[][] calldata signaturesList,
        uint256[] calldata deadlines
    ) external payable nonReentrant {
        uint256 n = escrowAddrs.length;
        require(n > 0, "EscrowManager: cannot process empty arrays");
        require(n <= 10, "EscrowManager: batch size exceeds maximum");
        require(
            n == targets.length &&
            n == values.length &&
            n == datas.length &&
            n == signaturesList.length &&
            n == deadlines.length,
            "EscrowManager: array length mismatch"
        );

        uint256 totalValue = 0;
        for (uint256 i = 0; i < n; ++i) {
            totalValue += values[i];
        }
        require(totalValue == msg.value, "EscrowManager: msg.value mismatch");

        for (uint256 i = 0; i < n; ++i) {
            address payable esc = escrowAddrs[i];
            require(escrowRegistry.isRegisteredEscrow(esc), "EscrowManager: escrow not registered");

            address escrowOwner = UserEscrowUpgradeable(esc).owner();
            require(
                msg.sender == escrowOwner,
                "EscrowManager: only escrow owner can batch trigger"
            );

            UserEscrowUpgradeable(esc).executeWithSignatures{value: values[i]}(
                targets[i],
                values[i],
                datas[i],
                signaturesList[i],
                deadlines[i]
            );
        }

        emit BatchEscrowTriggered(n);
    }

    /// ========== Bot Automation Functions (with Nonce) ==========
    /// @notice Bot automated trigger with nonce protection
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
        require(escrowRegistry.isRegisteredEscrow(escrowAddr), "EscrowManager: escrow not registered");

        address escrowOwner = UserEscrowUpgradeable(payable(escrowAddr)).owner();

        require(
            userBotPermissions[escrowOwner][msg.sender],
            "EscrowManager: user hasn't granted bot permission"
        );

        require(
            botNonces[msg.sender] == nonce,
            "EscrowManager: invalid nonce"
        );
        botNonces[msg.sender]++;

        require(msg.value == value, "EscrowManager: msg.value mismatch");

        UserEscrowUpgradeable(payable(escrowAddr)).executeWithSignatures{value: msg.value}(
            target,
            value,
            data,
            signatures,
            deadline
        );

        emit BotTriggered(msg.sender, escrowAddr, target);
    }

    /// @notice Bot batch trigger with nonce protection
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
        require(n > 0, "EscrowManager: empty arrays");
        require(n <= 5, "EscrowManager: batch size exceeds maximum");
        require(
            n == targets.length &&
            n == values.length &&
            n == datas.length &&
            n == signaturesList.length &&
            n == deadlines.length,
            "EscrowManager: array length mismatch"
        );

        require(
            botNonces[msg.sender] == nonce,
            "EscrowManager: invalid nonce"
        );
        botNonces[msg.sender]++;

        uint256 totalValue = 0;
        for (uint256 i = 0; i < n; ++i) {
            totalValue += values[i];
        }
        require(totalValue <= maxBotValue, "EscrowManager: batch total exceeds limit");
        require(totalValue == msg.value, "EscrowManager: msg.value mismatch");

        for (uint256 i = 0; i < n; ++i) {
            address escrowAddr = escrowAddrs[i];
            require(escrowAddr != address(0), "EscrowManager: zero address");
            require(escrowRegistry.isRegisteredEscrow(escrowAddr), "EscrowManager: not registered");

            address escrowOwner = UserEscrowUpgradeable(payable(escrowAddr)).owner();
            require(
                userBotPermissions[escrowOwner][msg.sender],
                "EscrowManager: user hasn't granted permission"
            );

            UserEscrowUpgradeable(payable(escrowAddr)).executeWithSignatures{value: values[i]}(
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

    /// ========== Bot View & Security Functions ==========
    /// @notice Check if user has granted permission to bot
    function hasUserGrantedBotPermission(address user, address bot) external view returns (bool) {
        return userBotPermissions[user][bot];
    }

    /// @notice Get bot's current nonce
    function getBotNonce(address bot) external view returns (uint256) {
        return botNonces[bot];
    }

    /// @notice Get bot system info
    function getBotSystemInfo() external view returns (
        bool enabled,
        uint256 maxValue,
        uint256 totalAuthorizedBots
    ) {
        enabled = botSystemEnabled;
        maxValue = maxBotValue;
        totalAuthorizedBots = 0; // Placeholder
    }

    /// ========== Emergency Functions ==========
    /// @notice User emergency revoke all bot permissions
    function emergencyRevokeBotPermissions(address[] calldata bots) external {
        require(bots.length > 0, "EscrowManager: empty bots array");

        for (uint256 i = 0; i < bots.length; i++) {
            userBotPermissions[msg.sender][bots[i]] = false;
            emit BotPermissionGranted(msg.sender, bots[i], false);
        }
    }

    /// @notice Owner emergency disable bot system
    function emergencyDisableBotSystem() external onlyOwner {
        botSystemEnabled = false;
    }

    /// @notice Owner emergency revoke bot
    function emergencyRevokeBot(address bot) external onlyOwner {
        require(bot != address(0), "EscrowManager: zero bot address");
        authorizedBots[bot] = false;
        emit BotAuthorized(bot, false);
    }

    /// @notice Required by UUPS pattern - only owner can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[44] private __gap;
}
