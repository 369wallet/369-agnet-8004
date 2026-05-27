// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";
import {ValidationRegistry} from "../src/ValidationRegistry.sol";
import {ReputationRegistry} from "../src/ReputationRegistry.sol";
import {IReputationRegistry} from "../src/interfaces/IReputationRegistry.sol";

/// @dev   Reputation only meaningfully exercises ONE auth path
///        (submitter == msg.sender) but the surface area is small —
///        we still cover happy path, both kinds, both reverts, the
///        one-per-key invariant, the cross-agent isolation, and a
///        fuzz over up-to-32 mixed feedbacks.
contract ReputationRegistryTest is Test {
    AgentIdentityRegistry internal identity;
    ValidationRegistry internal validation;
    ReputationRegistry internal reputation;

    uint256 internal constant AGENT_OWNER_PK = 0xA11CE;
    address internal agentOwner;

    address internal alice = address(0xA11);
    address internal bob   = address(0xB0B);

    uint256 internal agentA;
    uint256 internal agentB;

    event FeedbackRecorded(
        uint256 indexed agentId,
        bytes32 indexed validationKey,
        address indexed rater,
        IReputationRegistry.FeedbackKind kind,
        string outcomeURI
    );

    function setUp() public {
        agentOwner = vm.addr(AGENT_OWNER_PK);
        identity = new AgentIdentityRegistry();
        validation = new ValidationRegistry(address(identity));
        reputation = new ReputationRegistry(address(validation));

        vm.startPrank(agentOwner);
        agentA = identity.registerAgent("ipfs://agent-A");
        agentB = identity.registerAgent("ipfs://agent-B");
        vm.stopPrank();
    }

    // ─── happy path ────────────────────────────────────────────────

    function test_RecordFeedback_Favorable() public {
        bytes32 key = _submit(agentA, "ok-1", alice);

        vm.expectEmit(true, true, true, true);
        emit FeedbackRecorded(agentA, key, alice, IReputationRegistry.FeedbackKind.FAVORABLE, "ipfs://outcome");

        vm.prank(alice);
        reputation.recordFeedback(key, IReputationRegistry.FeedbackKind.FAVORABLE, "ipfs://outcome");

        IReputationRegistry.Reputation memory r = reputation.getReputation(agentA);
        assertEq(r.favorable, 1);
        assertEq(r.unfavorable, 0);
        assertEq(uint256(r.lastUpdate), block.timestamp);
        assertTrue(reputation.hasFeedback(key));
    }

    function test_RecordFeedback_Unfavorable() public {
        bytes32 key = _submit(agentA, "bad-1", alice);

        vm.prank(alice);
        reputation.recordFeedback(key, IReputationRegistry.FeedbackKind.UNFAVORABLE, "");

        IReputationRegistry.Reputation memory r = reputation.getReputation(agentA);
        assertEq(r.favorable, 0);
        assertEq(r.unfavorable, 1);
    }

    function test_RecordFeedback_MultipleScoresAggregate() public {
        bytes32 k1 = _submit(agentA, "a", alice);
        bytes32 k2 = _submit(agentA, "b", alice);
        bytes32 k3 = _submit(agentA, "c", bob);
        bytes32 k4 = _submit(agentA, "d", bob);

        vm.prank(alice);
        reputation.recordFeedback(k1, IReputationRegistry.FeedbackKind.FAVORABLE, "");
        vm.prank(alice);
        reputation.recordFeedback(k2, IReputationRegistry.FeedbackKind.UNFAVORABLE, "");
        vm.prank(bob);
        reputation.recordFeedback(k3, IReputationRegistry.FeedbackKind.FAVORABLE, "");
        vm.prank(bob);
        reputation.recordFeedback(k4, IReputationRegistry.FeedbackKind.FAVORABLE, "");

        IReputationRegistry.Reputation memory r = reputation.getReputation(agentA);
        assertEq(r.favorable, 3);
        assertEq(r.unfavorable, 1);
    }

    // ─── reverts ───────────────────────────────────────────────────

    function test_Revert_UnknownValidation() public {
        vm.expectRevert(ReputationRegistry.UnknownValidation.selector);
        vm.prank(alice);
        reputation.recordFeedback(bytes32(uint256(0xDEAD)), IReputationRegistry.FeedbackKind.FAVORABLE, "");
    }

    function test_Revert_NotSubmitter() public {
        bytes32 key = _submit(agentA, "alice-only", alice);

        vm.expectRevert(ReputationRegistry.NotSubmitter.selector);
        vm.prank(bob);
        reputation.recordFeedback(key, IReputationRegistry.FeedbackKind.FAVORABLE, "");
    }

    function test_Revert_AlreadyScored() public {
        bytes32 key = _submit(agentA, "one-shot", alice);

        vm.prank(alice);
        reputation.recordFeedback(key, IReputationRegistry.FeedbackKind.FAVORABLE, "");

        vm.expectRevert(ReputationRegistry.AlreadyScored.selector);
        vm.prank(alice);
        reputation.recordFeedback(key, IReputationRegistry.FeedbackKind.UNFAVORABLE, "");
    }

    // ─── isolation ────────────────────────────────────────────────

    function test_AgentIsolation_FeedbacksDontBleed() public {
        bytes32 keyA = _submit(agentA, "a-1", alice);
        bytes32 keyB = _submit(agentB, "b-1", alice);

        vm.prank(alice);
        reputation.recordFeedback(keyA, IReputationRegistry.FeedbackKind.FAVORABLE, "");
        vm.prank(alice);
        reputation.recordFeedback(keyB, IReputationRegistry.FeedbackKind.UNFAVORABLE, "");

        IReputationRegistry.Reputation memory rA = reputation.getReputation(agentA);
        IReputationRegistry.Reputation memory rB = reputation.getReputation(agentB);
        assertEq(rA.favorable, 1);
        assertEq(rA.unfavorable, 0);
        assertEq(rB.favorable, 0);
        assertEq(rB.unfavorable, 1);
    }

    // ─── views ────────────────────────────────────────────────────

    function test_GetReputation_EmptyForUnknownAgent() public view {
        IReputationRegistry.Reputation memory r = reputation.getReputation(999);
        assertEq(r.favorable, 0);
        assertEq(r.unfavorable, 0);
        assertEq(uint256(r.lastUpdate), 0);
    }

    function test_HasFeedback_FalseUntilScored() public {
        bytes32 key = _submit(agentA, "not-scored", alice);
        assertFalse(reputation.hasFeedback(key));

        vm.prank(alice);
        reputation.recordFeedback(key, IReputationRegistry.FeedbackKind.FAVORABLE, "");
        assertTrue(reputation.hasFeedback(key));
    }

    function test_SupportsInterface() public view {
        assertTrue(reputation.supportsInterface(type(IReputationRegistry).interfaceId));
        assertTrue(reputation.supportsInterface(0x01ffc9a7));
        assertFalse(reputation.supportsInterface(0xffffffff));
    }

    // ─── fuzz ─────────────────────────────────────────────────────

    function testFuzz_MixedFeedbackTotals(uint8 favorableCount, uint8 unfavorableCount) public {
        uint256 nF = uint256(favorableCount) % 16;
        uint256 nU = uint256(unfavorableCount) % 16;

        for (uint256 i = 0; i < nF; i++) {
            bytes32 k = _submit(agentA, _seed("f", i), alice);
            vm.prank(alice);
            reputation.recordFeedback(k, IReputationRegistry.FeedbackKind.FAVORABLE, "");
        }
        for (uint256 j = 0; j < nU; j++) {
            bytes32 k = _submit(agentA, _seed("u", j), alice);
            vm.prank(alice);
            reputation.recordFeedback(k, IReputationRegistry.FeedbackKind.UNFAVORABLE, "");
        }

        IReputationRegistry.Reputation memory r = reputation.getReputation(agentA);
        assertEq(uint256(r.favorable), nF);
        assertEq(uint256(r.unfavorable), nU);
    }

    // ─── helpers ──────────────────────────────────────────────────

    function _submit(uint256 agentId, string memory recSeed, address submitter)
        internal
        returns (bytes32 key)
    {
        bytes32 recHash = keccak256(bytes(recSeed));
        bytes memory sig = _sign(AGENT_OWNER_PK, recHash);

        vm.prank(submitter);
        key = validation.submitValidation(agentId, recHash, bytes32(uint256(uint160(submitter))), sig, true, "");
    }

    function _seed(string memory tag, uint256 i) internal pure returns (string memory) {
        return string(abi.encodePacked(tag, "-", _toString(i)));
    }

    function _toString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory b = new bytes(len);
        while (v != 0) {
            len -= 1;
            b[len] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(b);
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
