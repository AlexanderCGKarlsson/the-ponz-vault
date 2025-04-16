// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "src/ThePonzVault.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {USDCToken} from "test/mocks/USDCToken.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployVault} from "script/DeployVault.s.sol";
import {VaultConstants} from "src/libraries/VaultConstants.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

contract ThePonzVaultTest is Test {
    Vault public vault;
    HelperConfig public helperConfig;

    address usdcTokenAddress;
    address public PLAYER_ONE = makeAddr("player_one");
    address public PLAYER_TWO = makeAddr("player_two");
    uint256 public constant STARTING_BALANCE = 5 ether;
    uint256 public constant TIME_INTERVAL = 60 minutes;
    uint256 public constant DECIMALS_PRECISION = 1e6;
    uint256 private constant FEE_PRECISION = 10000;
    uint256 public constant VAULT_FEE = VaultConstants.VAULT_FEE_BASIS_POINTS;
    

    function setUp() external {
        DeployVault deployer = new DeployVault();
        (vault, helperConfig) = deployer.deployContract();
        usdcTokenAddress = vault.getUsdcAddress();

        // Mint USDC to players
        USDCToken(usdcTokenAddress).mint(PLAYER_ONE, 1000 * DECIMALS_PRECISION);
        USDCToken(usdcTokenAddress).mint(PLAYER_TWO, 1000 * DECIMALS_PRECISION); 
        

        // Dealing some ETH to players
        vm.deal(PLAYER_ONE, STARTING_BALANCE);
        vm.deal(PLAYER_TWO, STARTING_BALANCE);
    }

    /* State tests */

    function testVaultInitializedState() public view {
        console.log("The Vault starting status", uint256(vault.getVaultStatus()));
        assert(vault.getVaultStatus() == Vault.VaultStatus.OPEN);
    }

    function testDeposit(uint256 amount) public {
        amount = bound(amount, 1e5, 100 * DECIMALS_PRECISION);
        vm.startPrank(PLAYER_ONE);

        // Approve the vault to spend USDC
        IERC20(usdcTokenAddress).approve(address(vault), amount);
        console.log("Player one's USDC Balance", IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE));
        vault.depositVault(amount);
        console.log("Player one's USDC Balance After", IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE));
        vm.stopPrank();
    }

    /* Deposit tests */
    function testTwoPlayerDeposit(uint256 amount) public {
        amount = bound(amount, 1e5, 99 * DECIMALS_PRECISION);
        vm.startPrank(PLAYER_ONE);

        // Approve the vault to spend USDC
        IERC20(usdcTokenAddress).approve(address(vault), amount);
        vault.depositVault(amount);
        vm.stopPrank();
        // Prank player two
        vm.startPrank(PLAYER_TWO);
        // Approve for player two
        IERC20(usdcTokenAddress).approve(address(vault), amount + 1);
        vault.depositVault(amount + 1);
    }


    function testNumberTwoPlayerFailsBecauseOfEqualDeposit(uint256 amount) public {
        amount = bound(amount, 1e5, 100 * DECIMALS_PRECISION);
        vm.startPrank(PLAYER_ONE);
        IERC20(usdcTokenAddress).approve(address(vault), amount);
        console.log("Player one deposits amount: ", amount);
        // Deposits into the vault
        vault.depositVault(amount);
        vm.stopPrank();
        // Prank the second player
        vm.startPrank(PLAYER_TWO);
        IERC20(usdcTokenAddress).approve(address(vault), amount);
        vm.expectRevert(
            Vault.Vault__AmountNeedsToBeMoreThanLastDepositor.selector);
        console.log("Player two deposits amount ", amount);
        vault.depositVault(amount);
    }

    function testDepositAndGetCurrentWinningPlayerAndLastAmount() public {
        uint256 balance = IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE);
        console.log("Player one address: ", PLAYER_ONE);
        vm.startPrank(PLAYER_ONE);
        IERC20(usdcTokenAddress).approve(address(vault), balance);
        uint256 depositAmount = balance - 99;
        vault.depositVault(depositAmount);
        address currentWinningPlayer = vault.getCurrentWinningPlayer();
        vm.stopPrank();
        assertEq(currentWinningPlayer, PLAYER_ONE);
    }

    function testTwoPlayerDepositAndCurrentWinningPlayerChanges() public {
        uint256 balance = IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE);
        vm.startPrank(PLAYER_ONE);
        
        IERC20(usdcTokenAddress).approve(address(vault), balance);
        // @dev we do -99 as if we do balance, we will get hit with the revert because we deposit the same amount in PLAYER_TWO deposit.
        vault.depositVault(balance - 99);
        address currentWinningPlayer = vault.getCurrentWinningPlayer();
        assertEq(currentWinningPlayer, PLAYER_ONE);
        vm.stopPrank();

        // prank player two
        vm.startPrank(PLAYER_TWO);

        // @dev: We can use `balance` here too as we mint the same amount USDC to both users.
        IERC20(usdcTokenAddress).approve(address(vault), balance);
        vault.depositVault(balance);
        assertEq(vault.getCurrentWinningPlayer(), PLAYER_TWO);
    }

    function testTwoPlayerDepositsAndPlayerTwoWin() public {
        uint256 balance = IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE);
        vm.startPrank(PLAYER_ONE);
        
        IERC20(usdcTokenAddress).approve(address(vault), balance);
        vault.depositVault(100);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + 58 minutes);
        console.log(vault.getTimeRemaining());

        // prank player two
        vm.startPrank(PLAYER_TWO);

        IERC20(usdcTokenAddress).approve(address(vault), balance);
        vault.depositVault(101); // one more than player 1 deposit, the time should then be reset.
        assert(vault.getTimeRemaining() <= 3600);
        uint256 balanceAfterDeposit = IERC20(usdcTokenAddress).balanceOf(PLAYER_TWO);


        
        
        // Warp time again
        vm.warp(block.timestamp + 61 minutes);

        address currentWinningPlayer = vault.getCurrentWinningPlayer();
        uint256 timeRemaining = vault.getTimeRemaining();

        assertEq(currentWinningPlayer, PLAYER_TWO);
        assertEq(timeRemaining, 0);

        // Call the claim.
        bool readyForClaim = vault.checkIfVaultWinnerIsDecided();
        assertEq(readyForClaim, true);
        uint256 pricePool = vault.getCurrentVaultPool();
        
        // perform the transfer
        vault.performVaultWinner();
        vm.stopPrank();

        // Assert for player two.
        assertEq(pricePool + balanceAfterDeposit, IERC20(usdcTokenAddress).balanceOf(PLAYER_TWO));
    }

    /* Fee & payout testing */

    function testGetLastAmountAndTreasuryBalanceAndWinningPool(uint256 amount) public {
        amount = bound(amount, 1e5, 60 * DECIMALS_PRECISION);
        vm.startPrank(PLAYER_ONE);

        // Approve the vault to spend USDC
        IERC20(usdcTokenAddress).approve(address(vault), amount);
        vault.depositVault(amount);

        // Get the vault fee from the contract
        uint256 vaultFee = vault.getVaultFee();

        // Asserts
        assertEq(vault.getLastAmount(), amount);
        assertEq(vault.getTreasuryBalance(), (amount * vaultFee) / FEE_PRECISION);

        vm.stopPrank();
    }

    function testSendEthToContractAsDonation(uint256 amount) public {
        amount = bound(amount, 1e5, 100 * DECIMALS_PRECISION);
        
        // get the keccak256 hash for the event "EthDonation"
        bytes32 ethDonationSignature = keccak256("EthDonation(address,uint256)");
        console.logBytes32(ethDonationSignature);
        vm.startPrank(PLAYER_ONE);


        // Send Eth
        vm.recordLogs();
        (bool success, ) = address(vault).call{value: amount}("");
        vm.stopPrank();
        console.log("The vault ETH balance", vault.getEthBalance());
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        console.logBytes32(entries[0].topics[0]);

        bytes32 donor = entries[0].topics[1]; // This gets the address
        uint256 donationAmount = abi.decode(entries[0].data, (uint256));


        // Asserts
        assert(success);
        assertEq(vault.getEthBalance(), amount);
        assertEq(address(uint160(uint256(donor))), PLAYER_ONE);
        assertEq(donationAmount, amount);

    }

    function testZeroSendEthToContractAsDonation() public {
        
    }

    function testWithdrawToTreasury(uint256 amount) public {
        amount = bound(amount, 1e5, 100 * DECIMALS_PRECISION);
        vm.startPrank(PLAYER_ONE);
        IERC20(usdcTokenAddress).approve(address(vault), amount);
        vault.depositVault(amount);
        (bool success, ) = address(vault).call{value: amount}("");
        vm.stopPrank();

        address owner = vault.getTreasuryOwner();
         
        // Owner has Eth already so we calculate the vault balance + what owner already has.
        uint256 ethBalanceBeforeWithdraw = address(owner).balance;
        uint256 expectedEthBalance = address(vault).balance + ethBalanceBeforeWithdraw;
        
        // Same procedure as above.
        uint256 usdcBalanceBeforeWithdraw = IERC20(usdcTokenAddress).balanceOf(owner);
        uint256 expectedUsdcToTreasury = vault.getTreasuryBalance() + usdcBalanceBeforeWithdraw;

        // Prank owner
        vm.prank(owner);
        vault.withDrawToTreasury();

        

        uint256 ethBalanceOfUser = address(owner).balance;
        uint256 usdcBalanceOfUser = IERC20(usdcTokenAddress).balanceOf(address(owner));

        // assertEq(address(this).balance, amount);
        assertEq(expectedUsdcToTreasury, usdcBalanceOfUser);
        assertEq(expectedEthBalance, ethBalanceOfUser);
    }

    function testOnlyOnlyOwnerCanWithdraw() public {
        vm.startPrank(PLAYER_ONE);
        IERC20(usdcTokenAddress).approve(address(vault), 99);
        vault.depositVault(99);
        (bool success, ) = address(vault).call{value: 99}("");
        vm.stopPrank();

        vm.prank(PLAYER_TWO);
        vm.expectRevert(abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector, 
            PLAYER_TWO));
        vault.withDrawToTreasury();
    }

    function testFeeCalculation() public {
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC
        vm.startPrank(PLAYER_ONE);
        IERC20(usdcTokenAddress).approve(address(vault), depositAmount);
        vault.depositVault(depositAmount);

        console.log("Vault's fee", vault.getVaultFee());

        uint256 expectedFee = (depositAmount * VAULT_FEE) / 10000; // This should be 4 usdc.
        assertEq(vault.getTreasuryBalance(), expectedFee);
        assertEq(expectedFee, 4 * 1e6, "Fee should be 4 USDC");
        vm.stopPrank();
    }

    function testFallBackReverts() public {
        vm.startPrank(PLAYER_ONE);

        // Call with random function signature to trigger fallback
        vm.expectRevert(Vault.Vault__NoEthAccepted.selector);
        (bool success,) = address(vault).call{value: 1 ether}(
            abi.encodeWithSignature("nonexistentFunction()")
        );

        vm.stopPrank();
    }



    /* Get testing */

    function testGetFeeForContract() public view {
        assertEq(vault.getVaultFee(), VAULT_FEE);
    }

    function testGetVaultAddress() public view {
        address vaultAddress = vault.getVaultAddress();
        console.log("Vault Address:", vaultAddress);
        console.log("Expected Address:", address(vault));
        
        assertEq(vaultAddress, address(vault), "Vault address should match contract address");
    }

    function testVaultOwnership() public view {
        address owner = vault.getTreasuryOwner();
        assertEq(owner, msg.sender);
    }


    function testGetTimeInterval() public view {
        uint256 timeInterval = vault.getTimeInterval();
        assertEq(timeInterval, TIME_INTERVAL);
    }

    function testGetLastTimeStamp() public {
        uint256 balance = IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE);
        vm.startPrank(PLAYER_ONE);
        
        IERC20(usdcTokenAddress).approve(address(vault), balance);
        uint256 expectedTimeStamp = block.timestamp;
        vault.depositVault(100);
        vm.stopPrank();
        uint256 lastTimeStamp = vault.getLastTimeStamp();
        assertEq(expectedTimeStamp, lastTimeStamp);
    }

    function testGetRecentVaultWinner() public {
        uint256 balance = IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE);
        vm.startPrank(PLAYER_ONE);
        
        IERC20(usdcTokenAddress).approve(address(vault), balance);
        vault.depositVault(100);

        // Warp the time
        vm.warp(block.timestamp + 60 minutes);
        vault.performVaultWinner();
        vm.stopPrank();

        address recentWinner = vault.getRecentVaultWinner();
        assertEq(PLAYER_ONE, recentWinner);
    }

    /* Helper Functions */

    function testIsWinnerDecidable() public {
        // Set up to return true
        uint256 balance = IERC20(usdcTokenAddress).balanceOf(PLAYER_ONE);
        vm.startPrank(PLAYER_ONE);
        
        IERC20(usdcTokenAddress).approve(address(vault), balance);
        vault.depositVault(100);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + 60 minutes);

        bool checkVaultWinner = vault.checkIfVaultWinnerIsDecided();
        assertTrue(checkVaultWinner);
    }

    /* USDC Mock */

    function testGetUSDCMockDecimals() public view {
        uint256 expectedDecimals = 6;

        
        uint256 decimals = USDCToken(usdcTokenAddress).decimals();
        assertEq(expectedDecimals, decimals);
    }

    function testUSDCMint() public {
        address PLAYER_THREE = makeAddr("player_three");
        vm.deal(PLAYER_THREE, 3 ether);
        vm.startPrank(PLAYER_THREE);
        USDCToken(usdcTokenAddress).mint(PLAYER_THREE, 100);
        assertEq(IERC20(usdcTokenAddress).balanceOf(PLAYER_THREE), 100);
    }

    function testUsdcMockTransferAndCallWithEvent() public {
        uint256 balance = IERC20(usdcTokenAddress).balanceOf(PLAYER_TWO);
        uint256 transferAmount = 100;
        bytes memory data = abi.encode("This is a test");

        vm.startPrank(PLAYER_ONE);
        // IERC20(usdcTokenAddress).approve(address(PLAYER_TWO), balance);
        bool success = USDCToken(usdcTokenAddress).transferAndCall(
            PLAYER_TWO,
            transferAmount, 
            data
        );
        vm.stopPrank();
        vm.recordLogs();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Assert
        assertTrue(success);
    }

    /* DeployVault Script */

    function testDeployVaultRunScript() public {
        DeployVault deployerVault = new DeployVault();
        deployerVault.run();

        assertTrue(address(vault) != address(0));
        assertEq(vault.getVaultFee(), deployerVault.VAULT_FEE_BASIS_POINT());
    }

    /* HelperConfig */
    function testGetConfigByChainId() public {
        // Test for LOCAL_CHAIN_ID
        HelperConfig.NetworkConfig memory config = helperConfig.getConfigByChainId(helperConfig.LOCAL_CHAIN_ID());
        assertTrue(address(config.usdcTokenAddress) != address(0));
    }

    function testGetOrCreateAnvilConfig() public {
        HelperConfig.NetworkConfig memory config = helperConfig.getOrCreateAnvilEthConfig();
        
        // Verify USDC token was deployed
        assertTrue(address(config.usdcTokenAddress) != address(0));
        
        // Verify local config was set
        (address usdcAddress) = helperConfig.localNetworkConfig();
        assertEq(config.usdcTokenAddress, usdcAddress);
    }
}