// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Vault} from "src/ThePonzVault.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {USDCToken} from "test/mocks/USDCToken.sol";


abstract contract CodeConstants {
    /* Chain IDs */
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 public constant BASE_MAINNET_CHAIN_ID = 8453;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    address public constant BASE_SEPOLIA_USDC_TOKEN_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address public constant BASE_MAINNET_USDC_TOKEN_ADDRESS = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
}

contract HelperConfig is Script, CodeConstants {
    /* Errors */
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address usdcTokenAddress;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[BASE_SEPOLIA_CHAIN_ID] = getBaseSepoliaEthConfig();
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if(networkConfigs[chainId].usdcTokenAddress != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            console2.log("Creating the local anvil chain config");
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getBaseSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdcTokenAddress: BASE_SEPOLIA_USDC_TOKEN_ADDRESS
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Deploy the mocks

        vm.startBroadcast();
        USDCToken usdcToken = new USDCToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            usdcTokenAddress: address(usdcToken)
        });

        return localNetworkConfig; 
    }
}