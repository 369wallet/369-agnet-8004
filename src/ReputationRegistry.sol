// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {IValidationRegistry} from "./interfaces/IValidationRegistry.sol";
import {IReputationRegistry} from "./interfaces/IReputationRegistry.sol";

/// @title  ReputationRegistry
/// @author 369 Wallet
/// @notice Aggregates per-agent reputation from binary user feedback
///         attached to existing ValidationRegistry records.
/// @dev    The trust model: only the address that submitted a
///         validation (i.e. the user whose device executed the
///         agent's recommendation) can rate that validation. This
///         binds reputation to lived outcomes without staking,
///         oracles, or identity layers.
///
///         The contract is hash-format-agnostic — it reads keys
///         straight from the bound ValidationRegistry rather than
///         re-deriving them. New recommendation schemas don't require
///         a redeploy of this contract.
///
///         Storage layout:
///           validation                     => immutable ref
///           _reputation[agentId]           => Reputation
///           _hasFeedback[validationKey]    => bool
///         Both maps are append-only.
contract ReputationRegistry is IReputationRegistry {
    /// @notice Semver-ish version string for off-chain reflection.
    string public constant VERSION = "1.0.0";

    /// @notice The validation registry this reputation log binds to.
    ///         Set at construction, immutable for the contract's lifetime.
    IValidationRegistry public immutable validation;

    /// @dev agentId => running counters.
    mapping(uint256 => Reputation) private _reputation;

    /// @dev validationKey => has the submitter scored this validation yet.
    mapping(bytes32 => bool) private _hasFeedback;

    /// @notice Custom errors so off-chain decoders can branch on the
    ///         failure mode without parsing strings.
    error UnknownValidation();
    error NotSubmitter();
    error AlreadyScored();

    /// @param validationRegistry Deployed ValidationRegistry. Cannot
    ///                           be changed after construction — fork
    ///                           to point at a different validation layer.
    constructor(address validationRegistry) {
        validation = IValidationRegistry(validationRegistry);
    }

    /// @inheritdoc IReputationRegistry
    function recordFeedback(
        bytes32 validationKey,
        FeedbackKind kind,
        string calldata outcomeURI
    ) external {
        IValidationRegistry.Validation memory v = validation.getValidation(validationKey);
        if (v.timestamp == 0) revert UnknownValidation();
        if (v.submitter != msg.sender) revert NotSubmitter();
        if (_hasFeedback[validationKey]) revert AlreadyScored();

        _hasFeedback[validationKey] = true;

        Reputation storage r = _reputation[v.agentId];
        unchecked {
            if (kind == FeedbackKind.FAVORABLE) {
                r.favorable += 1;
            } else {
                r.unfavorable += 1;
            }
        }
        r.lastUpdate = uint64(block.timestamp);

        emit FeedbackRecorded(v.agentId, validationKey, msg.sender, kind, outcomeURI);
    }

    /// @inheritdoc IReputationRegistry
    function getReputation(uint256 agentId) external view returns (Reputation memory) {
        return _reputation[agentId];
    }

    /// @inheritdoc IReputationRegistry
    function hasFeedback(bytes32 validationKey) external view returns (bool) {
        return _hasFeedback[validationKey];
    }

    /// @notice ERC-165 interface detection.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IReputationRegistry).interfaceId
            || interfaceId == 0x01ffc9a7;
    }
}
