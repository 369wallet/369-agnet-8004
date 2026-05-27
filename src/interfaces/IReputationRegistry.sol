// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

/// @title  IReputationRegistry
/// @author 369 Wallet
/// @notice Per-agent reputation aggregator built on top of the
///         ValidationRegistry. Every recorded validation MAY be
///         scored exactly once by the address that submitted it
///         (the user whose device experienced the outcome). The
///         contract aggregates those binary signals into a running
///         {favorable, unfavorable, lastUpdate} tuple per agent.
/// @dev    Reputation is intentionally scoped to outcomes the SAME
///         party who triggered the action attests to — preventing
///         drive-by raters and Sybil aggregations without resorting
///         to staking, identity, or off-chain oracles. The score
///         (favorable / total) is left to the caller because
///         different consumers want different smoothing (raw,
///         time-decayed, weighted).
///
///         Storage layout:
///           reputation[agentId]            => Reputation
///           hasFeedback[validationKey]     => bool
///         Both are append-only; there is no revoke / clear path.
interface IReputationRegistry {
    /// @notice Aggregate state for one agent.
    /// @dev    Counters are uint64 each — at one feedback per second
    ///         it would take ~585 years to overflow either side. The
    ///         contract uses unchecked increments accordingly.
    struct Reputation {
        uint64 favorable;
        uint64 unfavorable;
        uint64 lastUpdate;
    }

    /// @notice The kind of feedback being recorded. Binary on purpose:
    ///         arbitrary scores invite gaming and complicate aggregation,
    ///         while a single bit per outcome is hard to fake and easy
    ///         to roll up.
    enum FeedbackKind {
        FAVORABLE,
        UNFAVORABLE
    }

    /// @notice Emitted exactly once per validationKey, on first scoring.
    /// @param  agentId        The agent the feedback targets.
    /// @param  validationKey  ValidationRegistry key being scored.
    /// @param  rater          msg.sender — required to equal the
    ///                        ValidationRegistry record's `submitter`.
    /// @param  kind           FAVORABLE or UNFAVORABLE.
    /// @param  outcomeURI     Optional off-chain pointer to a richer
    ///                        outcome record (logs, receipts, dispute
    ///                        artifact). MAY be empty.
    event FeedbackRecorded(
        uint256 indexed agentId,
        bytes32 indexed validationKey,
        address indexed rater,
        FeedbackKind kind,
        string outcomeURI
    );

    /// @notice Records a single rating against an existing validation.
    /// @dev    MUST revert when:
    ///           - the validationKey does not exist in the bound
    ///             ValidationRegistry, OR
    ///           - msg.sender != the validation's submitter, OR
    ///           - feedback has already been recorded for this key.
    /// @param  validationKey  The key returned by ValidationRegistry.
    /// @param  kind           FAVORABLE or UNFAVORABLE.
    /// @param  outcomeURI     Optional off-chain detail. MAY be empty.
    function recordFeedback(
        bytes32 validationKey,
        FeedbackKind kind,
        string calldata outcomeURI
    ) external;

    /// @notice Returns the aggregate counters for an agent. Returns
    ///         a zero struct for an agent with no feedback yet.
    function getReputation(uint256 agentId) external view returns (Reputation memory);

    /// @notice Returns true iff the validationKey has already been scored.
    function hasFeedback(bytes32 validationKey) external view returns (bool);
}
