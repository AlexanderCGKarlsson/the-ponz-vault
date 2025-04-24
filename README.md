![img](img/The%20Ponz.png)


# The Ponz Vault

A last-depositor-wins game built on the Base blockchain where users compete to be the final depositor when the timer runs out.

## Overview

The Ponz Vault is a smart contract game where users deposit USDC into a vault. Each deposit must be larger than the previous one, and the last person to deposit before the timer expires wins the entire vault's contents (minus fees).

Key features:
- Last depositor when the timer expires wins the pot
- Each deposit must be larger than the previous one
- Configurable time interval between deposits
- Small fee on deposits goes to the treasury
- ETH donations accepted but not required for gameplay

## How It Works

1. **Deposit**: Users deposit USDC into the vault. Each deposit must be larger than the previous one.
2. **Timer**: Each deposit resets the timer (configurable, typically 60 minutes).
3. **Win Condition**: When the timer expires, the last depositor can claim the entire vault's contents.
4. **Snooze Period**: If no one claims the prize after the timer expires, others can deposit again and restart the clock.

## Game Mechanics

### Deposits
- Each deposit must be larger than the previous one
- A small fee is taken from each deposit and added to the treasury
- The depositor becomes the current winning player
- The timer resets with each deposit

### Winning
- When the timer expires, the current winning player can claim the prize
- Anyone can trigger the payout to the winner by calling `performVaultWinner()`
- If no one claims the prize, the game remains in a "claimable" state until someone either claims or makes a new deposit

### Treasury
- Fees collected from deposits accumulate in the treasury
- Only the contract owner can withdraw from the treasury
- The treasury also collects any ETH donations sent to the contract

## Getting Started

### Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0`

### Quickstart

```bash
git clone https://github.com/AlexanderCGKarlsson/the-ponz-vault
cd the-ponz-vault
forge build
```

###  Environment Setup
copy the example `Env.example`and fill in your values.

``` bash
cp .env.example .env
```

Required environment variables:
- `PRIVATE_KEY`: Your wallet's private key (This should only be added if you are not using `cast wallet` - makefile need to be edited then with --$(PRIVATE_KEY) if used.)
- `BASE_SEPOLIA_RPC_URL`: RPC URL for Base Sepolia testnet
- `ARB_SEPOLIA_RPC_URL`: RPC URL for Arbitrum Sepolia testnet
- `BASE_ETHERSCAN_API_KEY`: API key for Base block explorer
- `ARB_ETHERSCAN_API_KEY`: API key for Arbitrum block explorer
- `ACCOUNT`: The account name configured in your cast wallet Foundry setup.

## Usage

### Start a Local Node

``` bash
anvil
```

### Deploy locally (on anvil chain, run the above command first)

``` bash
make deploy
```

### Deploy to testnet

For Base Sepolia:

``` bash
make deploy-baseSepolia
```

For Arbitrum:

``` bash
make deploy-arbSepolia
```

### Testing

Run the whole test suite

``` bash
make test
```

## Technical Implementation

The Ponz Vault is implemented as a Solidity smart contract with the following key components:

- **ReentrancyGuard**: Prevents reentrancy attacks during prize distribution
- **Ownable**: Restricts treasury withdrawals to the contract owner
- **IERC20 Integration**: Works with any USDC token on the Base network
- **State Management**: Tracks current winner, deposit amounts, and time remaining

## Disclaimer

This is a gambling game. You have a high probability of losing your money, participate at your own risk. There is no guarantee of winning, and you may lose your deposited funds. 