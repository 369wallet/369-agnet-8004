// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.26;

import {IAgentIdentityRegistry} from "./interfaces/IAgentIdentityRegistry.sol";

/// @title  AgentIdentityRegistry
/// @author 369 Wallet
/// @notice On-chain registry of autonomous agents, modelled on the
///         ERC-8004 "Trustless Agents" identity layer.
/// @dev    Permissionless registration. Each agent gets a monotonically
///         increasing id (1-indexed) and stores its owner + an off-chain
///         manifest URI. No upgradeability and no admin role — deploy
///         once, fork if a different policy is needed.
///
///         All state-changing functions revert with typed errors so
///         downstream tooling can branch on the failure mode without
///         parsing strings.
contract AgentIdentityRegistry is IAgentIdentityRegistry {
    /// @notice Semver-ish version string. Bump on every breaking on-chain
    ///         schema change so off-chain consumers can detect deploys.
    string public constant VERSION = "1.0.0";

    /// @notice Sequential id counter. Reads as the id that will be
    ///         assigned by the next `registerAgent`.
    uint256 private _nextId = 1;

    /// @dev Storage layout: tightly packed where possible (owner +
    ///      registeredAt share a slot via uint64).
    mapping(uint256 => Agent) private _agents;

    /// @notice Reverts thrown by this contract. Listed here for the
    ///         convenience of off-chain decoders.
    error MetadataRequired();
    error AgentNotFound();
    error NotOwner();
    error ZeroAddress();

    /// @inheritdoc IAgentIdentityRegistry
    function registerAgent(string calldata metadataURI) external returns (uint256 agentId) {
        if (bytes(metadataURI).length == 0) revert MetadataRequired();
        unchecked {
            agentId = _nextId++;
        }
        _agents[agentId] = Agent({
            owner: msg.sender,
            registeredAt: uint64(block.timestamp),
            metadataURI: metadataURI
        });
        emit AgentRegistered(agentId, msg.sender, metadataURI);
    }

    /// @inheritdoc IAgentIdentityRegistry
    function updateMetadata(uint256 agentId, string calldata metadataURI) external {
        Agent storage a = _agents[agentId];
        if (a.owner == address(0)) revert AgentNotFound();
        if (a.owner != msg.sender) revert NotOwner();
        if (bytes(metadataURI).length == 0) revert MetadataRequired();
        a.metadataURI = metadataURI;
        emit MetadataUpdated(agentId, metadataURI);
    }

    /// @inheritdoc IAgentIdentityRegistry
    function transferOwnership(uint256 agentId, address newOwner) external {
        Agent storage a = _agents[agentId];
        if (a.owner == address(0)) revert AgentNotFound();
        if (a.owner != msg.sender) revert NotOwner();
        if (newOwner == address(0)) revert ZeroAddress();
        address prev = a.owner;
        a.owner = newOwner;
        emit OwnershipTransferred(agentId, prev, newOwner);
    }

    /// @inheritdoc IAgentIdentityRegistry
    function getAgent(uint256 agentId) external view returns (Agent memory) {
        return _agents[agentId];
    }

    /// @inheritdoc IAgentIdentityRegistry
    function exists(uint256 agentId) external view returns (bool) {
        return _agents[agentId].owner != address(0);
    }

    /// @inheritdoc IAgentIdentityRegistry
    function nextId() external view returns (uint256) {
        return _nextId;
    }

    /// @notice ERC-165 interface support. Lets downstream contracts
    ///         (validation registry, reputation, etc.) detect this
    ///         contract's shape without trusting the address out of band.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        // type(IAgentIdentityRegistry).interfaceId
        return interfaceId == type(IAgentIdentityRegistry).interfaceId
            // ERC-165 itself
            || interfaceId == 0x01ffc9a7;
    }
}
