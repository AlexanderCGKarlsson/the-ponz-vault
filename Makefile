-include .env

.PHONY: all test deploy

build :; forge build

test :; forge test

install :; forge install cyfrin/foundry-devops@0.3.2 && forge install Openzeppelin/openzeppelin-contracts && forge install foundry-rs/forge-std

deploy-baseSepolia:
	@forge script script/DeployVault.s.sol:DeployVault --rpc-url $(BASE_SEPOLIA_RPC_URL) --account $(ACCOUNT) --broadcast --verify --etherscan-api-key $(BASE_ETHERSCAN_API_KEY) -vvvv

deploy-arbSepolia:
	@forge script script/DeployVault.s.sol:DeployVault --rpc-url $(ARB_SEPOLIA_RPC_URL) --account $(ACCOUNT) --broadcast --verify --etherscan-api-key $(ARB_ETHERSCAN_API_KEY) -vvvv

deploy:
	@forge script script/DeployVault.s.sol:DeployVault --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -vvvv