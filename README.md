# Cabanon

Cabanon is a self-hosted household-finance application written in Gleam.

It helps a household to:

- track recurring and exceptional household expenses;
- calculate a fair contribution to the joint account for each resident;
- keep a detailed history of actual costs for a house-construction project.

The application is deliberately a modular monolith: simple to learn, deploy, back up, and evolve without distributed-system overhead.

## Status

The repository contains an Erlang HTTP server, a Lustre browser client with in-memory household and construction-cost screens, a shared pure domain package, and a PostgreSQL migration plus construction-cost storage adapter. The client can calculate equal household contributions and record actual construction costs by date, description, and category, with totals by category. The browser is not connected to the storage adapter yet, so client data still resets on reload. Authentication, the HTTP API, and serving the production client bundle remain future slices.

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

## Development commands

```sh
mise run format
mise run check
mise run test
mise run verify
mise run frontend:check
mise run frontend:run
mise run package
mise run ci
mise tasks
```

`mise run package` creates an Erlang shipment archive in `dist/`. Deploy it directly to the application LXC; the target needs Erlang/OTP, but not Gleam, Mise, Docker, or Podman.

See [Development](docs/development.md) for the local PostgreSQL workflow and [Operations](docs/operations.md) for the direct systemd deployment model.

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
- Expose only Caddy to the Internet; PostgreSQL stays on loopback in the application LXC.
- Ship a small Erlang release archive supervised by systemd, with explicit backups and restore tests.

## Contributor instructions

Read [AGENTS.md](AGENTS.md) before changing the repository. It gives a compact task map, non-negotiable financial rules, commands, deployment constraints, and a completion checklist suitable for both humans and coding agents.

## Documentation

- [Architecture](docs/architecture.md)
- [Data model](docs/data-model.md)
- [Development](docs/development.md)
- [Security](docs/security.md)
- [Production operations](docs/operations.md)
