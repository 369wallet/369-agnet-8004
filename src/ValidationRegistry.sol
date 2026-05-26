// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {IAgentIdentityRegistry} from "./interfaces/IAgentIdentityRegistry.sol";
import {IValidationRegistry} from "./interfaces/IValidationRegistry.sol";

/// @title  ValidationRegistry
/// @author 369 Wallet
/// @notice Append-only log of validated agent actions.
/// @dev    Each entry binds (a) a recommendation digest the agent signed
///         with its owner key and (b) the on-chain action that resulted.
///         Anyone can witness — gas is whoever submits — but the
///         recommendation MUST carry a valid ECDSA signature from the
///         agent's current owner, so the log is permissionless to write
///         yet cryptographically scoped to one identity per `agentId`.
///
///         The contract is intentionally hash-format-agnostic. The
///         canonical scheme is EIP-712 typed-data over the
///         AgentRecommendation struct documented in the project README;
///         keeping that off-chain means new schema versions don't
///         require a new registry deploy.
///
///         Storage layout:
///           validations[validationKey] => Validation
///           validationCount[agentId]   => uint256
///         Both are append-only; there is no revoke / clear path.
contract ValidationRegistry is IValidationRegistry {
    /// @notice Semver-ish version string for off-chain reflection.
    string public constant VERSION = "1.0.0";

    /// @notice The identity registry this validation log binds to.
    ///         Set at construction, immutable for the contract's lifetime.
    IAgentIdentityRegistry public immutable identity;

    /// @dev validationKey => Validation. Keys are `keccak256(agentId || recHash)`.
    mapping(bytes32 => Validation) private _validations;

    /// @inheritdoc IValidationRegistry
    mapping(uint256 => uint256) public override validationCount;

    /// @notice Reverts thrown by this contract. Custom errors so off-chain
    ///         decoders can branch on the failure mode without parsing strings.
    error AgentNotFound();
    error DuplicateValidation();
    error InvalidSignatureLength();
    error InvalidSignature();
    error InvalidSigner();

    /// @param identityRegistry Deployed AgentIdentityRegistry. Cannot be
    ///                         changed after construction — fork to point
    ///                         at a different identity layer.
    constructor(address identityRegistry) {
        identity = IAgentIdentityRegistry(identityRegistry);
    }

    /// @inheritdoc IValidationRegistry
    function submitValidation(
        uint256 agentId,
        bytes32 recommendationHash,
        bytes32 actionHash,
        bytes calldata agentSignature,
        bool success,
        string calldata outcomeURI
    ) external returns (bytes32 validationKey) {
        IAgentIdentityRegistry.Agent memory agent = identity.getAgent(agentId);
        if (agent.owner == address(0)) revert AgentNotFound();

        address signer = _recoverSigner(recommendationHash, agentSignature);
        if (signer != agent.owner) revert InvalidSigner();

        validationKey = keccak256(abi.encodePacked(agentId, recommendationHash));
        if (_validations[validationKey].timestamp != 0) revert DuplicateValidation();

        _validations[validationKey] = Validation({
            agentId: agentId,
            submitter: msg.sender,
            recommendationHash: recommendationHash,
            actionHash: actionHash,
            timestamp: uint64(block.timestamp),
            success: success
        });
        unchecked {
            validationCount[agentId] += 1;
        }

        emit ValidationSubmitted(
            agentId,
            validationKey,
            msg.sender,
            recommendationHash,
            actionHash,
            success,
            outcomeURI
        );
    }

    /// @inheritdoc IValidationRegistry
    function getValidation(bytes32 validationKey) external view returns (Validation memory) {
        return _validations[validationKey];
    }

    /// @inheritdoc IValidationRegistry
    function deriveKey(uint256 agentId, bytes32 recommendationHash)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(agentId, recommendationHash));
    }

    /// @notice ERC-165 interface detection.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IValidationRegistry).interfaceId
            || interfaceId == 0x01ffc9a7;
    }

    /// @dev Inline ECDSA recovery. Accepts standard 65-byte (r,s,v)
    ///      signatures and tolerates v in {0,1,27,28}. Rejects the
    ///      malleable upper-half-order s per EIP-2 — the contract
    ///      MUST NOT accept both (r,s,v) and (r,n-s,v^1) as the same
    ///      signature, since validationKey would otherwise be replayable.
    function _recoverSigner(bytes32 digest, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) revert InvalidSignatureLength();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 0x20))
            v := byte(0, calldataload(add(sig.offset, 0x40)))
        }
        // EIP-2 malleability guard: secp256k1n / 2.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }
        if (v < 27) {
            unchecked { v += 27; }
        }
        if (v != 27 && v != 28) revert InvalidSignature();
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
        return signer;
    }
}
