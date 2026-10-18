# Cabanon agent guide

## Purpose

Cabanon is a self-hosted household-finance application written in Gleam. It calculates joint-account contributions and tracks house-construction costs. It runs as an Erlang shipment under systemd in a Proxmox LXC. It does not use Docker, Podman, or an OCI runtime.

## Language

- Write code, comments, commit messages, and documentation in English.
- Reply to the maintainer in French unless explicitly asked otherwise.

## Non-negotiable rules

- Store every monetary value as integer cents in an `Int`. Never use floating-point values for money.
- Keep business rules in `src/cabanon/domain`. Domain modules must not import HTTP, PostgreSQL, filesystem, or environment modules.
- Keep dependencies pointing inward: web and persistence adapters may use domain modules, never the reverse.
- Treat household financial data, environment files, backups, tokens, and session secrets as sensitive.
- Never commit `.env` files, database dumps, build output, release archives, or credentials.
- Do not add Docker, Podman, Compose, or OCI configuration. Production deploys an Erlang shipment through systemd.

## Repository map

| Path | Responsibility |
| --- | --- |
| `src/cabanon/domain/` | Pure household and construction rules |
| `src/cabanon/web/` | HTTP routes and middleware |
| `src/cabanon.gleam` | Application bootstrap |
| `test/cabanon_test.gleam` | Focused unit and route tests |
| `docs/` | Architecture, data, security, development, operations |
| `infra/systemd/` | Production service and environment template |
| `scripts/package.sh` | Erlang shipment archive and checksum |

## Commands

```sh
mise install
mise run format
mise run verify
mise run ci
mise run package
```

- Use `mise run verify` for formatting, type checks, and tests.
- Use `mise run ci` before proposing a change. It also scans Git history for secrets.
- Use `mise run package` to build `dist/cabanon-erlang-shipment.tar.gz`.
- Run `mise run hooks:install` once after cloning.

## Change workflow

1. Read the closest domain module and its existing tests before editing.
2. For a business rule, add a focused failing test before implementation.
3. Make the smallest change that preserves the module boundaries.
4. Run `mise run format` and `mise run ci`.
5. Update the matching English documentation when behavior, deployment, security, or data rules change.

## Feature routing

| Change | Start here |
| --- | --- |
| Household split or expense rule | `src/cabanon/domain/household/` |
| Construction estimate or actual cost rule | `src/cabanon/domain/construction/` |
| HTTP endpoint or middleware | `src/cabanon/web/` |
| Runtime secret or bootstrap | `src/cabanon.gleam`, `src/cabanon/env.gleam` |
| Deployment or service hardening | `infra/systemd/`, `docs/operations.md`, `docs/security.md` |
| Schema or persistence | Add a persistence adapter; do not move logic out of domain modules |

## Completion checklist

- [ ] Money remains integer cents
- [ ] Domain code has no adapter dependency
- [ ] Tests cover changed behavior
- [ ] `mise run ci` passes
- [ ] No generated or sensitive file is staged
- [ ] Documentation remains in English and matches behavior
