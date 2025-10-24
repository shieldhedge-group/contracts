// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IUserEscrow {
    function executeWithSignatures(
        address target,
        uint256 value,
        bytes calldata data,
        bytes[] calldata signatures,
        uint256 deadline
    ) external payable;
    function nonce() external view returns (uint256);
    function threshold() external view returns (uint256);
    function isApproverMap(address) external view returns (bool);
}

/**
 * @title SignatureForger
 * @dev Contract untuk testing berbagai signature attacks
 */
contract SignatureForger {
    using ECDSA for bytes32;

    IUserEscrow public target;

    struct StoredSignature {
        address target;
        uint256 value;
        bytes data;
        bytes[] signatures;
        uint256 deadline;
        uint256 nonce;
        uint256 chainId;
    }

    mapping(bytes32 => StoredSignature) public storedSignatures;
    mapping(address => uint256) public privateKeys; // For testing only - NEVER store real private keys!

    event SignatureForged(bytes32 indexed hash, bool success);
    event ReplayAttempt(bytes32 indexed originalHash, bytes32 indexed replayHash);
    event MalleabilityAttempt(bytes32 indexed originalHash, bytes32 indexed malleatedHash);

    constructor() {
        // Test private keys (DO NOT USE IN PRODUCTION!)
        privateKeys[0x70997970C51812dc3A010C7d01b50e0d17dc79C8] = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        privateKeys[0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC] = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    }

    function setTarget(address _target) external {
        target = IUserEscrow(_target);
    }

    function storeValidSignature(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes[] calldata _signatures,
        uint256 _deadline
    ) external {
        bytes32 hash = keccak256(abi.encode(_target, _value, _data, _signatures, _deadline));

        storedSignatures[hash] = StoredSignature({
            target: _target,
            value: _value,
            data: _data,
            signatures: _signatures,
            deadline: _deadline,
            nonce: target.nonce(),
            chainId: block.chainid
        });
    }

    // Attack 1: Signature Replay dengan nonce lama
    function attemptSignatureReplay(bytes32 originalHash) external {
        StoredSignature memory stored = storedSignatures[originalHash];

        bytes32 replayHash = keccak256(abi.encode(stored.target, stored.value, stored.data, block.timestamp));
        emit ReplayAttempt(originalHash, replayHash);

        try target.executeWithSignatures(
            stored.target,
            stored.value,
            stored.data,
            stored.signatures,
            stored.deadline
        ) {
            emit SignatureForged(replayHash, true);
        } catch {
            emit SignatureForged(replayHash, false);
        }
    }

    // Attack 2: Cross-chain signature replay
    function attemptCrossChainReplay(bytes32 originalHash, uint256 targetChainId) external {
        StoredSignature memory stored = storedSignatures[originalHash];

        // Forge signatures for different chain
        bytes[] memory forgedSignatures = new bytes[](stored.signatures.length);

        for (uint256 i = 0; i < stored.signatures.length; i++) {
            // Create message hash for different chain
            bytes32 rawHash = keccak256(
                abi.encode(
                    address(target),
                    targetChainId, // Different chain ID
                    stored.target,
                    stored.value,
                    keccak256(stored.data),
                    stored.nonce,
                    stored.deadline
                )
            );
            bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rawHash));

            // Try to forge signature (this should fail in real scenario)
            forgedSignatures[i] = stored.signatures[i]; // Copy original signature
        }

        try target.executeWithSignatures(
            stored.target,
            stored.value,
            stored.data,
            forgedSignatures,
            stored.deadline + 1 hours // Extended deadline
        ) {
            emit SignatureForged(keccak256(abi.encode("cross-chain", targetChainId)), true);
        } catch {
            emit SignatureForged(keccak256(abi.encode("cross-chain", targetChainId)), false);
        }
    }

    // Attack 3: Signature Malleability
    function attemptSignatureMalleability(bytes32 originalHash) external {
        StoredSignature memory stored = storedSignatures[originalHash];

        bytes[] memory malleatedSignatures = new bytes[](stored.signatures.length);

        for (uint256 i = 0; i < stored.signatures.length; i++) {
            malleatedSignatures[i] = malleateSignature(stored.signatures[i]);
        }

        bytes32 malleatedHash = keccak256(abi.encode("malleated", malleatedSignatures));
        emit MalleabilityAttempt(originalHash, malleatedHash);

        try target.executeWithSignatures(
            stored.target,
            stored.value,
            stored.data,
            malleatedSignatures,
            stored.deadline
        ) {
            emit SignatureForged(malleatedHash, true);
        } catch {
            emit SignatureForged(malleatedHash, false);
        }
    }

    // Attack 4: Threshold bypass dengan invalid signatures
    function attemptThresholdBypass(address _target, uint256 _value, bytes calldata _data) external {
        uint256 threshold = target.threshold();

        // Create more signatures than threshold but all invalid
        bytes[] memory invalidSignatures = new bytes[](threshold + 1);

        for (uint256 i = 0; i < threshold + 1; i++) {
            // Create completely invalid signature
            invalidSignatures[i] = abi.encodePacked(
                bytes32(uint256(i + 1)), // r
                bytes32(uint256(i + 2)), // s
                uint8(27 + (i % 2))      // v
            );
        }

        try target.executeWithSignatures(
            _target,
            _value,
            _data,
            invalidSignatures,
            block.timestamp + 1 hours
        ) {
            emit SignatureForged(keccak256("threshold-bypass"), true);
        } catch {
            emit SignatureForged(keccak256("threshold-bypass"), false);
        }
    }

    // Attack 5: Duplicate signer attack
    function attemptDuplicateSignerAttack(
        address _target,
        uint256 _value,
        bytes calldata _data,
        address validSigner
    ) external {
        // Create message hash
        bytes32 rawHash = keccak256(
            abi.encode(
                address(target),
                block.chainid,
                _target,
                _value,
                keccak256(_data),
                target.nonce(),
                block.timestamp + 1 hours
            )
        );
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rawHash));

        // Create signature from valid signer (if we have the private key)
        uint256 privateKey = privateKeys[validSigner];
        require(privateKey != 0, "No private key for signer");

        (uint8 v, bytes32 r, bytes32 s) = vm_sign(privateKey, messageHash);
        bytes memory validSignature = abi.encodePacked(r, s, v);

        // Try to submit same signature multiple times
        bytes[] memory duplicateSignatures = new bytes[](target.threshold());
        for (uint256 i = 0; i < target.threshold(); i++) {
            duplicateSignatures[i] = validSignature; // Same signature repeated
        }

        try target.executeWithSignatures(
            _target,
            _value,
            _data,
            duplicateSignatures,
            block.timestamp + 1 hours
        ) {
            emit SignatureForged(keccak256("duplicate-signer"), true);
        } catch {
            emit SignatureForged(keccak256("duplicate-signer"), false);
        }
    }

    // Attack 6: Expired deadline bypass
    function attemptDeadlineBypass(bytes32 originalHash) external {
        StoredSignature memory stored = storedSignatures[originalHash];

        // Try to use signature with expired deadline
        try target.executeWithSignatures(
            stored.target,
            stored.value,
            stored.data,
            stored.signatures,
            block.timestamp - 1 // Expired deadline
        ) {
            emit SignatureForged(keccak256("deadline-bypass"), true);
        } catch {
            emit SignatureForged(keccak256("deadline-bypass"), false);
        }
    }

    // Helper function to malleate signature
    function malleateSignature(bytes memory signature) internal pure returns (bytes memory) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Malleate s value (flip high/low)
        uint256 sInt = uint256(s);
        uint256 malleatedS = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - sInt;

        // Flip v
        uint8 malleatedV = v == 27 ? 28 : 27;

        return abi.encodePacked(r, bytes32(malleatedS), malleatedV);
    }

    // Mock vm.sign for testing (replace with actual implementation)
    function vm_sign(uint256 privateKey, bytes32 digest) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // This is a simplified mock - in real testing use foundry's vm.sign
        // For now, return dummy values
        return (27, bytes32(privateKey), digest);
    }

    // Attack 7: Front-running signature submission
    function frontRunSignature(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes[] calldata _signatures,
        uint256 _deadline
    ) external {
        // Immediately submit the signature we intercepted
        try target.executeWithSignatures(_target, _value, _data, _signatures, _deadline) {
            emit SignatureForged(keccak256("front-run"), true);
        } catch {
            emit SignatureForged(keccak256("front-run"), false);
        }
    }

    // Utility functions
    function generateMessageHash(
        address escrowAddress,
        address _target,
        uint256 _value,
        bytes calldata _data,
        uint256 _nonce,
        uint256 _deadline
    ) external view returns (bytes32) {
        bytes32 rawHash = keccak256(
            abi.encode(
                escrowAddress,
                block.chainid,
                _target,
                _value,
                keccak256(_data),
                _nonce,
                _deadline
            )
        );
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", rawHash));
    }
}