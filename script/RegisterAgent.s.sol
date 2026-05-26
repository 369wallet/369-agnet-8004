// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IAgentIdentityRegistry} from "../src/interfaces/IAgentIdentityRegistry.sol";

/// @title RegisterAgent
/// @notice Registers an agent against an already-deployed identity
///         registry and prints the assigned id.
///
/// Usage:
///   IDENTITY_REGISTRY=0x... \
///   METADATA_URI=ipfs://... \
///   forge script script/RegisterAgent.s.sol:RegisterAgent \
///       --rpc-url arc_testnet \
///       --broadcast
contract RegisterAgent is Script {
    function run() external returns (uint256 agentId) {
        address registry = vm.envAddress("IDENTITY_REGISTRY");
        string memory uri = vm.envString("METADATA_URI");
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        agentId = IAgentIdentityRegistry(registry).registerAgent(uri);
        vm.stopBroadcast();

        console2.log("Agent registered:");
        console2.log("  agentId:", agentId);
        console2.log("  metadataURI:", uri);
    }
}
