// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";
import {IAgentIdentityRegistry} from "../src/interfaces/IAgentIdentityRegistry.sol";

contract AgentIdentityRegistryTest is Test {
    AgentIdentityRegistry internal registry;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    event AgentRegistered(uint256 indexed agentId, address indexed owner, string metadataURI);
    event MetadataUpdated(uint256 indexed agentId, string metadataURI);
    event OwnershipTransferred(uint256 indexed agentId, address indexed from, address indexed to);

    function setUp() public {
        registry = new AgentIdentityRegistry();
    }

    // ─── registerAgent ─────────────────────────────────────────────

    function test_RegisterAgent_AssignsSequentialIds() public {
        vm.prank(alice);
        uint256 id1 = registry.registerAgent("ipfs://one");
        assertEq(id1, 1);

        vm.prank(bob);
        uint256 id2 = registry.registerAgent("ipfs://two");
        assertEq(id2, 2);

        assertEq(registry.nextId(), 3);
    }

    function test_RegisterAgent_StoresOwnerAndMetadata() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://manifest");

        IAgentIdentityRegistry.Agent memory a = registry.getAgent(id);
        assertEq(a.owner, alice);
        assertEq(a.metadataURI, "ipfs://manifest");
        assertEq(uint256(a.registeredAt), block.timestamp);
        assertTrue(registry.exists(id));
    }

    function test_RegisterAgent_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(1, alice, "ipfs://manifest");

        vm.prank(alice);
        registry.registerAgent("ipfs://manifest");
    }

    function test_RegisterAgent_RevertsOnEmptyURI() public {
        vm.expectRevert(AgentIdentityRegistry.MetadataRequired.selector);
        vm.prank(alice);
        registry.registerAgent("");
    }

    // ─── updateMetadata ────────────────────────────────────────────

    function test_UpdateMetadata_HappyPath() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://v1");

        vm.expectEmit(true, false, false, true);
        emit MetadataUpdated(id, "ipfs://v2");

        vm.prank(alice);
        registry.updateMetadata(id, "ipfs://v2");

        assertEq(registry.getAgent(id).metadataURI, "ipfs://v2");
    }

    function test_UpdateMetadata_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://v1");

        vm.expectRevert(AgentIdentityRegistry.NotOwner.selector);
        vm.prank(bob);
        registry.updateMetadata(id, "ipfs://v2");
    }

    function test_UpdateMetadata_RevertsForUnknownAgent() public {
        vm.expectRevert(AgentIdentityRegistry.AgentNotFound.selector);
        vm.prank(alice);
        registry.updateMetadata(999, "ipfs://x");
    }

    function test_UpdateMetadata_RevertsOnEmptyURI() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://v1");

        vm.expectRevert(AgentIdentityRegistry.MetadataRequired.selector);
        vm.prank(alice);
        registry.updateMetadata(id, "");
    }

    // ─── transferOwnership ─────────────────────────────────────────

    function test_TransferOwnership_HappyPath() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://m");

        vm.expectEmit(true, true, true, false);
        emit OwnershipTransferred(id, alice, bob);

        vm.prank(alice);
        registry.transferOwnership(id, bob);

        assertEq(registry.getAgent(id).owner, bob);
    }

    function test_TransferOwnership_RevertsForNonOwner() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://m");

        vm.expectRevert(AgentIdentityRegistry.NotOwner.selector);
        vm.prank(bob);
        registry.transferOwnership(id, bob);
    }

    function test_TransferOwnership_RevertsOnZeroAddress() public {
        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://m");

        vm.expectRevert(AgentIdentityRegistry.ZeroAddress.selector);
        vm.prank(alice);
        registry.transferOwnership(id, address(0));
    }

    function test_TransferOwnership_RevertsForUnknownAgent() public {
        vm.expectRevert(AgentIdentityRegistry.AgentNotFound.selector);
        vm.prank(alice);
        registry.transferOwnership(123, bob);
    }

    // ─── views ─────────────────────────────────────────────────────

    function test_Exists_ReturnsFalseForUnknown() public view {
        assertFalse(registry.exists(0));
        assertFalse(registry.exists(1));
        assertFalse(registry.exists(type(uint256).max));
    }

    function test_GetAgent_ReturnsEmptyForUnknown() public view {
        IAgentIdentityRegistry.Agent memory a = registry.getAgent(42);
        assertEq(a.owner, address(0));
        assertEq(a.metadataURI, "");
        assertEq(uint256(a.registeredAt), 0);
    }

    function test_SupportsInterface() public view {
        assertTrue(registry.supportsInterface(type(IAgentIdentityRegistry).interfaceId));
        assertTrue(registry.supportsInterface(0x01ffc9a7)); // ERC-165
        assertFalse(registry.supportsInterface(0xffffffff));
        assertFalse(registry.supportsInterface(0xdeadbeef));
    }

    // ─── fuzz ──────────────────────────────────────────────────────

    function testFuzz_RegisterMany(uint8 n) public {
        uint256 count = uint256(n) % 32 + 1;
        for (uint256 i = 0; i < count; i++) {
            vm.prank(address(uint160(0x1000 + i)));
            uint256 id = registry.registerAgent("ipfs://x");
            assertEq(id, i + 1);
        }
        assertEq(registry.nextId(), count + 1);
    }

    function testFuzz_TransferThenUpdateBlocked(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != alice);

        vm.prank(alice);
        uint256 id = registry.registerAgent("ipfs://m");

        vm.prank(alice);
        registry.transferOwnership(id, newOwner);

        // Old owner can no longer update.
        vm.expectRevert(AgentIdentityRegistry.NotOwner.selector);
        vm.prank(alice);
        registry.updateMetadata(id, "ipfs://v2");

        // New owner can.
        vm.prank(newOwner);
        registry.updateMetadata(id, "ipfs://v2");
        assertEq(registry.getAgent(id).metadataURI, "ipfs://v2");
    }
}
