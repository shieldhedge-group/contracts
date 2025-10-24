const { ethers } = require('hardhat');

async function main() {
    const [deployer, user1, user2] = await ethers.getSigners();
    
    console.log("\n=== SETUP ===");
    console.log("deployer:", deployer.address);
    console.log("user1:", user1.address);
    console.log("user2:", user2.address);
    
    // Deploy contracts
    console.log("\n=== DEPLOYING CONTRACTS ===");
    const EscrowRegistry = await ethers.getContractFactory("EscrowRegistry");
    const registry = await EscrowRegistry.deploy();
    await registry.waitForDeployment();
    console.log("Registry deployed:", await registry.getAddress());
    
    const WhitelistManager = await ethers.getContractFactory("WhitelistManager");
    const whitelist = await WhitelistManager.deploy(await registry.getAddress());
    await whitelist.waitForDeployment();
    console.log("Whitelist deployed:", await whitelist.getAddress());
    
    const EscrowFactory = await ethers.getContractFactory("EscrowFactory");
    const factory = await EscrowFactory.deploy(
        604800,
        await registry.getAddress(),
        await whitelist.getAddress(),
        deployer.address
    );
    await factory.waitForDeployment();
    console.log("Factory deployed:", await factory.getAddress());
    
    await registry.setAuthorizedFactory(await factory.getAddress(), true);
    console.log("Factory authorized");
    
    // Check initial state
    console.log("\n=== INITIAL STATE ===");
    console.log("Factory.isHasLive():", await factory.isHasLive());
    
    // Whitelist user1 only
    await whitelist.setWhitelist(user1.address, true);
    console.log("user1 whitelisted:", await whitelist.isWhitelisted(user1.address));
    console.log("user2 whitelisted:", await whitelist.isWhitelisted(user2.address));
    
    // Create escrow
    console.log("\n=== CREATING ESCROW ===");
    const poolAddr = ethers.Wallet.createRandom().address;
    const createTx = await factory.connect(user1).createEscrow(
        poolAddr,
        [user1.address],
        1,
        10
    );
    const receipt = await createTx.wait();
    
    // Find escrow address from events
    let escrowAddr;
    for (const log of receipt.logs) {
        try {
            const parsed = factory.interface.parseLog(log);
            if (parsed && parsed.name === 'EscrowCreatedForPool') {
                escrowAddr = parsed.args[2]; // Third argument is escrow address
                break;
            }
        } catch (e) {
            // Skip logs that can't be parsed
        }
    }
    
    if (!escrowAddr) {
        console.error("ERROR: Could not find escrow address in events");
        return;
    }
    
    console.log("Escrow created:", escrowAddr);
    const escrow = await ethers.getContractAt("UserEscrow", escrowAddr);
    
    // Check escrow state
    console.log("\n=== ESCROW STATE ===");
    try {
        const owner = await escrow.owner();
        console.log("Escrow owner:", owner);
    } catch (e) {
        console.log("ERROR reading owner:", e.message.split('\n')[0]);
    }
    
    try {
        const factoryAddr = await escrow.factory();
        console.log("Escrow factory:", factoryAddr);
        console.log("Factory match:", factoryAddr === await factory.getAddress());
        
        // Try to call isHasLive through the factory reference
        if (factoryAddr && factoryAddr !== ethers.ZeroAddress) {
            const factoryFromEscrow = await ethers.getContractAt("IEscrowFactory", factoryAddr);
            const isLive = await factoryFromEscrow.isHasLive();
            console.log("Factory.isHasLive() from escrow:", isLive);
        }
    } catch (e) {
        console.log("ERROR reading factory:", e.message.split('\n')[0]);
    }
    
    try {
        const whitelistAddr = await escrow.whitelistManager();
        console.log("Escrow whitelist:", whitelistAddr);
        console.log("Whitelist match:", whitelistAddr === await whitelist.getAddress());
    } catch (e) {
        console.log("ERROR reading whitelistManager:", e.message.split('\n')[0]);
    }
    
    // Test deposit from user1 (whitelisted)
    console.log("\n=== TEST 1: Whitelisted User Deposit ===");
    try {
        const tx = await user1.sendTransaction({
            to: escrowAddr,
            value: ethers.parseEther("1.0")
        });
        await tx.wait();
        const balance = await ethers.provider.getBalance(escrowAddr);
        console.log("✅ user1 (whitelisted) deposit SUCCESS");
        console.log("   Escrow balance:", ethers.formatEther(balance), "ETH");
    } catch (e) {
        console.log("❌ user1 deposit FAILED:", e.message.split('\n')[0]);
    }
    
    // Test deposit from user2 (NOT whitelisted) - should FAIL
    console.log("\n=== TEST 2: Non-whitelisted User Deposit (should REJECT) ===");
    try {
        const tx = await user2.sendTransaction({
            to: escrowAddr,
            value: ethers.parseEther("1.0"),
            gasLimit: 100000
        });
        await tx.wait();
        const balance = await ethers.provider.getBalance(escrowAddr);
        console.log("❌ ERROR: user2 (NOT whitelisted) deposit SUCCESS - SHOULD HAVE BEEN REJECTED!");
        console.log("   Escrow balance:", ethers.formatEther(balance), "ETH");
    } catch (e) {
        const errorMsg = e.message;
        if (errorMsg.includes("dev mode: depositor not whitelisted")) {
            console.log("✅ user2 deposit correctly REJECTED");
            console.log("   Error:", "dev mode: depositor not whitelisted");
        } else {
            console.log("⚠️  user2 deposit FAILED but with wrong error:");
            console.log("   Error:", errorMsg.split('\n')[0]);
        }
    }
    
    // Switch to Live Mode
    console.log("\n=== SWITCHING TO LIVE MODE ===");
    await factory.connect(deployer).setLiveMode(true);
    console.log("Factory.isHasLive():", await factory.isHasLive());
    
    // Test deposit from user2 again (should now WORK)
    console.log("\n=== TEST 3: Non-whitelisted User Deposit in Live Mode (should WORK) ===");
    try {
        const tx = await user2.sendTransaction({
            to: escrowAddr,
            value: ethers.parseEther("2.0")
        });
        await tx.wait();
        const balance = await ethers.provider.getBalance(escrowAddr);
        console.log("✅ user2 deposit SUCCESS in Live Mode");
        console.log("   Escrow balance:", ethers.formatEther(balance), "ETH");
    } catch (e) {
        console.log("❌ user2 deposit FAILED in Live Mode:", e.message.split('\n')[0]);
    }
}

main().catch(console.error);
