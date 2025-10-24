// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IEscrowFactory.sol";
import "./interfaces/IWhitelistManager.sol";
import "./libraries/SecurityUtils.sol";

/**
 * @title UserEscrow
 * @notice Gas-optimized escrow contract with enhanced security features
 *
 * @dev This contract references factory.botAddress for pause/unpause functionality
 * The bot is set by EscrowFactory during creation and has emergency pause powers
 * For batch operation bots, see EscrowManager.authorizedBots
 * @dev Implements IERC721Receiver to safely receive NFTs from gauge unstaking
 */
contract UserEscrow is ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

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

    /* ========== STORAGE ========== */
    address public owner;
    address public pendingOwner;
    uint256 public pendingOwnerAvailableAt;
    uint256 public immutable ownershipDelay;

    IEscrowFactory public factory;
    IWhitelistManager public whitelistManager;
    address public immutable poolAddress;

    // Multi-sig
    address[] public approvers;
    mapping(address => bool) public isApproverMap;
    uint256 public threshold;

    uint256 public nonce;
    uint256 public immutable maxCalls;

    // Compact storage for efficiency
    address public usdcAddress;
    mapping(address => bool) public authorizedDepositors;

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
        // If factory is NOT live (dev mode), only allow whitelisted depositors
        if (!factory.isHasLive()) {
            require(whitelistManager.isWhitelisted(msg.sender), "dev mode: depositor not whitelisted");
        }
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _owner,
        address _poolAddress,
        address[] memory _approvers,
        uint256 _threshold,
        uint256 _maxCalls,
        uint256 _ownershipDelay,
        address _factory,
        address _whitelist,
        address _usdc
    ) {
        require(_owner != address(0) && _poolAddress != address(0), "zero address");
        require(_approvers.length >= _threshold && _threshold > 0, "invalid threshold");
        require(_approvers.length <= 10, "too many approvers"); // SECURITY FIX: Prevent DOS via gas exhaustion

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

    function depositToken(address token, uint256 amount) external whenNotPaused whenNotInEmergency notZero(token) onlyAllowedDepositors {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit DepositedToken(token, msg.sender, amount);
    }

    /// @notice Combined deposit function for ETH and USDC
    /// @param usdcAmount Amount of USDC to deposit (0 if no USDC)
    function deposit(uint256 usdcAmount) external payable whenNotPaused whenNotInEmergency onlyAllowedDepositors {
        // Deposit ETH if sent
        if (msg.value > 0) {
            emit DepositedETH(msg.sender, msg.value);
        }

        // Deposit USDC if specified
        if (usdcAmount > 0) {
            IERC20(usdcAddress).safeTransferFrom(msg.sender, address(this), usdcAmount);
            emit DepositedToken(usdcAddress, msg.sender, usdcAmount);
        }

        // Require at least one deposit
        require(msg.value > 0 || usdcAmount > 0, "UserEscrow: no assets to deposit");
    }

    /**
     * @notice Handle the receipt of an NFT (ERC721 token)
     * @dev Required to receive NFTs via safeTransferFrom (e.g., when unstaking from gauge)
     * @param operator The address which called `safeTransferFrom` function
     * @param from The address which previously owned the token
     * @param tokenId The NFT identifier which is being transferred
     * @param data Additional data with no specified format
     * @return bytes4 Returns `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        // Accept all NFT transfers
        // Note: Security is enforced by the whitelist system in executeWithSignatures
        return IERC721Receiver.onERC721Received.selector;
    }

    /* ========== WITHDRAWAL FUNCTIONS ========== */
    /// @notice Withdraw ETH - ALWAYS WORKS (even during pause/emergency)
    /// @dev NO pause/emergency modifiers to ensure users can always access funds
    function withdrawETH(address payable to)
        external
        nonReentrant
        onlyOwner
        notZero(to)
    {
        uint256 bal = address(this).balance;
        require(bal > 0, "no ETH");

        // Enhanced security check
        if (to.code.length > 0) {
            require(SecurityUtils.isValidWithdrawalTarget(to, owner, address(whitelistManager)), "invalid target");
        }

        SecurityUtils.secureETHTransfer(to, bal, address(whitelistManager));
        emit WithdrawnETH(to, bal);
    }

    /// @notice Withdraw tokens - ALWAYS WORKS (even during pause/emergency)
    /// @dev NO pause/emergency modifiers to ensure users can always access funds
    function withdrawToken(address token, address to)
        external
        nonReentrant
        onlyOwner
        notZero(token)
        notZero(to)
    {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        require(balanceBefore > 0, "no balance");

        // Enhanced security validation using library
        require(SecurityUtils.isValidTokenContract(token), "invalid token");
        if (to.code.length > 0) {
            require(SecurityUtils.isValidWithdrawalTarget(to, owner, address(whitelistManager)), "invalid target");
        }

        // Transfer all tokens
        IERC20(token).safeTransfer(to, balanceBefore);

        // Verify transfer completed - support fee-on-transfer tokens
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 actualTransferred = balanceBefore - balanceAfter;

        // Accept if at least 95% was transferred (5% max fee tolerance)
        // This supports fee-on-transfer tokens like PAXG, certain USDT configurations, etc.
        require(
            actualTransferred >= (balanceBefore * 95) / 100,
            "transfer failed or excessive fee"
        );

        emit WithdrawnToken(token, to, actualTransferred);
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
        require(targets.length <= 50, "array too large"); // DoS protection
        require(targets.length == datas.length && datas.length == values.length, "length mismatch");

        results = new bytes[](targets.length);
        uint256 totalValue = 0;

        // Validate and calculate total value
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            require(target != address(0), "zero target");
            require(target != address(this), "self-call not allowed");
            require(whitelistManager.isWhitelistedWithCaller(target, address(this)), "not whitelisted");

            totalValue = SecurityUtils.safeAdd(totalValue, values[i]);
        }
        require(totalValue == msg.value, "value mismatch");

        // Execute all calls
        for (uint256 i = 0; i < targets.length; i++) {
            SecurityUtils.checkGasLimit(50000); // Gas limit check

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
        require(block.timestamp < deadline, "expired"); // SECURITY FIX: Strict expiry check

        // Compute message hash - include owner to prevent cross-escrow replay
        bytes32 rawHash = keccak256(abi.encode(address(this), owner, block.chainid, target, value, keccak256(data), nonce, deadline));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rawHash));

        // Enhanced signature verification using library
        address[] memory signers = new address[](signatures.length);
        uint256 validSigners = 0;

        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = ECDSA.recover(messageHash, signatures[i]);

            // Use library for enhanced validation
            require(SecurityUtils.validateSignature(messageHash, signatures[i], signer), "invalid signature");
            require(isApproverMap[signer], "invalid signer");
            require(signer != address(0), "zero signer");

            // Check for duplicates
            for (uint256 j = 0; j < validSigners; j++) {
                require(signers[j] != signer, "duplicate signer");
            }
            signers[validSigners] = signer;
            validSigners++;
        }

        require(validSigners >= threshold, "insufficient valid signatures");
        require(value <= address(this).balance, "insufficient balance");

        // Execute call
        (bool ok, ) = target.call{value: value}(data);
        require(ok, "execution failed");

        // Increment nonce (automatic overflow protection in Solidity 0.8+)
        nonce++;

        emit ExecutedWithSignatures(target, value, data, signers);
    }

    /* ========== EMERGENCY CONTROLS ========== */

    /// @notice Pause this escrow (emergency stop for this escrow only)
    /// @dev Only owner can pause. Does not affect other escrows.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause this escrow
    /// @dev Only owner can unpause
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
        // Simplified TVL calculation
        uint256 ethBalance = address(this).balance;

        // Return basic info - can be extended as needed
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

        // Token balances
        tokenBalances = new uint256[](tokens.length);
        tokenAddresses = tokens;
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenBalances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }

        // LP balances (simplified)
        lpBalance0 = new uint256[](lpPools.length);
        lpBalance1 = new uint256[](lpPools.length);
        for (uint256 i = 0; i < lpPools.length; i++) {
            lpBalance0[i] = IERC20(lpPools[i]).balanceOf(address(this));
            lpBalance1[i] = 0; // Simplified for now
        }
    }

    /* ========== APPROVER MANAGEMENT ========== */
    /// @notice Add a new approver to the escrow
    /// @param approver Address of the new approver
    function addApprover(address approver) external onlyOwner notZero(approver) whenNotInEmergency {
        require(!isApproverMap[approver], "already approver");
        require(approvers.length < 10, "too many approvers"); // Max 10 approvers

        approvers.push(approver);
        isApproverMap[approver] = true;

        emit ApproverAdded(approver);
    }

    /// @notice Remove an approver from the escrow
    /// @param approver Address of the approver to remove
    function removeApprover(address approver) external onlyOwner whenNotInEmergency {
        require(isApproverMap[approver], "not an approver");
        require(approvers.length > threshold, "would break threshold");

        // SECURITY FIX: Remove ALL occurrences to prevent array/mapping mismatch
        uint256 writeIndex = 0;
        for (uint256 i = 0; i < approvers.length; i++) {
            if (approvers[i] != approver) {
                approvers[writeIndex] = approvers[i];
                writeIndex++;
            }
        }

        // Shrink array to remove all instances
        uint256 removedCount = approvers.length - writeIndex;
        require(removedCount > 0, "approver not found in array");

        for (uint256 i = 0; i < removedCount; i++) {
            approvers.pop();
        }

        isApproverMap[approver] = false;
        emit ApproverRemoved(approver);
    }

    /// @notice Update signature threshold
    /// @param newThreshold New threshold value
    function updateThreshold(uint256 newThreshold) external onlyOwner whenNotInEmergency {
        require(newThreshold > 0, "threshold must be > 0");
        require(newThreshold <= approvers.length, "threshold too high");

        threshold = newThreshold;
        // Emit event for transparency (can add ThresholdUpdated event if needed)
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
}