// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";

import {VaultFactory} from "../src/VaultFactory.sol";

contract DeployVaultFactory is Script {
    address private immutable deployerAddress;
    VaultFactory public vaultFactory;

    constructor() {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);
    }

    function run() external {
        vm.startBroadcast(deployerAddress);
        vaultFactory = new VaultFactory(0);
        vm.stopBroadcast();
    }
}
