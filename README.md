# Cabanon

Cabanon is a self-hosted household-finance application written in Gleam.

It helps a household to:

- track recurring and exceptional household expenses;
- calculate a fair contribution to the joint account for each resident;
- keep a detailed history of actual costs for a house-construction project.

The application is deliberately a modular monolith: simple to learn, deploy, back up, and evolve without distributed-system overhead.

## Status

The repository contains an Erlang HTTP server, a Lustre browser client, shared pure domain rules, and PostgreSQL-backed household and construction-cost storage. The production release bundles the frontend and serves it from the Erlang application. Production configuration requires an explicit private bind address, port, browser origin, database URL, and session secret; the service exposes `/healthz` for liveness and `/readyz` for database readiness.

Cabanon is a single-user application behind a Pocket ID-protected Caddy boundary. It has no application-level accounts or roles: Caddy and Pocket ID configuration are operator-managed and must be in place before public exposure. State-changing requests require an exact `Origin` match, and the application listens on its configured private bind address; the operator must restrict its firewall to Caddy.

## Quick start

```sh
mise install
mise run hooks:install
export CABANON_SECRET_KEY_BASE="$(openssl rand -hex 32)"
mise run run
curl http://127.0.0.1:8080/healthz
```

`CABANON_SECRET_KEY_BASE` is mandatory for the Erlang server. Keep the generated value in a secret manager or a root-owned environment file; never commit it.

For the browser calculator, run `mise run frontend:run` in another terminal and open `http://localhost:1234`. Its in-memory data resets when the page reloads.

## Public demo

The static demo is published at [https://mazama923.github.io/cabanon/](https://mazama923.github.io/cabanon/) after successful verification on `main`. It uses synthetic in-memory data only; it never connects to the self-hosted server, PostgreSQL, or household financial data.

## Development commands

```sh
mise run format
mise run check
mise run test
mise run verify
mise run frontend:check
mise run frontend:demo
mise run frontend:run
mise run package
mise run ci
mise tasks
```

`mise run package` creates an Erlang shipment archive in `dist/` for local packaging checks. Production releases are built by `scripts/package-release.sh` in CI and published as `main-<short-sha>` GitHub pre-releases, including the frontend, migrations, systemd unit, and installer scripts. The Debian 13 target needs Erlang/OTP `27.3.4.1`, but not Gleam, Mise, Docker, or Podman.

See [Development](docs/development.md) for the local PostgreSQL workflow and [Operations](docs/operations.md) for installer-based deployment and the remaining operator responsibilities.

## Repository layout

```text
client/
  src/             Lustre application targeting JavaScript
  assets/          Frontend styles and static assets
shared/src/
  cabanon/domain/  Pure household and construction rules for both targets
src/cabanon/
  web/             Erlang HTTP routing and middleware
  persistence/     Erlang-targeted database adapters
  env.gleam        Small boundary for mandatory runtime configuration
priv/migrations/   PostgreSQL schema migrations
src/cabanon.gleam  Erlang server bootstrap
test/              Domain, route, and optional PostgreSQL integration tests
docs/              Product, architecture, security, and operations decisions
infra/systemd/     systemd service and runtime environment template
scripts/           Release packaging scripts
```

## Design principles

- Store money as integer cents; never use floating-point amounts.
- Keep business rules independent from HTTP and PostgreSQL.
- Use PostgreSQL as the source of truth; no financial record is silently deleted.
- Expose only Caddy to the Internet; Pocket ID is the single-user authentication boundary, while PostgreSQL stays on loopback in the application LXC.
- Ship an immutable release bundle supervised by systemd; configure encrypted off-host backups and restore tests before production use.

## Contributor instructions

Read [AGENTS.md](AGENTS.md) before changing the repository. It gives a compact task map, non-negotiable financial rules, commands, deployment constraints, and a completion checklist suitable for both humans and coding agents.

## Documentation

- [Architecture](docs/architecture.md)
- [Data model](docs/data-model.md)
- [Development](docs/development.md)
- [Security](docs/security.md)
- [Production operations](docs/operations.md)
- [Self-hosting guide](docs/self-hosting.md)
