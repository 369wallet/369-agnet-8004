// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {AgentIdentityRegistry} from "../src/AgentIdentityRegistry.sol";
import {ValidationRegistry} from "../src/ValidationRegistry.sol";
import {IValidationRegistry} from "../src/interfaces/IValidationRegistry.sol";

contract ValidationRegistryTest is Test {
    AgentIdentityRegistry internal identity;
    ValidationRegistry internal validation;

    uint256 internal constant AGENT_OWNER_PK = 0xA11CE;
    address internal agentOwner;

    address internal stranger = address(0xCAFE);
    uint256 internal agentId;

    event ValidationSubmitted(
        uint256 indexed agentId,
        bytes32 indexed validationKey,
        address indexed submitter,
        bytes32 recommendationHash,
        bytes32 actionHash,
        bool success,
        string outcomeURI
    );

    function setUp() public {
        agentOwner = vm.addr(AGENT_OWNER_PK);
        identity = new AgentIdentityRegistry();
        validation = new ValidationRegistry(address(identity));

        vm.prank(agentOwner);
        agentId = identity.registerAgent("ipfs://agent-manifest");
    }

    // ─── happy path ────────────────────────────────────────────────

    function test_SubmitValidation_HappyPath() public {
        bytes32 recHash = keccak256("recommendation-1");
        bytes32 actionHash = bytes32(uint256(0xdeadbeef));
        bytes memory sig = _sign(AGENT_OWNER_PK, recHash);

        bytes32 expectedKey = keccak256(abi.encodePacked(agentId, recHash));

        vm.expectEmit(true, true, true, true);
        emit ValidationSubmitted(
            agentId,
            expectedKey,
            stranger,
            recHash,
            actionHash,
            true,
            "ipfs://outcome"
        );

        vm.prank(stranger);
        bytes32 key = validation.submitValidation(
            agentId, recHash, actionHash, sig, true, "ipfs://outcome"
        );

        assertEq(key, expectedKey);
        assertEq(validation.validationCount(agentId), 1);

        IValidationRegistry.Validation memory v = validation.getValidation(key);
        assertEq(v.agentId, agentId);
        assertEq(v.submitter, stranger);
        assertEq(v.recommendationHash, recHash);
        assertEq(v.actionHash, actionHash);
        assertEq(uint256(v.timestamp), block.timestamp);
        assertTrue(v.success);
    }

    function test_DeriveKey_MatchesContract() public view {
        bytes32 recHash = keccak256("anything");
        bytes32 expected = keccak256(abi.encodePacked(agentId, recHash));
        assertEq(validation.deriveKey(agentId, recHash), expected);
    }

    // ─── reverts ───────────────────────────────────────────────────

    function test_Revert_AgentNotFound() public {
        bytes32 recHash = keccak256("r");
        bytes memory sig = _sign(AGENT_OWNER_PK, recHash);

        vm.expectRevert(ValidationRegistry.AgentNotFound.selector);
        validation.submitValidation(999, recHash, bytes32(0), sig, true, "");
    }

    function test_Revert_InvalidSigner() public {
        bytes32 recHash = keccak256("r");
        // Different key signs.
        bytes memory sig = _sign(0xBADBADBAD, recHash);

        vm.expectRevert(ValidationRegistry.InvalidSigner.selector);
        validation.submitValidation(agentId, recHash, bytes32(0), sig, true, "");
    }

    function test_Revert_InvalidSignatureLength() public {
        bytes32 recHash = keccak256("r");
        bytes memory sig = new bytes(64); // too short

        vm.expectRevert(ValidationRegistry.InvalidSignatureLength.selector);
        validation.submitValidation(agentId, recHash, bytes32(0), sig, true, "");
    }

    function test_Revert_DuplicateValidation() public {
        bytes32 recHash = keccak256("r");
        bytes memory sig = _sign(AGENT_OWNER_PK, recHash);

        validation.submitValidation(agentId, recHash, bytes32(0), sig, true, "");

        vm.expectRevert(ValidationRegistry.DuplicateValidation.selector);
        validation.submitValidation(agentId, recHash, bytes32(0), sig, true, "");
    }

    function test_Revert_MalleableSignature() public {
        bytes32 recHash = keccak256("malleable");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AGENT_OWNER_PK, recHash);

        // Flip s into the upper half (n - s) and toggle v. This is the
        // classic malleability vector — the recovered address would be
        // the same, but EIP-2 forbids it.
        bytes32 nMinusS = bytes32(
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
                - uint256(s)
        );
        uint8 flippedV = v == 27 ? 28 : 27;

        bytes memory sig = abi.encodePacked(r, nMinusS, flippedV);

        vm.expectRevert(ValidationRegistry.InvalidSignature.selector);
        validation.submitValidation(agentId, recHash, bytes32(0), sig, true, "");
    }

    // ─── ownership rotation ────────────────────────────────────────

    function test_OwnershipTransfer_OldOwnerSigInvalidated() public {
        address newOwnerAddr = address(0xBEEF);

        vm.prank(agentOwner);
        identity.transferOwnership(agentId, newOwnerAddr);

        // Old owner's signature should no longer satisfy the validation.
        bytes32 recHash = keccak256("post-transfer");
        bytes memory oldSig = _sign(AGENT_OWNER_PK, recHash);

        vm.expectRevert(ValidationRegistry.InvalidSigner.selector);
        validation.submitValidation(agentId, recHash, bytes32(0), oldSig, true, "");
    }

    // ─── views ─────────────────────────────────────────────────────

    function test_GetValidation_EmptyForUnknown() public view {
        IValidationRegistry.Validation memory v = validation.getValidation(bytes32(uint256(42)));
        assertEq(uint256(v.timestamp), 0);
        assertEq(v.agentId, 0);
    }

    function test_SupportsInterface() public view {
        assertTrue(validation.supportsInterface(type(IValidationRegistry).interfaceId));
        assertTrue(validation.supportsInterface(0x01ffc9a7));
        assertFalse(validation.supportsInterface(0xffffffff));
    }

    // ─── fuzz ──────────────────────────────────────────────────────

    function testFuzz_SubmitManyRecommendations(uint8 count) public {
        uint256 n = uint256(count) % 16 + 1;
        for (uint256 i = 0; i < n; i++) {
            bytes32 rec = keccak256(abi.encode("rec", i));
            bytes memory sig = _sign(AGENT_OWNER_PK, rec);
            validation.submitValidation(agentId, rec, bytes32(i), sig, i % 2 == 0, "");
        }
        assertEq(validation.validationCount(agentId), n);
    }

    // ─── helpers ───────────────────────────────────────────────────

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
