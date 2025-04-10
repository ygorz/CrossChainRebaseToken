// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {RebaseToken} from "src/RebaseToken.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";

contract TokenAndPoolDeployer is Script {
    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        // create a new ccip local simulator fork
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // get the network details of the current chain id with the ccip simulator fork
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();
        // deploy token
        token = new RebaseToken();
        // deploy token pool
        pool = new RebaseTokenPool(
            IERC20(address(token)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );

        vm.stopBroadcast();
    }
}

contract SetPermissions is Script {
    function grantRole(address token, address pool) public {
        vm.startBroadcast();
        // grant role to pool to mint and burn
        IRebaseToken(address(token)).grantMintAndBurnRole(address(pool));
        vm.stopBroadcast();
    }

    function setAdmin(address token, address pool) public {
        // create a new ccip local simulator fork
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // get the network details of the current chain id with the ccip simulator fork
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();

        // claim admin role for the token
        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(token));
        // accept admin role for the token
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(token));
        //
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(address(token), address(pool));
        vm.stopBroadcast();
    }
}

contract VaultDeployer is Script {
    function run(address _rebaseToken) public returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
    }
}
