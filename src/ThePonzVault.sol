// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";

/** 
 * @title The Ponz Vault
 * @author acgk
 * @notice This is a vault that users can deposit into, the last user who deposits into the vault and the time ends will win the vaults worth of USDC.
 * @notice The only possible function to deposit into the game, will go through the deposit function. The receive & fallback will be considered as donation to the procotol.
 * @notice As the s_lastAmount increases the more the treasury will get, it is working as intended in the design.
 * @notice It's another game within the game once the countdown reaches 0 that the s_currentWinningPlayer calls the `performVaultWinner()` function to claim their prize (other may do it for them too).
 * If left snoozing others can deposit and restart the clock. 
 * @dev we currently using an enm VaultStatus (open / closed) it's with conscience that its left in open state and can be implemented with closed for future upgrades to the contract.
 */

contract Vault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /* Errors */
    error Vault__DepositFailed();
    error Vault__AmountNeedsToBeMoreThanLastDepositor();
    error Vault__DepositingIsNotOpen();
    error Vault__NoEthAccepted();
    error Vault__PickingVaultWinnerIsNotNeeded(uint256 balance, uint256 timeStamp, uint256 vaultStatus);
    error Vault__TransferFailed();
    error Vault__TransferFailedToTreasury();
    error Vault__TreasuryIsEmpty(uint256 balance);
    error Vault__ZeroEthDonation();
    error Vault__InvalidUsdcTokenAddress();
    error Vault__EthTransferFailed();
    error Vault__MessageTooLong();

    /* type declarations */
    enum VaultStatus {
        OPEN,
        CLOSED
    }

    /* State Variables */
    uint256 private constant FEE_PRECISION = 10000;
    // uint256 private constant TIME_INTERVAL = 60 minutes; // 60 minutes.
    uint256 private immutable i_VaultFee; // Fee percentage in basis points (1/100 of a percent)
    uint256 private s_lastAmount;
    uint256 private s_lastTimeStamp;
    uint256 private s_treasury;
    address private s_currentWinningPlayer;
    address private s_winner;
    IERC20 private immutable i_usdcTokenAddress;
    uint256 private immutable i_timeInterval;

    VaultStatus private s_vaultStatus;

    event VaultDepositor(address indexed user, uint256 indexed amount, string message);
    event VaultWinner(address indexed winner, uint256 indexed amount);
    event FeeCollected(uint256 fee);
    event EthDonation(address indexed donor, uint256 amount);
    event EthWithdrawn(address indexed to, uint256 amount);

    constructor(uint256 _vaultFee, address _usdcTokenAddress, uint256 _timeInterval
    ) Ownable (msg.sender) {
        if (_usdcTokenAddress == address(0)) revert Vault__InvalidUsdcTokenAddress();
        i_VaultFee = _vaultFee; // fee in basis points (example: 50 = 0.5%)
        i_usdcTokenAddress = IERC20(_usdcTokenAddress);
        s_vaultStatus = VaultStatus.OPEN;
        i_timeInterval = _timeInterval;
    }

    /**
     * @notice Allows user to deposit USDC into the vault
     * @param _amount Amount of USDC to deposit
     * @dev The same user can technically deposit again without rejection.
     * @dev Must be grater than the last deposit. Fee is calculated and added to treasury.
     * @dev Fee Calculation: amount * fee_basis_points / 10000
     * For example: 100 usdc with a 0.4% fee (40 basis points)
     * Fee = 100 * 40 / 10000 = 0.4 USDC
     */
    function depositVault(uint256 _amount, string calldata _message) external {
        if (_amount <= s_lastAmount) {
            revert Vault__AmountNeedsToBeMoreThanLastDepositor();
        }
        if (s_vaultStatus != VaultStatus.OPEN) {
            revert Vault__DepositingIsNotOpen();
        }

        // Message will be restricted to 140 in length.
        if (bytes(_message).length > 140) revert Vault__MessageTooLong();

        /* @dev Calculate the fee (i_VaultFee is in basis points, 1 basis point = 0.01%) */
        uint256 feeAmount = (_amount * i_VaultFee) / FEE_PRECISION;

        // Add the fee to the treasury
        s_treasury += feeAmount;
        s_currentWinningPlayer = msg.sender;
        s_lastAmount = _amount;
        s_lastTimeStamp = block.timestamp;

        i_usdcTokenAddress.safeTransferFrom(msg.sender, address(this), _amount);

        emit VaultDepositor(msg.sender, _amount, _message);
    }

    /**
     * @dev - The function will be called to the chainlink nodes to check if the vault winner is ready to be called.
     * @return upkeepNeeded - true if `performVaultWinner` can be called.
     * @return performData - Is the data that will be passed to the function when `performVaultWinner`is called
     */

    function checkUpkeep(bytes memory /* checkData */) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool deadlineHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_timeInterval);
        bool vaultIsOpen = s_vaultStatus == VaultStatus.OPEN;
        bool hasBalance = IERC20(i_usdcTokenAddress).balanceOf(address(this)) > 0;
        upkeepNeeded = (deadlineHasPassed && vaultIsOpen && hasBalance);
        return(upkeepNeeded, "");
    }

    /**
     * @notice Determines and pays out the vault winner.
     * @dev Can only be called when the time has expired and vault has balance.
     * @dev Follows CEI: Checks, effects, interactions.
     */

    function performVaultWinner(bytes calldata /* performData */) external nonReentrant {
        // Checking if Vault Winner can be decided. 
        (bool upKeepNeeded, ) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Vault__PickingVaultWinnerIsNotNeeded(address(this).balance, s_lastTimeStamp, uint256(s_vaultStatus));
        }

        // Set the effects.
        s_winner = s_currentWinningPlayer;
        s_lastTimeStamp = block.timestamp;
        s_lastAmount = 0;

        /*
        * // s_vaultStatus = VaultStatus.CLOSED;
        * @dev: This can be implemented if we will use open / close in two different functions.
        * As of now with how the contract looks it does not make sense to have it open and close within the same function.
        */

        // Calculate Vault price before changing state
        uint256 totalBalance = i_usdcTokenAddress.balanceOf(address(this));
        uint256 pricePool = totalBalance - s_treasury;

        i_usdcTokenAddress.safeTransfer(s_winner, pricePool);

        // s_vaultStatus = VaultStatus.OPEN;

        emit VaultWinner(s_winner, pricePool);
    }

    /**
     * @notice Allows the owner to withdraw accumulated fees
     * @dev Withdraws both USDC fees and any ETH donations.
     */
    function withDrawToTreasury() external onlyOwner {
        uint256 treasuryValue = s_treasury;
        if (treasuryValue == 0) {
            revert Vault__TreasuryIsEmpty(treasuryValue);
        }
        
        // Transfer out the USDC.
        i_usdcTokenAddress.safeTransfer(owner(), treasuryValue);

        // Set the treasury back to 0
        s_treasury = 0;

        // Withdraw any ETH donations
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool ethSuccess, ) = owner().call{value: ethBalance}("");
            if(!ethSuccess) {
                revert Vault__EthTransferFailed();
            }
            emit EthWithdrawn(owner(), ethBalance);
        }
        emit FeeCollected(treasuryValue);
    }

    // Function handles if anyone is trying to send ETH to the contract.
    receive() external payable {
        if (msg.value == 0) {
            revert Vault__ZeroEthDonation();
        }
        emit EthDonation(msg.sender, msg.value);
    }

    // We revert fallbacks if somebody tries to call a function that doesn't exist.
    fallback() external payable {
        revert Vault__NoEthAccepted();
    }


    /* Getter functions */

    // Game State
    function getVaultStatus() external view returns (VaultStatus) {
        return s_vaultStatus;
    }

    function getCurrentWinningPlayer() external view returns (address) {
        return s_currentWinningPlayer;
    }

    function getRecentVaultWinner() external view returns (address) {
        return s_winner;
    }
    
    // Time Info

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getTimeRemaining() external view returns (uint256) {
        if (block.timestamp - s_lastTimeStamp >= i_timeInterval) {
            return 0;
        }
        return i_timeInterval - (block.timestamp - s_lastTimeStamp);
    }


    function getLastAmount() external view returns (uint256) {
        return s_lastAmount;
    }

    // Balance Info
    function getTreasuryBalance() external view returns (uint256) {
        return s_treasury;
    }

    function getCurrentVaultPool() external view returns (uint256) {
        uint256 totalBalance = IERC20(i_usdcTokenAddress).balanceOf(address(this));
        return totalBalance - s_treasury;
    }

    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Contract Constants
    function getVaultFee() external view returns (uint256) {
        return i_VaultFee;
    }

    function getTimeInterval() external view returns (uint256) {
        return i_timeInterval;
    }

    function getUsdcAddress() external view returns (IERC20) {
        return i_usdcTokenAddress;
    }

    function getVaultAddress() external view returns (address) {
        return address(this);
    }

    function getTreasuryOwner() external view returns (address) {
        return owner();
    }

    // Helper Function
    function isWinnerDecidable() external view returns (bool) {
        (bool upkeepNeeded, ) = checkUpkeep("");
        return upkeepNeeded;
    }
}