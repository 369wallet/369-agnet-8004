# 369 Agent · ERC-8004 Registries

Minimal, immutable, ECDSA-verified registries for autonomous agents on
EVM chains. Inspired by the
[ERC-8004 "Trustless Agents"](https://eips.ethereum.org/EIPS/eip-8004)
draft.

Two contracts:

| Contract | Purpose |
| --- | --- |
| `AgentIdentityRegistry` | On-chain identity for autonomous agents — permissionless registration, owner-managed manifest URI, transferable ownership. |
| `ValidationRegistry`    | Append-only log linking signed agent recommendations to the on-chain actions they triggered. Anyone can submit; the agent owner's signature is enforced. |

**Status:** Testnet (Arc Testnet). Mainnet deployment pending audit.

---

## Why

When an AI agent recommends a transaction — bridge USDC, swap tokens,
revoke an allowance — the recommendation usually lives off-chain
(server logs, model outputs). There is no cryptographic proof, after
the fact, that *this agent* recommended *this action*.

These contracts close that gap:

1. **Identity** — register the agent once. The registry records the
   owning key and a manifest URI describing capabilities, version,
   operator, etc.
2. **Validation** — for each on-chain action the agent triggers, log
   a record that pairs the agent's signed recommendation hash with
   the resulting transaction hash. The agent owner's ECDSA signature
   is verified on-chain.

The result is a permissionless, append-only audit trail of agent
behaviour, queryable by anyone with the agent id.

---

## Build / Test

```bash
# Install Foundry once.
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone + bootstrap deps.
git clone https://github.com/369wallet/369-agnet-8004.git
cd 369-agnet-8004
forge install foundry-rs/forge-std --no-commit

# Compile + test.
forge build
forge test -vv
```

The test suite covers happy paths, all custom errors, ECDSA
malleability, and ownership rotation. CI runs `forge test` on every PR.

---

## Deploy

`script/Deploy.s.sol` deploys both contracts in a single broadcast.

```bash
export PRIVATE_KEY=0x...                       # deployer key
export ARC_TESTNET_RPC_URL=https://rpc.testnet.arc.network

forge script script/Deploy.s.sol:Deploy \
    --rpc-url arc_testnet \
    --broadcast \
    --slow
```

Then register the agent:

```bash
export IDENTITY_REGISTRY=0x...                 # from previous step
export METADATA_URI=https://example.com/agent-manifest.json

forge script script/RegisterAgent.s.sol:RegisterAgent \
    --rpc-url arc_testnet \
    --broadcast
```

### Deployments

| Network        | AgentIdentityRegistry | ValidationRegistry |
| -------------- | --------------------- | ------------------ |
| Arc Testnet    | _TBD_                 | _TBD_              |

Update this table in the PR that ships each deployment.

---

## Canonical recommendation hash (EIP-712)

The contract is intentionally hash-format-agnostic: `submitValidation`
verifies that *whatever* `bytes32` you signed was signed by the
agent's owner. The canonical scheme for inter-op is **EIP-712 typed
data** over the following struct:

```solidity
struct AgentRecommendation {
    uint256 agentId;
    bytes32 actionScope;   // keccak256(action name), e.g. "send", "bridge"
    bytes32 inputHash;     // keccak256 of canonical JSON input
    uint64  nonce;         // monotonic per agent
    uint64  expiresAt;     // unix seconds; 0 = no expiry
}
```

Domain separator:

```
EIP712Domain(
    string name = "369AgentRecommendation",
    string version = "1",
    uint256 chainId,
    address verifyingContract = address of ValidationRegistry
)
```

Off-chain SDKs that follow this schema interoperate; bespoke schemes
work but lose the ability to be parsed by generic tooling.

---

## Manifest format

The `metadataURI` referenced by `AgentIdentityRegistry` SHOULD resolve
to an immutable JSON document with at least these fields:

```json
{
    "name": "369 Wallet Agent",
    "version": "1.0.0",
    "operator": "0x...",
    "description": "AI agent that performs balance reads, sends, swaps, bridges, and approval revokes on behalf of a user's wallet.",
    "capabilities": [
        "sendArc",
        "bridgeQuote",
        "bridgeExecute",
        "arcSwap",
        "listApprovals",
        "revokeApproval"
    ],
    "signingKey": "0x...",
    "recommendationSchema": "eip712:369AgentRecommendation:1"
}
```

`signingKey` is the address that signs recommendations. For the V1
registries it MUST equal the agent's on-chain `owner` — the simplest
model. Future versions may permit a separate signing key delegated
from the owner.

---

## Design choices

- **Immutable, non-upgradeable.** Both contracts can be audited end
  to end; there's no proxy or admin. Fork the repo and redeploy if
  policy changes.
- **No on-chain reputation.** Reputation is a separate concern and
  belongs in a separate contract that reads from this validation log.
- **Permissionless writes.** Anyone can submit a validation provided
  the agent owner signed the recommendation hash. This lets relayers
  pay gas without privileged roles.
- **EIP-2 malleability guard.** The validation key is
  `keccak256(agentId || recommendationHash)`, so a malleable signature
  could otherwise let an attacker double-submit. The recovery path
  rejects upper-half-order `s` values.
- **Typed custom errors.** Every revert is a Solidity custom error,
  so downstream decoders branch on selectors rather than parsing
  strings.

---

## Repository layout

```
.
├── foundry.toml             — build + RPC config
├── remappings.txt           — forge-std mapping
├── src/
│   ├── interfaces/
│   │   ├── IAgentIdentityRegistry.sol
│   │   └── IValidationRegistry.sol
│   ├── AgentIdentityRegistry.sol
│   └── ValidationRegistry.sol
├── script/
│   ├── Deploy.s.sol
│   └── RegisterAgent.s.sol
├── test/
│   ├── AgentIdentityRegistry.t.sol
│   └── ValidationRegistry.t.sol
├── SECURITY.md
├── LICENSE                  — Apache-2.0
└── README.md
```

---

## License

Apache-2.0. See [LICENSE](./LICENSE).
