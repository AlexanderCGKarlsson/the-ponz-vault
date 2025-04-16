// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Vault} from "src/ThePonzVault.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {console2} from "forge-std/console2.sol";

contract DeployVault is Script {

    uint256 public constant VAULT_FEE_BASIS_POINT = 40;
    uint256 public constant TIME_INTERVAL = 60 minutes;
    

    function run() public {
        deployContract();
    }

    function deployContract() public returns (Vault, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        address usdcAddress = config.usdcTokenAddress;

        vm.startBroadcast();
        Vault vault = new Vault(VAULT_FEE_BASIS_POINT, usdcAddress, TIME_INTERVAL);
        vm.stopBroadcast();

        return(vault, helperConfig);
        }
    }