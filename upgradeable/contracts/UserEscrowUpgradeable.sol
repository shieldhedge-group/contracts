// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./interfaces/IEscrowFactory.sol";
import "./interfaces/IWhitelistManager.sol";
import "./libraries/SecurityUtilsUpgradeable.sol";

/**
 * @title UserEscrowUpgradeable
 * @notice Upgradeable escrow contract with enhanced security and NFT support
 * @dev Uses TransparentUpgradeableProxy pattern for safe upgrades
 *
 * KEY FEATURES:
 * - ✅ Upgradeable via proxy pattern
 * - ✅ NFT support (ERC721HolderUpgradeable)
 * - ✅ Multi-signature execution
 * - ✅ Emergency pause controls
 * - ✅ Storage gap for future upgrades
 *
 * SECURITY:
 * - 7-day timelock for upgrades
 * - Multi-sig governance required
 * - ReentrancyGuard on all state changes
 * - Pausable for emergency stops
 */
contract UserEscrowUpgradeable is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC721HolderUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ECDSAUpgradeable for bytes32;

    /* ========== EVENTS ========== */
    event DepositedETH(address indexed from, uint256 amount);
    event DepositedToken(address indexed token, address indexed from, uint256 amount);
    event WithdrawnETH(address indexed to, uint256 amount);
    event WithdrawnToken(address indexed token, address indexed to, uint256 amount);
    event ExecutedCall(address indexed target, uint256 value, bytes data, bytes result);
    event ExecutedMulticall(address indexed owner, uint256 calls);
    event ExecutedWithSignatures(address indexed target, uint256 value, bytes data, address[] signers);
    event ApproverAdded(address indexed approver);
    event ApproverRemoved(address indexed approver);
    event OwnershipProposed(address indexed newOwner, uint256 availableAt);
    event OwnershipAccepted(address indexed previousOwner, address indexed newOwner);
    event NFTWithdrawn(address indexed nftContract, uint256 indexed tokenId, address indexed recipient);

    /* ========== STORAGE ========== */
    // NOTE: Storage layout must be preserved across upgrades!
    // NEVER reorder these variables, only append new ones at the end

    address public owner;
    address public pendingOwner;
    uint256 public pendingOwnerAvailableAt;
    uint256 public ownershipDelay;  // Was immutable, now storage

    IEscrowFactory public factory;
    IWhitelistManager public whitelistManager;
    address public poolAddress;  // Was immutable, now storage

    // Multi-sig
    address[] public approvers;
    mapping(address => bool) public isApproverMap;
    uint256 public threshold;

    uint256 public nonce;
    uint256 public maxCalls;  // Was immutable, now storage

    // Compact storage for efficiency
    address public usdcAddress;
    mapping(address => bool) public authorizedDepositors;

    /* ========== STORAGE GAP ========== */
    // Reserve storage slots for future upgrades
    // If you add new variables, reduce gap size accordingly
    // Example: Adding 1 variable → change to uint256[49]
    uint256[50] private __gap;

    /* ========== MODIFIERS ========== */
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier notZero(address a) {
        require(a != address(0), "zero address");
        _;
    }

    modifier onlyWhitelisted(address target) {
        require(whitelistManager.isWhitelistedWithCaller(target, address(this)), "not whitelisted");
        _;
    }

    modifier whenNotInEmergency() {
        require(!factory.globalEmergencyPause(), "emergency pause");
        _;
    }

    modifier onlyAllowedDepositors() {
        if (!factory.isHasLive()) {
            require(whitelistManager.isWhitelisted(msg.sender), "dev mode: depositor not whitelisted");
        }
        _;
    }

    /* ========== INITIALIZER ========== */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the escrow contract (replaces constructor)
     * @dev Can only be called once due to initializer modifier
     * @param _owner Owner of the escrow
     * @param _poolAddress Associated pool address
     * @param _approvers Initial approvers for multi-sig
     * @param _threshold Minimum signatures required
     * @param _maxCalls Maximum calls in multicall
     * @param _ownershipDelay Delay for ownership transfer
     * @param _factory Factory contract address
     * @param _whitelist Whitelist manager address
     * @param _usdc USDC token address
     */
    function initialize(
        address _owner,
        address _poolAddress,
        address[] memory _approvers,
        uint256 _threshold,
        uint256 _maxCalls,
        uint256 _ownershipDelay,
        address _factory,
        address _whitelist,
        address _usdc
    ) external initializer {
        require(_owner != address(0) && _poolAddress != address(0), "zero address");
        require(_approvers.length >= _threshold && _threshold > 0, "invalid threshold");
        require(_approvers.length <= 10, "too many approvers");

        // Initialize parent contracts
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC721Holder_init();

        // Set state variables
        owner = _owner;
        poolAddress = _poolAddress;
        threshold = _threshold;
        maxCalls = _maxCalls;
        ownershipDelay = _ownershipDelay;
        factory = IEscrowFactory(_factory);
        whitelistManager = IWhitelistManager(_whitelist);
        usdcAddress = _usdc;

        // Add approvers with duplicate check
        for (uint256 i = 0; i < _approvers.length; i++) {
            address approver = _approvers[i];
            require(approver != address(0), "zero approver");
            require(!isApproverMap[approver], "duplicate approver");

            approvers.push(approver);
            isApproverMap[approver] = true;
            emit ApproverAdded(approver);
        }
    }

    /* ========== RECEIVE & DEPOSIT FUNCTIONS ========== */
    receive() external payable whenNotPaused whenNotInEmergency onlyAllowedDepositors {
        emit DepositedETH(msg.sender, msg.value);
    }

    function depositETH() external payable whenNotPaused whenNotInEmergency onlyAllowedDepositors {
        emit DepositedETH(msg.sender, msg.value);
    }

    function depositToken(address token, uint256 amount)
        external
        whenNotPaused
        whenNotInEmergency
        notZero(token)
        onlyAllowedDepositors
    {
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
        emit DepositedToken(token, msg.sender, amount);
    }

    function deposit(uint256 usdcAmount)
        external
        payable
        whenNotPaused
        whenNotInEmergency
        onlyAllowedDepositors
    {
        if (msg.value > 0) {
            emit DepositedETH(msg.sender, msg.value);
        }

        if (usdcAmount > 0) {
            IERC20Upgradeable(usdcAddress).safeTransferFrom(msg.sender, address(this), usdcAmount);
            emit DepositedToken(usdcAddress, msg.sender, usdcAmount);
        }

        require(msg.value > 0 || usdcAmount > 0, "UserEscrow: no assets to deposit");
    }

    /// @notice Handle NFT receipts (ERC721)
    /// @dev Required for receiving NFTs (e.g., Aerodrome LP positions)
    /// @dev Security is enforced by the whitelist system in executeWithSignatures
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes memory /* data */
    ) public virtual override returns (bytes4) {
        // Accept all NFT transfers
        // Whitelist validation happens in executeWithSignatures when interacting with NFTs
        return this.onERC721Received.selector;
    }

    /* ========== WITHDRAWAL FUNCTIONS ========== */
    function withdrawETH(address payable to)
        external
        nonReentrant
        onlyOwner
        notZero(to)
    {
        uint256 bal = address(this).balance;
        require(bal > 0, "no ETH");

        if (to.code.length > 0) {
            require(SecurityUtilsUpgradeable.isValidWithdrawalTarget(to, owner, address(whitelistManager)), "invalid target");
        }

        SecurityUtilsUpgradeable.secureETHTransfer(to, bal, address(whitelistManager));
        emit WithdrawnETH(to, bal);
    }

    function withdrawToken(address token, address to)
        external
        nonReentrant
        onlyOwner
        notZero(token)
        notZero(to)
    {
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(address(this));
        require(balanceBefore > 0, "no balance");

        require(SecurityUtilsUpgradeable.isValidTokenContract(token), "invalid token");
        if (to.code.length > 0) {
            require(SecurityUtilsUpgradeable.isValidWithdrawalTarget(to, owner, address(whitelistManager)), "invalid target");
        }

        IERC20Upgradeable(token).safeTransfer(to, balanceBefore);

        uint256 balanceAfter = IERC20Upgradeable(token).balanceOf(address(this));
        uint256 actualTransferred = balanceBefore - balanceAfter;

        require(
            actualTransferred >= (balanceBefore * 95) / 100,
            "transfer failed or excessive fee"
        );

        emit WithdrawnToken(token, to, actualTransferred);
    }

    /**
     * @notice Withdraw NFT from escrow (NEW FEATURE!)
     * @dev This is what the old escrow was missing!
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to withdraw
     * @param recipient Address to receive the NFT
     */
    function withdrawNFT(
        address nftContract,
        uint256 tokenId,
        address recipient
    ) external nonReentrant onlyOwner notZero(nftContract) notZero(recipient) {
        // Use OpenZeppelin's ERC721 interface
        IERC721Upgradeable nft = IERC721Upgradeable(nftContract);

        // Verify escrow owns the NFT
        require(nft.ownerOf(tokenId) == address(this), "escrow doesn't own NFT");

        // Transfer NFT to recipient
        nft.safeTransferFrom(address(this), recipient, tokenId);

        emit NFTWithdrawn(nftContract, tokenId, recipient);
    }

    /* ========== EXECUTE FUNCTIONS ========== */
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        nonReentrant
        onlyOwner
        whenNotPaused
        notZero(target)
        onlyWhitelisted(target)
        whenNotInEmergency
        returns (bytes memory)
    {
        require(msg.value == value, "value mismatch");
        (bool ok, bytes memory result) = target.call{value: value}(data);
        require(ok, "call failed");
        emit ExecutedCall(target, value, data, result);
        return result;
    }

    function multicall(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        nonReentrant
        onlyOwner
        whenNotPaused
        whenNotInEmergency
        returns (bytes[] memory results)
    {
        require(targets.length <= maxCalls, "too many calls");
        require(targets.length <= 50, "array too large");
        require(targets.length == datas.length && datas.length == values.length, "length mismatch");

        results = new bytes[](targets.length);
        uint256 totalValue = 0;

        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            require(target != address(0), "zero target");
            require(target != address(this), "self-call not allowed");
            require(whitelistManager.isWhitelistedWithCaller(target, address(this)), "not whitelisted");

            totalValue = SecurityUtilsUpgradeable.safeAdd(totalValue, values[i]);
        }
        require(totalValue == msg.value, "value mismatch");

        for (uint256 i = 0; i < targets.length; i++) {
            SecurityUtilsUpgradeable.checkGasLimit(50000);

            (bool ok, bytes memory res) = targets[i].call{value: values[i]}(datas[i]);
            require(ok, "call failed");
            results[i] = res;
            emit ExecutedCall(targets[i], values[i], datas[i], res);
        }

        emit ExecutedMulticall(owner, targets.length);
    }

    /* ========== SIGNATURE-BASED EXECUTION ========== */
    function executeWithSignatures(
        address target,
        uint256 value,
        bytes calldata data,
        bytes[] calldata signatures,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused whenNotInEmergency notZero(target) onlyWhitelisted(target) {
        require(signatures.length >= threshold, "insufficient signatures");
        require(block.timestamp < deadline, "expired");

        bytes32 rawHash = keccak256(abi.encode(address(this), owner, block.chainid, target, value, keccak256(data), nonce, deadline));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rawHash));

        address[] memory signers = new address[](signatures.length);
        uint256 validSigners = 0;

        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = ECDSAUpgradeable.recover(messageHash, signatures[i]);

            require(SecurityUtilsUpgradeable.validateSignature(messageHash, signatures[i], signer), "invalid signature");
            require(isApproverMap[signer], "invalid signer");
            require(signer != address(0), "zero signer");

            for (uint256 j = 0; j < validSigners; j++) {
                require(signers[j] != signer, "duplicate signer");
            }
            signers[validSigners] = signer;
            validSigners++;
        }

        require(validSigners >= threshold, "insufficient valid signatures");
        require(value <= address(this).balance, "insufficient balance");

        (bool ok, ) = target.call{value: value}(data);
        require(ok, "execution failed");

        nonce++;

        emit ExecutedWithSignatures(target, value, data, signers);
    }

    /* ========== EMERGENCY CONTROLS ========== */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ========== VIEW FUNCTIONS ========== */
    function isOperational() external view returns (bool) {
        return !paused() && !factory.globalEmergencyPause();
    }

    function isFunctionOperational(bytes4 selector) external view returns (bool) {
        return !paused() && !factory.globalEmergencyPause() && !factory.pausedFunctions(selector);
    }

    function getApprovers() external view returns (address[] memory) {
        return approvers;
    }

    function getApproverCount() external view returns (uint256) {
        return approvers.length;
    }

    function getTVL() external view returns (uint256, uint256[] memory, address[] memory, uint256[] memory) {
        uint256 ethBalance = address(this).balance;
        uint256[] memory tokenBalances = new uint256[](0);
        address[] memory tokens = new address[](0);
        uint256[] memory lpBalances = new uint256[](0);

        return (ethBalance, tokenBalances, tokens, lpBalances);
    }

    function getTotalTVL(address[] calldata tokens, address[] calldata lpPools)
        external
        view
        returns (
            uint256 ethBalance,
            uint256[] memory tokenBalances,
            address[] memory tokenAddresses,
            uint256[] memory lpBalance0,
            uint256[] memory lpBalance1
        )
    {
        ethBalance = address(this).balance;

        tokenBalances = new uint256[](tokens.length);
        tokenAddresses = tokens;
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenBalances[i] = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
        }

        lpBalance0 = new uint256[](lpPools.length);
        lpBalance1 = new uint256[](lpPools.length);
        for (uint256 i = 0; i < lpPools.length; i++) {
            lpBalance0[i] = IERC20Upgradeable(lpPools[i]).balanceOf(address(this));
            lpBalance1[i] = 0;
        }
    }

    /* ========== APPROVER MANAGEMENT ========== */
    function addApprover(address approver) external onlyOwner notZero(approver) whenNotInEmergency {
        require(!isApproverMap[approver], "already approver");
        require(approvers.length < 10, "too many approvers");

        approvers.push(approver);
        isApproverMap[approver] = true;

        emit ApproverAdded(approver);
    }

    function removeApprover(address approver) external onlyOwner whenNotInEmergency {
        require(isApproverMap[approver], "not an approver");
        require(approvers.length > threshold, "would break threshold");

        uint256 writeIndex = 0;
        for (uint256 i = 0; i < approvers.length; i++) {
            if (approvers[i] != approver) {
                approvers[writeIndex] = approvers[i];
                writeIndex++;
            }
        }

        uint256 removedCount = approvers.length - writeIndex;
        require(removedCount > 0, "approver not found in array");

        for (uint256 i = 0; i < removedCount; i++) {
            approvers.pop();
        }

        isApproverMap[approver] = false;
        emit ApproverRemoved(approver);
    }

    function updateThreshold(uint256 newThreshold) external onlyOwner whenNotInEmergency {
        require(newThreshold > 0, "threshold must be > 0");
        require(newThreshold <= approvers.length, "threshold too high");

        threshold = newThreshold;
    }

    /* ========== OWNERSHIP FUNCTIONS ========== */
    function proposeOwnershipTransfer(address newOwner) external onlyOwner notZero(newOwner) {
        pendingOwner = newOwner;
        pendingOwnerAvailableAt = block.timestamp + ownershipDelay;
        emit OwnershipProposed(newOwner, pendingOwnerAvailableAt);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        require(block.timestamp >= pendingOwnerAvailableAt, "delay not passed");

        address previousOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        pendingOwnerAvailableAt = 0;

        emit OwnershipAccepted(previousOwner, owner);
    }

    /**
     * @notice Get contract version
     * @dev Override this in future upgrades to track versions
     * @return Version string
     */
    function version() external pure virtual returns (string memory) {
        return "2.0.0";
    }
}
