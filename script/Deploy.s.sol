// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";
import {ValidationRegistry} from "../src/ValidationRegistry.sol";

/// @title Deploy
/// @notice Deploys AgentIdentityRegistry then ValidationRegistry wired
///         to it. Address is logged to stdout — the deployer is
///         responsible for capturing them into the project README's
///         "Deployments" table.
///
/// Usage:
///   forge script script/Deploy.s.sol:Deploy \
///       --rpc-url arc_testnet \
///       --broadcast \
///       --verify
///
/// Required env:
///   PRIVATE_KEY        — deployer key (NEVER commit)
contract Deploy is Script {
    function run() external returns (address identity, address validation) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        AgentIdentityRegistry id = new AgentIdentityRegistry();
        identity = address(id);
        console2.log("AgentIdentityRegistry:", identity);

        ValidationRegistry vr = new ValidationRegistry(identity);
        validation = address(vr);
        console2.log("ValidationRegistry:   ", validation);

        vm.stopBroadcast();
    }
}
