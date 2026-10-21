# Cabanon agent guide

## Purpose

Cabanon is a self-hosted household-finance application written in Gleam. A Lustre client targets JavaScript, while the Erlang server and browser client share pure domain rules from the `shared/` package. The server runs as an Erlang shipment under systemd in a Proxmox LXC. It does not use Docker, Podman, or an OCI runtime.

## Language

- Write code, comments, commit messages, and documentation in English.
- Reply to the maintainer in French unless explicitly asked otherwise.

## Non-negotiable rules

- Store every monetary value as integer cents in an `Int`. Never use floating-point values for money.
- Keep business rules in `shared/src/cabanon/domain`. Domain modules must not import HTTP, PostgreSQL, filesystem, or environment modules.
- Keep dependencies pointing inward: web and persistence adapters may use domain modules, never the reverse.
- Treat household financial data, environment files, backups, tokens, and session secrets as sensitive.
- Never commit `.env` files, database dumps, build output, release archives, or credentials.
- Do not add Docker, Podman, Compose, or OCI configuration. Production deploys an Erlang shipment through systemd.

## Repository map

| Path | Responsibility |
| --- | --- |
| `shared/src/cabanon/domain/` | Pure household and construction rules shared by Erlang and JavaScript |
| `client/src/` | Lustre browser application targeting JavaScript |
| `client/assets/` | Frontend CSS and static assets |
| `src/cabanon/web/` | Erlang HTTP routes and middleware |
| `src/cabanon/persistence/` | Erlang-targeted database adapters |
| `priv/migrations/` | PostgreSQL schema migrations |
| `src/cabanon.gleam` | Erlang server bootstrap |
| `test/` | Domain, route, and optional PostgreSQL integration tests |
| `docs/` | Architecture, data, security, development, operations |
| `infra/systemd/` | Production service and environment template |
| `scripts/package.sh` | Erlang shipment archive and checksum |

## Commands

```sh
mise install
mise run format
mise run verify
mise run ci
mise run frontend:check
mise run frontend:run
mise run package
```

- Use `mise run verify` for formatting, type checks, tests, and the frontend bundle build.
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
| Household split or expense rule | `shared/src/cabanon/domain/household/` |
| Construction estimate or actual cost rule | `shared/src/cabanon/domain/construction/` |
| Lustre UI or browser interaction | `client/src/`, with rules imported from `shared/` |
| HTTP endpoint or middleware | `src/cabanon/web/` |
| Runtime secret or bootstrap | `src/cabanon.gleam`, `src/cabanon/env.gleam` |
| Deployment or service hardening | `infra/systemd/`, `docs/operations.md`, `docs/security.md` |
| Schema or persistence | Add a persistence adapter; do not move logic out of domain modules |

## Completion checklist

- [ ] Money remains integer cents
- [ ] Domain code has no adapter dependency
- [ ] Browser and server use the shared domain package rather than duplicate rules
- [ ] Tests cover changed behavior
- [ ] `mise run ci` passes
- [ ] No generated or sensitive file is staged
- [ ] Documentation remains in English and matches behavior
