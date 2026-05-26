// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

/// @title  IValidationRegistry
/// @author 369 Wallet
/// @notice Append-only log of agent actions, each cryptographically
///         linked to the recommendation that triggered them.
/// @dev    The contract is permissionless to write to. Trust is enforced
///         via the ECDSA signature on `recommendationHash`: the signer
///         MUST be the current owner of `agentId` (per the identity
///         registry the validation registry was constructed with).
///
///         The chosen hashing scheme is the writer's responsibility.
///         The canonical scheme is EIP-712 typed-data over the
///         AgentRecommendation struct defined in the project README;
///         the contract itself stays format-agnostic so future schema
///         revisions don't require a new validation registry.
interface IValidationRegistry {
    struct Validation {
        uint256 agentId;
        address submitter;
        bytes32 recommendationHash;
        bytes32 actionHash;
        uint64 timestamp;
        bool success;
    }

    /// @notice Emitted on every successful `submitValidation`.
    event ValidationSubmitted(
        uint256 indexed agentId,
        bytes32 indexed validationKey,
        address indexed submitter,
        bytes32 recommendationHash,
        bytes32 actionHash,
        bool success,
        string outcomeURI
    );

    /// @notice Records a validated agent action.
    /// @param  agentId            On-chain agent identifier.
    /// @param  recommendationHash 32-byte digest the agent signed.
    /// @param  actionHash         Resulting on-chain transaction hash
    ///                            (or any 32-byte off-chain action id).
    /// @param  agentSignature     65-byte ECDSA signature over
    ///                            `recommendationHash` produced by the
    ///                            current owner of `agentId`.
    /// @param  success            Whether the action completed successfully.
    /// @param  outcomeURI         Optional off-chain pointer to a richer
    ///                            outcome record (logs, receipts). MAY be empty.
    /// @return validationKey      `keccak256(agentId || recommendationHash)`.
    function submitValidation(
        uint256 agentId,
        bytes32 recommendationHash,
        bytes32 actionHash,
        bytes calldata agentSignature,
        bool success,
        string calldata outcomeURI
    ) external returns (bytes32 validationKey);

    /// @notice Returns a previously-recorded validation. Returns an
    ///         empty struct (`timestamp == 0`) for unknown keys.
    function getValidation(bytes32 validationKey) external view returns (Validation memory);

    /// @notice The total number of validations recorded for an agent.
    function validationCount(uint256 agentId) external view returns (uint256);

    /// @notice Pure helper: derive the canonical validation key the
    ///         same way the contract does.
    function deriveKey(uint256 agentId, bytes32 recommendationHash)
        external
        pure
        returns (bytes32);
}
