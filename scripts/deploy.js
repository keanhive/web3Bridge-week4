const hre = require("hardhat");

async function main() {
    console.log("Deploying SavingsVault...");

    const SavingsVault = await hre.ethers.getContractFactory("SavingsVault");
    const savingsVault = await SavingsVault.deploy();
    await savingsVault.waitForDeployment();

    const vaultAddress = await savingsVault.getAddress();
    console.log("SavingsVault deployed to:", vaultAddress);

    const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
    const mockToken = await MockERC20.deploy("Test Token", "TST", 18);
    await mockToken.waitForDeployment();

    console.log("MockERC20 deployed to:", await mockToken.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });