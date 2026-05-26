# Security Policy

## Reporting a Vulnerability

Please **do not** open a public issue for security-impacting bugs.

Email security reports to **security@369.fi** with:

- A description of the issue and its impact.
- A reproducer (Foundry test, transaction trace, or step list).
- Whether the issue affects deployed contracts; if so, which network and address.

You'll get an acknowledgement within 72 hours. We aim to ship a fix
or coordinated disclosure plan within 14 days for any contract-level
issue affecting a production deployment.

## Scope

In scope:
- `src/AgentIdentityRegistry.sol`
- `src/ValidationRegistry.sol`
- Interfaces and deploy scripts under `src/interfaces/` and `script/`.

Out of scope:
- Off-chain agent manifests referenced by `metadataURI`. These are
  the responsibility of the agent operator.
- Front-end integrations consuming the registry. Open issues against
  those repositories directly.

## Supported Versions

Only the contracts at the latest tagged release receive security
patches. The registries are immutable once deployed — fixes mean a
new deploy + community migration, not an upgrade in place. Stay
subscribed to releases on this repository.

## Known Tradeoffs

- **No upgradeability.** Both registries are non-upgradeable by
  design. A vulnerability requires a fresh deploy; off-chain
  consumers must follow the new address.
- **Append-only validation log.** Submitted validations cannot be
  edited or withdrawn. If a recommendation is later found to be
  bad, the agent owner should rotate ownership (which invalidates
  future signatures) and publish the rotation off-chain.
- **No on-chain revocation.** There is no on-chain "delist" path
  for an agent. Owners can transfer ownership to `address(0xdead)`
  as a soft delete; that pattern is not blessed by the contract but
  is permitted.
