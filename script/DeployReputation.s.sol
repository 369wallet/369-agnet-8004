// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ReputationRegistry} from "../src/ReputationRegistry.sol";

/// @title DeployReputation
/// @notice Deploys ONLY the ReputationRegistry, wired to a previously-
///         deployed ValidationRegistry on the same chain. Keeps the
///         existing Identity + Validation deployments untouched —
///         Reputation is an additive layer.
///
/// Usage:
///   VALIDATION_REGISTRY=0x148336926e6F21A2EC63B47BA31dD0B08E538b91 \
///   forge script script/DeployReputation.s.sol:DeployReputation \
///       --rpc-url arc_testnet \
///       --broadcast \
///       --verify
///
/// Required env:
///   PRIVATE_KEY          — deployer key (NEVER commit)
///   VALIDATION_REGISTRY  — address of the existing ValidationRegistry
///                          this Reputation layer will bind to.
contract DeployReputation is Script {
    function run() external returns (address reputation) {
        uint256 pk = _deployerKey();
        address validation = vm.envAddress("VALIDATION_REGISTRY");
        require(validation != address(0), "VALIDATION_REGISTRY env empty");

        vm.startBroadcast(pk);
        ReputationRegistry r = new ReputationRegistry(validation);
        reputation = address(r);
        console2.log("ReputationRegistry:", reputation);
        console2.log("  bound to ValidationRegistry:", validation);
        vm.stopBroadcast();
    }

    /// @dev Accepts PRIVATE_KEY in either form (matches Deploy.s.sol).
    function _deployerKey() internal view returns (uint256) {
        try vm.envUint("PRIVATE_KEY") returns (uint256 v) {
            return v;
        } catch {
            string memory raw = vm.envString("PRIVATE_KEY");
            return vm.parseUint(string.concat("0x", raw));
        }
    }
}
