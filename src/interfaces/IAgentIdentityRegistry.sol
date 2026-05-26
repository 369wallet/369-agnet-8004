// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

/// @title  IAgentIdentityRegistry
/// @author 369 Wallet
/// @notice ERC-8004 inspired identity registry for autonomous agents.
/// @dev    Single source of truth for "who is agent N." Permissionless to
///         register; ownership is on-chain, transferable, and revocable
///         by the current owner only. Off-chain manifests are referenced
///         by URI — implementers SHOULD use immutable storage (ipfs://,
///         arweave://, or content-addressed https) so the URI's bytes
///         alone uniquely commit to the agent's capabilities.
interface IAgentIdentityRegistry {
    struct Agent {
        address owner;
        uint64 registeredAt;
        string metadataURI;
    }

    /// @notice Emitted exactly once per agent, at registration.
    event AgentRegistered(uint256 indexed agentId, address indexed owner, string metadataURI);

    /// @notice Emitted whenever an agent's owner replaces the manifest URI.
    event MetadataUpdated(uint256 indexed agentId, string metadataURI);

    /// @notice Emitted when an agent's ownership transfers.
    event OwnershipTransferred(uint256 indexed agentId, address indexed from, address indexed to);

    /// @notice Registers a new agent owned by `msg.sender`.
    /// @param  metadataURI Off-chain pointer to the agent manifest (https / ipfs / arweave).
    ///                     MUST be non-empty.
    /// @return agentId The newly minted agent id (1-indexed, strictly monotonic).
    function registerAgent(string calldata metadataURI) external returns (uint256 agentId);

    /// @notice Replaces an agent's manifest URI. MUST revert unless
    ///         `msg.sender == owner(agentId)`.
    function updateMetadata(uint256 agentId, string calldata metadataURI) external;

    /// @notice Transfers ownership of an agent. MUST revert unless
    ///         `msg.sender == owner(agentId)` and `newOwner != address(0)`.
    function transferOwnership(uint256 agentId, address newOwner) external;

    /// @notice Returns the full agent record. Returns an empty struct
    ///         (`owner == address(0)`) for unknown ids.
    function getAgent(uint256 agentId) external view returns (Agent memory);

    /// @notice Returns true iff the agent has ever been registered.
    function exists(uint256 agentId) external view returns (bool);

    /// @notice The next id `registerAgent` will assign.
    function nextId() external view returns (uint256);
}
