import {expect} from "chai";
import {ethers} from "hardhat";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";
import {MockERC20, SavingsVault} from "../typechain-types";

describe("SavingsVault", function () {
    // Contract instances
    let savingsVault: SavingsVault;
    let mockToken: MockERC20;

    // Signers
    let owner: SignerWithAddress;
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;
    let addr: SignerWithAddress[];

    // Constants
    const TOKEN_DECIMALS = 18;
    const INITIAL_SUPPLY = ethers.parseUnits("1000000", TOKEN_DECIMALS);
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    beforeEach(async function () {
        // Get signers
        [owner, user1, user2, ...addr] = await ethers.getSigners();

        // Deploy mock ERC20 token
        const MockERC20Factory = await ethers.getContractFactory("MockERC20");
        mockToken = await MockERC20Factory.deploy("Mock Token", "MTK", TOKEN_DECIMALS);
        await mockToken.waitForDeployment();

        // Deploy SavingsVault
        const SavingsVaultFactory = await ethers.getContractFactory("SavingsVault");
        savingsVault = await SavingsVaultFactory.deploy();
        await savingsVault.waitForDeployment();

        // Transfer some tokens to user1 and user2 for testing
        await mockToken.transfer(user1.address, ethers.parseUnits("1000", TOKEN_DECIMALS));
        await mockToken.transfer(user2.address, ethers.parseUnits("1000", TOKEN_DECIMALS));
    });

    describe("Ether Functions", function () {
        it("Should deposit Ether correctly", async function () {
            const depositAmount = ethers.parseEther("1.0");

            // Deposit Ether
            await expect(savingsVault.connect(user1).depositEther({ value: depositAmount }))
                .to.emit(savingsVault, "EtherDeposited")
                .withArgs(user1.address, depositAmount);

            // Check balance
            const balance = await savingsVault.getEtherBalance(user1.address);
            expect(balance).to.equal(depositAmount);
        });

        it("Should accept Ether via receive function", async function () {
            const depositAmount = ethers.parseEther("1.0");

            // Send Ether directly to contract
            await expect(user1.sendTransaction({
                to: await savingsVault.getAddress(),
                value: depositAmount
            })).to.emit(savingsVault, "EtherDeposited")
                .withArgs(user1.address, depositAmount);

            // Check balance
            const balance = await savingsVault.getEtherBalance(user1.address);
            expect(balance).to.equal(depositAmount);
        });

        it("Should not accept zero Ether deposits", async function () {
            await expect(savingsVault.connect(user1).depositEther({ value: 0 }))
                .to.be.revertedWith("SavingsVault: deposit amount must be greater than 0");
        });

        it("Should withdraw Ether correctly", async function () {
            const depositAmount = ethers.parseEther("1.0");
            const withdrawAmount = ethers.parseEther("0.5");

            // First deposit
            await savingsVault.connect(user1).depositEther({ value: depositAmount });

            // Get initial balance for comparison
            const initialBalance = await ethers.provider.getBalance(user1.address);

            // Withdraw
            const tx = await savingsVault.connect(user1).withdrawEther(withdrawAmount);
            const receipt = await tx.wait();

            if (!receipt) throw new Error("Transaction failed");

            // Calculate gas cost
            const gasCost = receipt.gasUsed * receipt.gasPrice;

            // Check vault balance decreased
            const vaultBalance = await savingsVault.getEtherBalance(user1.address);
            expect(vaultBalance).to.equal(depositAmount - withdrawAmount);

            // Check user received Ether (balance increased, accounting for gas)
            const finalBalance = await ethers.provider.getBalance(user1.address);
            expect(finalBalance + gasCost).to.be.gt(initialBalance);
        });

        it("Should not withdraw more than deposited", async function () {
            const depositAmount = ethers.parseEther("1.0");

            await savingsVault.connect(user1).depositEther({ value: depositAmount });

            await expect(savingsVault.connect(user1).withdrawEther(ethers.parseEther("2.0")))
                .to.be.revertedWith("SavingsVault: insufficient Ether balance");
        });
    });

    describe("ERC20 Functions", function () {
        const depositAmount = ethers.parseUnits("100", TOKEN_DECIMALS);

        beforeEach(async function () {
            // Approve savingsVault to spend user1's tokens
            await mockToken.connect(user1).approve(await savingsVault.getAddress(), depositAmount);
        });

        it("Should deposit ERC20 tokens correctly", async function () {
            const vaultAddress = await savingsVault.getAddress();
            const tokenAddress = await mockToken.getAddress();

            // Get initial balances
            const initialUserBalance = await mockToken.balanceOf(user1.address);
            const initialVaultBalance = await mockToken.balanceOf(vaultAddress);

            // Deposit
            await expect(savingsVault.connect(user1).depositERC20(tokenAddress, depositAmount))
                .to.emit(savingsVault, "ERC20Deposited")
                .withArgs(user1.address, tokenAddress, depositAmount);

            // Check balances after deposit
            const finalUserBalance = await mockToken.balanceOf(user1.address);
            const finalVaultBalance = await mockToken.balanceOf(vaultAddress);

            expect(finalUserBalance).to.equal(initialUserBalance - depositAmount);
            expect(finalVaultBalance).to.equal(initialVaultBalance + depositAmount);

            // Check vault's internal balance tracking
            const vaultBalance = await savingsVault.getERC20Balance(user1.address, tokenAddress);
            expect(vaultBalance).to.equal(depositAmount);
        });

        it("Should track user tokens correctly", async function () {
            const tokenAddress = await mockToken.getAddress();

            await savingsVault.connect(user1).depositERC20(tokenAddress, depositAmount);

            const userTokens = await savingsVault.getUserTokens(user1.address);
            expect(userTokens.length).to.equal(1);
            expect(userTokens[0]).to.equal(tokenAddress);
        });

        it("Should withdraw ERC20 tokens correctly", async function () {
            const tokenAddress = await mockToken.getAddress();
            const vaultAddress = await savingsVault.getAddress();

            // First deposit
            await savingsVault.connect(user1).depositERC20(tokenAddress, depositAmount);

            // Get initial balances
            const initialUserBalance = await mockToken.balanceOf(user1.address);
            const withdrawAmount = depositAmount / 2n;

            // Withdraw
            await expect(savingsVault.connect(user1).withdrawERC20(tokenAddress, withdrawAmount))
                .to.emit(savingsVault, "ERC20Withdrawn")
                .withArgs(user1.address, tokenAddress, withdrawAmount);

            // Check balances after withdrawal
            const finalUserBalance = await mockToken.balanceOf(user1.address);
            const vaultBalance = await savingsVault.getERC20Balance(user1.address, tokenAddress);
            const finalVaultBalance = await mockToken.balanceOf(vaultAddress);

            expect(finalUserBalance).to.equal(initialUserBalance + withdrawAmount);
            expect(vaultBalance).to.equal(depositAmount - withdrawAmount);
            expect(finalVaultBalance).to.equal(depositAmount - withdrawAmount);
        });

        it("Should not withdraw more than deposited", async function () {
            const tokenAddress = await mockToken.getAddress();

            await savingsVault.connect(user1).depositERC20(tokenAddress, depositAmount);

            const tooMuch = depositAmount + 1n;
            await expect(savingsVault.connect(user1).withdrawERC20(tokenAddress, tooMuch))
                .to.be.revertedWith("SavingsVault: insufficient token balance");
        });

        it("Should not deposit without approval", async function () {
            const tokenAddress = await mockToken.getAddress();

            // user2 hasn't approved
            await expect(savingsVault.connect(user2).depositERC20(tokenAddress, depositAmount))
                .to.be.reverted;
        });

        it("Should handle zero address checks", async function () {
            await expect(savingsVault.connect(user1).depositERC20(ZERO_ADDRESS, depositAmount))
                .to.be.revertedWith("SavingsVault: invalid token address");

            await expect(savingsVault.connect(user1).withdrawERC20(ZERO_ADDRESS, depositAmount))
                .to.be.revertedWith("SavingsVault: invalid token address");
        });
    });

    describe("Multiple Users and Tokens", function () {
        it("Should handle multiple users correctly", async function () {
            const depositAmount1 = ethers.parseEther("1.0");
            const depositAmount2 = ethers.parseEther("2.0");

            // Both users deposit Ether
            await savingsVault.connect(user1).depositEther({ value: depositAmount1 });
            await savingsVault.connect(user2).depositEther({ value: depositAmount2 });

            // Check balances
            expect(await savingsVault.getEtherBalance(user1.address)).to.equal(depositAmount1);
            expect(await savingsVault.getEtherBalance(user2.address)).to.equal(depositAmount2);
        });

        it("Should handle multiple tokens for same user", async function () {
            // Deploy second token
            const MockERC20Factory = await ethers.getContractFactory("MockERC20");
            const mockToken2 = await MockERC20Factory.deploy("Mock Token 2", "MTK2", 18);
            await mockToken2.waitForDeployment();

            // Transfer tokens to user1
            await mockToken2.transfer(user1.address, ethers.parseUnits("1000", 18));

            // Approve both tokens
            const depositAmount1 = ethers.parseUnits("50", 18);
            const depositAmount2 = ethers.parseUnits("30", 18);

            await mockToken.connect(user1).approve(await savingsVault.getAddress(), depositAmount1);
            await mockToken2.connect(user1).approve(await savingsVault.getAddress(), depositAmount2);

            // Deposit both tokens
            await savingsVault.connect(user1).depositERC20(await mockToken.getAddress(), depositAmount1);
            await savingsVault.connect(user1).depositERC20(await mockToken2.getAddress(), depositAmount2);

            // Check balances
            const balance1 = await savingsVault.getERC20Balance(user1.address, await mockToken.getAddress());
            const balance2 = await savingsVault.getERC20Balance(user1.address, await mockToken2.getAddress());

            expect(balance1).to.equal(depositAmount1);
            expect(balance2).to.equal(depositAmount2);

            // Check tracked tokens
            const userTokens = await savingsVault.getUserTokens(user1.address);
            expect(userTokens.length).to.equal(2);
            expect(userTokens).to.include(await mockToken.getAddress());
            expect(userTokens).to.include(await mockToken2.getAddress());
        });
    });

    describe("Utility Functions", function () {
        it("Should get user balances for multiple tokens", async function () {
            // Setup: deposit Ether and tokens
            const etherAmount = ethers.parseEther("1.0");
            const tokenAmount = ethers.parseUnits("100", TOKEN_DECIMALS);
            const tokenAddress = await mockToken.getAddress();

            await savingsVault.connect(user1).depositEther({ value: etherAmount });
            await mockToken.connect(user1).approve(await savingsVault.getAddress(), tokenAmount);
            await savingsVault.connect(user1).depositERC20(tokenAddress, tokenAmount);

            // Get all balances
            const [etherBalance, tokenBalances] = await savingsVault.getUserBalances(
                user1.address,
                [tokenAddress]
            );

            expect(etherBalance).to.equal(etherAmount);
            expect(tokenBalances[0]).to.equal(tokenAmount);
        });

        it("Should get token decimals correctly", async function () {
            const decimals = await savingsVault.getTokenDecimals(await mockToken.getAddress());
            expect(decimals).to.equal(TOKEN_DECIMALS);
        });

        it("Should revert when getting decimals for zero address", async function () {
            await expect(savingsVault.getTokenDecimals(ZERO_ADDRESS))
                .to.be.revertedWith("SavingsVault: invalid token address");
        });
    });

    describe("Edge Cases and Security", function () {
        it("Should handle zero amount withdrawals", async function () {
            await expect(savingsVault.connect(user1).withdrawEther(0))
                .to.be.revertedWith("SavingsVault: withdrawal amount must be greater than 0");

            await expect(savingsVault.connect(user1).withdrawERC20(await mockToken.getAddress(), 0))
                .to.be.revertedWith("SavingsVault: withdrawal amount must be greater than 0");
        });

        it("Should handle zero amount deposits", async function () {
            await expect(savingsVault.connect(user1).depositERC20(await mockToken.getAddress(), 0))
                .to.be.revertedWith("SavingsVault: deposit amount must be greater than 0");
        });

        it("Should maintain separate balances for different users", async function () {
            const depositAmount = ethers.parseUnits("100", TOKEN_DECIMALS);
            const tokenAddress = await mockToken.getAddress();

            // User1 deposits
            await mockToken.connect(user1).approve(await savingsVault.getAddress(), depositAmount);
            await savingsVault.connect(user1).depositERC20(tokenAddress, depositAmount);

            // User2 has no balance
            expect(await savingsVault.getERC20Balance(user2.address, tokenAddress)).to.equal(0);

            // User1's balance is correct
            expect(await savingsVault.getERC20Balance(user1.address, tokenAddress)).to.equal(depositAmount);
        });
    });
});