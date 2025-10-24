// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IUserEscrow {
    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory);
    function multicall(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external payable returns (bytes[] memory);
    function addApprover(address newApprover) external;
    function removeApprover(address approver) external;
    function pause() external;
    function unpause() external;
    function owner() external view returns (address);
    function nonce() external view returns (uint256);
}

interface IEscrowFactory {
    function setGlobalEmergency(bool _paused) external;
    function pauseFunction(bytes4 selector, bool _paused) external;
    function emergencyAdmin() external view returns (address);
    function owner() external view returns (address);
}

/**
 * @title StateCorruptor
 * @dev Contract untuk testing state manipulation dan corruption attacks
 */
contract StateCorruptor {
    IUserEscrow public targetEscrow;
    IEscrowFactory public targetFactory;

    mapping(address => uint256) public corruptionAttempts;
    mapping(bytes32 => bool) public executedOperations;

    event StateCorruptionAttempt(string attackType, bool success, bytes reason);
    event NonceManipulation(uint256 oldNonce, uint256 expectedNonce, uint256 actualNonce);
    event OwnershipCorruption(address originalOwner, address attemptedOwner);

    constructor() {}

    function setTargets(address _escrow, address _factory) external {
        targetEscrow = IUserEscrow(_escrow);
        targetFactory = IEscrowFactory(_factory);
    }

    // Attack 1: Race condition dalam multicall
    function attemptRaceConditionAttack() external {
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory datas = new bytes[](3);

        // Setup race condition: three operations that depend on each other
        targets[0] = address(targetEscrow);
        targets[1] = address(targetEscrow);
        targets[2] = address(targetEscrow);

        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        // Operation 1: Add this contract as approver
        datas[0] = abi.encodeWithSignature("addApprover(address)", address(this));

        // Operation 2: Remove original approver (race condition)
        datas[1] = abi.encodeWithSignature("removeApprover(address)", targetEscrow.owner());

        // Operation 3: Try to execute something as new approver
        datas[2] = abi.encodeWithSignature("pause()");

        try targetEscrow.multicall(targets, values, datas) {
            emit StateCorruptionAttempt("race-condition", true, "");
        } catch (bytes memory reason) {
            emit StateCorruptionAttempt("race-condition", false, reason);
        }
    }

    // Attack 2: State corruption via failed transactions
    function attemptFailedTransactionCorruption() external {
        corruptionAttempts[msg.sender]++;

        // Try to corrupt state by causing partial failures
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        targets[0] = address(this); // Valid target
        targets[1] = address(0);    // Invalid target - should cause failure

        values[0] = 0;
        values[1] = 1 ether; // Try to send ETH to zero address

        datas[0] = abi.encodeWithSignature("maliciousCallback()");
        datas[1] = "";

        try targetEscrow.multicall(targets, values, datas) {
            emit StateCorruptionAttempt("failed-transaction", true, "");
        } catch (bytes memory reason) {
            emit StateCorruptionAttempt("failed-transaction", false, reason);
        }
    }

    // Attack 3: Nonce manipulation
    function attemptNonceManipulation() external {
        uint256 oldNonce = targetEscrow.nonce();

        try targetEscrow.execute(
            address(this),
            0,
            abi.encodeWithSignature("revertAfterNonceChange()")
        ) {
            uint256 newNonce = targetEscrow.nonce();
            emit NonceManipulation(oldNonce, oldNonce + 1, newNonce);
            emit StateCorruptionAttempt("nonce-manipulation", true, "");
        } catch (bytes memory reason) {
            uint256 finalNonce = targetEscrow.nonce();
            emit NonceManipulation(oldNonce, oldNonce, finalNonce);
            emit StateCorruptionAttempt("nonce-manipulation", false, reason);
        }
    }

    // Attack 4: Ownership corruption via delegate call
    function attemptOwnershipCorruption() external {
        address originalOwner = targetEscrow.owner();

        try targetEscrow.execute(
            address(this),
            0,
            abi.encodeWithSignature("maliciousOwnershipChange(address)", address(this))
        ) {
            address newOwner = targetEscrow.owner();
            emit OwnershipCorruption(originalOwner, newOwner);
            emit StateCorruptionAttempt("ownership-corruption", newOwner == address(this), "");
        } catch (bytes memory reason) {
            emit StateCorruptionAttempt("ownership-corruption", false, reason);
        }
    }

    // Attack 5: Storage slot collision attack
    function attemptStorageCollision() external {
        // Try to manipulate storage via carefully crafted calls
        try targetEscrow.execute(
            address(this),
            0,
            abi.encodeWithSignature("storageManipulation(uint256,uint256)", 0, 0x123456789abcdef)
        ) {
            emit StateCorruptionAttempt("storage-collision", true, "");
        } catch (bytes memory reason) {
            emit StateCorruptionAttempt("storage-collision", false, reason);
        }
    }

    // Attack 6: Emergency system state corruption
    function attemptEmergencyStateCorruption() external {
        try targetFactory.setGlobalEmergency(true) {
            // If this succeeds, try to corrupt the emergency state
            try this.corruptEmergencyState() {
                emit StateCorruptionAttempt("emergency-corruption", true, "");
            } catch (bytes memory reason) {
                emit StateCorruptionAttempt("emergency-corruption", false, reason);
            }
        } catch (bytes memory reason) {
            emit StateCorruptionAttempt("emergency-corruption", false, reason);
        }
    }

    // Attack 7: Cross-function state corruption
    function attemptCrossFunctionCorruption() external {
        // Try to exploit state changes between different function calls
        try targetEscrow.pause() {
            // While paused, try to execute operations that should be blocked
            try targetEscrow.execute(address(this), 0, abi.encodeWithSignature("maliciousCallback()")) {
                emit StateCorruptionAttempt("cross-function", true, "");
            } catch {
                emit StateCorruptionAttempt("cross-function", false, "operation blocked correctly");
            }
        } catch (bytes memory reason) {
            emit StateCorruptionAttempt("cross-function", false, reason);
        }
    }

    // Attack 8: Atomic transaction failure exploitation
    function attemptAtomicFailureExploit() external {
        bytes32 operationId = keccak256(abi.encode(block.timestamp, msg.sender));

        require(!executedOperations[operationId], "Operation already executed");
        executedOperations[operationId] = true;

        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory datas = new bytes[](3);

        // Setup operations that should all succeed or all fail
        targets[0] = address(this);
        targets[1] = address(this);
        targets[2] = address(this);

        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        datas[0] = abi.encodeWithSignature("successfulOperation()");
        datas[1] = abi.encodeWithSignature("successfulOperation()");
        datas[2] = abi.encodeWithSignature("failingOperation()"); // This should cause revert

        try targetEscrow.multicall(targets, values, datas) {
            // Should not reach here due to failing operation
            emit StateCorruptionAttempt("atomic-failure", false, "transaction should have failed");
        } catch (bytes memory reason) {
            // Check if state was properly reverted
            bool stateReverted = !executedOperations[operationId];
            emit StateCorruptionAttempt("atomic-failure", !stateReverted, reason);
        }
    }

    // Malicious callback functions
    function maliciousCallback() external {
        // Try to re-enter or manipulate state
        if (msg.sender == address(targetEscrow)) {
            // We're being called from the escrow - try to manipulate its state
            try targetEscrow.addApprover(address(this)) {
                // Successful state manipulation
            } catch {
                // Failed to manipulate state
            }
        }
    }

    function revertAfterNonceChange() external pure {
        // This function always reverts, used to test nonce handling
        revert("Intentional revert after nonce change");
    }

    function maliciousOwnershipChange(address newOwner) external {
        // Try to change ownership (should fail due to proper access control)
        try targetEscrow.addApprover(newOwner) {
            // If this succeeds, the access control might be broken
        } catch {
            // Proper access control
        }
    }

    function storageManipulation(uint256 slot, uint256 value) external {
        // Try to manipulate storage directly (should not work in properly designed contracts)
        assembly {
            sstore(slot, value)
        }
    }

    function corruptEmergencyState() external {
        // Try to corrupt emergency state
        try targetFactory.pauseFunction(bytes4(0x12345678), false) {
            // Successful manipulation
        } catch {
            // Failed to manipulate
        }
    }

    function successfulOperation() external pure returns (bool) {
        return true;
    }

    function failingOperation() external pure {
        revert("Intentional failure for atomic test");
    }

    // Gas exhaustion attack
    function attemptGasExhaustionAttack() external {
        uint256[] memory largeArray = new uint256[](10000);

        for (uint256 i = 0; i < 10000; i++) {
            largeArray[i] = i;
        }

        try targetEscrow.execute(
            address(this),
            0,
            abi.encodeWithSignature("gasExhaustionCallback(uint256[])", largeArray)
        ) {
            emit StateCorruptionAttempt("gas-exhaustion", true, "");
        } catch (bytes memory reason) {
            emit StateCorruptionAttempt("gas-exhaustion", false, reason);
        }
    }

    function gasExhaustionCallback(uint256[] memory data) external pure {
        // Consume a lot of gas
        uint256 sum = 0;
        for (uint256 i = 0; i < data.length; i++) {
            sum += data[i] * data[i];
        }
    }

    // Fallback functions
    receive() external payable {}
    fallback() external payable {}
}

/**
 * @title StateObserver
 * @dev Helper contract untuk monitoring state changes
 */
contract StateObserver {
    struct StateSnapshot {
        address owner;
        uint256 nonce;
        bool paused;
        uint256 balance;
        uint256 timestamp;
    }

    mapping(address => StateSnapshot[]) public snapshots;

    function takeSnapshot(address escrow) external {
        IUserEscrow target = IUserEscrow(escrow);

        StateSnapshot memory snapshot = StateSnapshot({
            owner: target.owner(),
            nonce: target.nonce(),
            paused: false, // Would need to check pause status
            balance: escrow.balance,
            timestamp: block.timestamp
        });

        snapshots[escrow].push(snapshot);
    }

    function getSnapshotCount(address escrow) external view returns (uint256) {
        return snapshots[escrow].length;
    }

    function compareSnapshots(address escrow, uint256 index1, uint256 index2)
        external
        view
        returns (bool ownerChanged, bool nonceChanged, bool pauseChanged, bool balanceChanged)
    {
        require(index1 < snapshots[escrow].length && index2 < snapshots[escrow].length, "Invalid indices");

        StateSnapshot memory s1 = snapshots[escrow][index1];
        StateSnapshot memory s2 = snapshots[escrow][index2];

        ownerChanged = s1.owner != s2.owner;
        nonceChanged = s1.nonce != s2.nonce;
        pauseChanged = s1.paused != s2.paused;
        balanceChanged = s1.balance != s2.balance;
    }
}