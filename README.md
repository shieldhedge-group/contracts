# SolHedge Smart Contracts

## Overview

SolHedge is a secure DeFi escrow system built on Solidity ^0.8.30, deployed on Base network (mainnet and testnet). The system features multi-signature functionality, TVL aggregation, automated bot execution, and upgradeable contract architecture for DeFi portfolio management.

## Architecture

### Contract Structure

```
contracts/
├── contracts/               # Core non-upgradeable contracts
│   ├── EscrowFactory.sol           # Factory for creating UserEscrow instances
│   ├── UserEscrow.sol              # Individual escrow with multi-sig
│   ├── EscrowManager.sol           # TVL aggregation & batch operations
│   ├── EscrowRegistry.sol          # Central escrow registry
│   ├── WhitelistManager.sol        # Whitelist security management
│   ├── BatchDeployer.sol           # Batch deployment utilities
│   ├── NFTUnstakeHelper.sol        # NFT unstaking helper
│   └── interfaces/                 # Contract interfaces
│       ├── IEscrowFactory.sol
│       ├── IEscrowRegistry.sol
│       └── IWhitelistManager.sol
│
└── upgradeable/contracts/   # Upgradeable contract architecture
    ├── EscrowFactoryUpgradeable.sol      # Upgradeable factory
    ├── UserEscrowUpgradeable.sol         # Upgradeable escrow
    ├── EscrowManagerUpgradeable.sol      # Upgradeable manager
    ├── EscrowRegistry.sol                # Registry for upgradeable escrows
    ├── EscrowRegistryExtension.sol       # Registry extensions
    ├── TVLAggregator.sol                 # TVL aggregation logic
    ├── TimelockProxyAdmin.sol            # Timelock for upgrades
    └── WhitelistManager.sol              # Whitelist for upgradeable
```

---

## Core Contracts (Non-Upgradeable)

### 1. EscrowFactory.sol

**Purpose**: Factory contract for creating and managing UserEscrow instances.

**Key Features**:
- One escrow per user per pool address
- Automatically assigns bot address to all created escrows
- Global whitelist management through WhitelistManager
- Global emergency pause capability
- Dev/Live mode switching for deposit controls

**Constructor Parameters**:
```solidity
constructor(
    uint256 _ownershipDelay,    // Time delay for ownership transfers
    address _escrowRegistry,    // Registry contract address
    address _whitelistManager,  // Whitelist manager address
    address _botAddress         // Default bot for emergency pause
)
```

**Key Functions**:
- `createEscrow(address user, address[] approvers, uint256 threshold)` - Create basic escrow
- `createEscrowWithPool(address user, address pool, address[] approvers, uint256 threshold)` - Create escrow for specific pool
- `updateBotAddress(address newBot)` - Update default bot address
- `setLiveMode(bool isLive)` - Toggle live/dev mode

---

### 2. UserEscrow.sol

**Purpose**: Individual gas-optimized escrow contract with multi-signature capabilities and enhanced security.

**Key Features**:
- Multi-signature execution with threshold requirements
- Time-delayed ownership transfers
- Pausable operations (by owner or bot)
- ETH and ERC20 token support
- NFT support (IERC721Receiver)
- TVL tracking and reporting
- Chain ID-based replay protection
- Multicall support for batched operations

**Storage Variables**:
```solidity
address public owner;
address public pendingOwner;
uint256 public pendingOwnerAvailableAt;
uint256 public immutable ownershipDelay;
IEscrowFactory public factory;
IWhitelistManager public whitelistManager;
address public immutable poolAddress;
```

**Security Features**:
- ReentrancyGuard for all state-changing functions
- Signature-based execution with nonce tracking
- Whitelist validation for external calls
- Emergency pause capability

**Key Functions**:
- `depositETH()` - Deposit ETH to escrow
- `depositToken(address token, uint256 amount)` - Deposit ERC20 tokens
- `withdrawETH(uint256 amount)` - Withdraw ETH (owner only)
- `withdrawToken(address token, uint256 amount)` - Withdraw tokens (owner only)
- `execute(address target, uint256 value, bytes data)` - Execute whitelisted call
- `executeMulticall(Call[] calls)` - Execute multiple calls atomically
- `executeWithSignatures(...)` - Multi-sig execution with off-chain signatures

---

### 3. EscrowManager.sol

**Purpose**: TVL aggregation and batch operation coordinator for multiple escrows.

**Key Features**:
- TVL aggregation across multiple escrows
- Bot authorization system with user permissions
- Batch execution for multiple escrows
- Value limits for bot operations
- Replay attack prevention

**Bot System (Two-Layer)**:
```solidity
mapping(address => bool) public authorizedBots;              // Factory-authorized bots
mapping(address => mapping(address => bool)) public userBotPermissions; // User permissions
mapping(address => uint256) public botNonces;                // Replay protection
uint256 public maxBotValue = 1 ether;                        // Max value per tx
```

**Key Functions**:
- `triggerEscrow(address escrow, address target, uint256 value, bytes data)` - Single escrow trigger
- `batchTriggerEscrows(...)` - Batch trigger multiple escrows
- `botTriggerEscrowWithSignatures(...)` - Bot execution with user signatures
- `authorizeBots(address[] bots, bool[] authorized)` - Authorize bots (owner only)
- `grantBotPermission(address bot, bool granted)` - User grants bot permission
- `aggregateTVL(...)` - Calculate total value locked across escrows

---

### 4. EscrowRegistry.sol

**Purpose**: Central registry for tracking all created escrows.

**Key Features**:
- Maps users to their escrows per pool
- Tracks all created escrows
- Factory-controlled registration
- Query functions for escrow discovery

---

### 5. WhitelistManager.sol

**Purpose**: Centralized whitelist management for security.

**Key Features**:
- Controls which target addresses escrows can interact with
- Managed by factory owner
- Prevents unauthorized external calls
- Supports batch whitelist operations

---

### 6. Supporting Contracts

**BatchDeployer.sol**: Utilities for batch deployment operations.

**NFTUnstakeHelper.sol**: Helper contract for safely unstaking NFTs from gauges.

**MockERC20.sol / TestERC20.sol**: Test token contracts for development.

**IWETH.sol**: WETH interface for ETH wrapping/unwrapping.

---

## Upgradeable Contracts

### Architecture Pattern

The upgradeable system uses **TransparentUpgradeableProxy** pattern from OpenZeppelin:
- Implementation contracts hold logic
- Proxy contracts hold state and user balances
- ProxyAdmin controls upgrade permissions
- Timelock for governance-controlled upgrades

### Key Upgradeable Contracts

#### 1. EscrowFactoryUpgradeable.sol

Similar to EscrowFactory but creates escrows as TransparentUpgradeableProxy instances.

**Additional Features**:
- Centralized implementation management
- Upgradeable escrow logic without user migration
- Governance-controlled upgrades via ProxyAdmin

**Key State Variables**:
```solidity
address public escrowImplementation;  // Current implementation
ProxyAdmin public proxyAdmin;         // Upgrade controller
```

---

#### 2. UserEscrowUpgradeable.sol

Upgradeable version of UserEscrow with initialization instead of constructor.

**Versions**:
- `UserEscrowUpgradeable.sol` - Main upgradeable implementation
- `UserEscrowUpgradeableV1.sol` - Version 1 (legacy)
- `UserEscrowUpgradeableV2.sol` - Version 2 (current)

**Initialization**:
```solidity
function initialize(
    address _owner,
    address _factory,
    address _whitelistManager,
    address _poolAddress,
    address[] memory _approvers,
    uint256 _threshold,
    uint256 _ownershipDelay
) public initializer
```

---

#### 3. EscrowManagerUpgradeable.sol

Upgradeable version of EscrowManager for batch operations.

---

#### 4. TVLAggregator.sol

Dedicated contract for aggregating Total Value Locked across escrows.

---

#### 5. TimelockProxyAdmin.sol

ProxyAdmin with timelock functionality for secure upgrade governance.

**Features**:
- Delayed upgrade execution
- Cancellable upgrade proposals
- Multi-sig support for governance

---

## Security Architecture

### Multi-Signature System

UserEscrow supports threshold-based multi-signature execution:
- Approvers set at escrow creation
- Signatures collected off-chain
- On-chain verification via `executeWithSignatures()`
- Message hash includes: escrow address, chain ID, target, value, data, nonce
- Chain ID prevents cross-chain replay attacks
- Nonce prevents same-chain replay attacks

**Signature Flow**:
```
1. Approvers sign message off-chain
2. Collect signatures
3. Call executeWithSignatures() with all signatures
4. Contract verifies signatures and executes
```

---

### Bot System (Two Layers)

#### Layer 1: Factory Bot (Emergency Control)
- **Purpose**: Emergency circuit breaker only
- **Capabilities**: Can pause/unpause individual escrows
- **Restrictions**: Cannot execute transactions, withdraw funds, or modify governance
- **Set at**: Escrow deployment via factory

#### Layer 2: Manager Bots (Batch Operations)
- **Purpose**: Execute batch transactions on behalf of users
- **Requirements**:
  - Bot must be authorized by factory owner
  - User must grant permission to bot
  - User signatures required for all operations
- **Limits**: Maximum ETH value per transaction (default 1 ETH)
- **Flow**: `Admin authorizes → User grants permission → User signs → Bot executes with signatures`

---

### Whitelist System

All external calls from escrows must target whitelisted addresses:
- Managed centrally through WhitelistManager
- Factory owner controls whitelist
- Typical whitelisted targets: DEX routers, LP pools, token contracts
- Prevents malicious external calls

---

### Circuit Breaker

Multi-level emergency pause system:
- **Global Emergency Pause**: Factory-level pause for all escrows
- **Individual Pause**: Owner or bot can pause specific escrow
- **Emergency Admin Role**: Limited emergency powers
- **Function-Specific Pause**: Granular control over pausable functions

---

## Design Patterns

### Factory Pattern
EscrowFactory creates UserEscrow instances with consistent initialization and bot assignment.

### Multi-Signature Pattern
Threshold-based signature verification for critical operations with replay protection.

### Registry Pattern
EscrowRegistry tracks all created escrows for discovery and aggregation.

### Whitelist Security
All external interactions require whitelisted targets for security.

### TVL Aggregation
EscrowManager aggregates Total Value Locked across multiple escrows efficiently.

### Proxy Pattern (Upgradeable)
TransparentUpgradeableProxy enables logic upgrades without state migration.

---

## Network Configuration

### Supported Networks

| Network | Chain ID | Purpose |
|---------|----------|---------|
| Base Mainnet | 8453 | Production deployment |
| Base Sepolia | 84532 | Testnet deployment |
| Anvil Fork | 31338 | Local development (Base fork) |
| Hardhat Local | 31337 | Local testing |

### Network Addresses

**Base Mainnet USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

---

## Development

### Compilation
```bash
npm run compile          # Compile contracts
npm run clean           # Clean artifacts
```

### Testing
```bash
npm test                # Run all tests
npm run test:coverage   # Run with coverage
npm run test:anvil      # Test with Anvil Base fork
```

### Deployment
```bash
npm run deploy:base              # Deploy to Base mainnet
npm run deploy:base-sepolia      # Deploy to Base Sepolia
npm run deploy:localhost         # Deploy to Hardhat localhost
npm run deploy:anvil            # Deploy to Anvil fork
```

### Verification
```bash
npm run verify:base              # Verify on Base mainnet
npm run verify:base-sepolia      # Verify on Base Sepolia
```

---

## Key Security Considerations

### When Modifying Contracts

1. **Reentrancy**: All state-changing functions must use `nonReentrant` modifier
2. **Signature Validation**: Always include chain ID and nonce in signed messages
3. **Whitelist Checks**: External calls must check `whitelistManager.isWhitelistedWithCaller()`
4. **Zero Address**: Validate all address parameters against zero address
5. **SafeERC20**: Use `SafeERC20` for all token operations
6. **Access Control**: Properly use `onlyOwner`, `onlyBot`, and other modifiers

### Testing Security Changes

After modifying security-critical code, always run:
```bash
npx hardhat test test/HackerAttackVectors.test.js
npx hardhat test test/CircuitBreaker.test.js
npx hardhat test test/CompleteDeFiFlow.test.js
```

---

## Dependencies

- Hardhat ^2.19.0
- OpenZeppelin Contracts ^4.9.0
- Solidity ^0.8.30
- Foundry (for Anvil)

### Key OpenZeppelin Imports
- `ReentrancyGuard` - Reentrancy protection
- `Pausable` - Emergency pause functionality
- `SafeERC20` - Safe token operations
- `ECDSA` - Signature verification
- `Ownable` - Access control
- `TransparentUpgradeableProxy` - Upgradeable pattern
- `ProxyAdmin` - Upgrade governance

---

## Contract Interactions

### Creating an Escrow

```solidity
// 1. Deploy factory with dependencies
EscrowFactory factory = new EscrowFactory(
    ownershipDelay,
    escrowRegistry,
    whitelistManager,
    botAddress
);

// 2. Create escrow for user
address[] memory approvers = [addr1, addr2, addr3];
factory.createEscrow(userAddress, approvers, 2); // 2-of-3 multisig
```

### Executing with Multi-Sig

```solidity
// 1. Prepare call data
bytes memory data = abi.encodeWithSignature("swap(uint256)", amount);

// 2. Create message hash
bytes32 messageHash = keccak256(abi.encodePacked(
    address(escrow),
    block.chainid,
    target,
    value,
    keccak256(data),
    nonce
));

// 3. Collect signatures off-chain from approvers
// 4. Execute with signatures
escrow.executeWithSignatures(target, value, data, signatures);
```

### Bot Execution Flow

```solidity
// 1. Owner authorizes bot
manager.authorizeBots([botAddress], [true]);

// 2. User grants permission
manager.grantBotPermission(botAddress, true);

// 3. User signs transaction off-chain
// 4. Bot executes with user signature
manager.botTriggerEscrowWithSignatures(
    escrow,
    target,
    value,
    data,
    signatures
);
```

---

## Gas Optimization

The contracts are optimized for gas efficiency:
- Compiler optimizer enabled with 1000 runs
- `viaIR` enabled for additional optimization
- Immutable variables where possible
- Efficient storage packing
- Batch operations to reduce transaction count

**Solidity Settings**:
```javascript
solidity: {
  version: "0.8.30",
  settings: {
    optimizer: {
      enabled: true,
      runs: 1000,
    },
    viaIR: true,
  },
}
```

---

## License

MIT License

---

## Additional Resources

- **Deployment Addresses**: See `deployments/` directory
- **Bot Security Model**: See `docs/BOT_SECURITY_MODEL.md`
- **Latest Deployment**: See `DEPLOYMENT_SUMMARY.md`
- **Contract ABIs**: Generated in `artifacts/` after compilation

---

## Support

For issues and feature requests, please contact the SolHedge development team.
