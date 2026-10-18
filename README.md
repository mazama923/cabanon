# Cabanon

Cabanon is a self-hosted household-finance application written in Gleam.

It helps a household to:

- track recurring and exceptional household expenses;
- calculate a fair contribution to the joint account for each resident;
- track estimates, commitments, and actual costs for a house-construction project.

The application is deliberately a modular monolith: simple to learn, deploy, back up, and evolve without distributed-system overhead.

## Status

The repository contains the secure application foundation: a Gleam HTTP server, health endpoint, pure domain calculations, unit tests, development tooling, and operations documentation. Authentication, persistence, and the user interface are the next vertical slices.

## Quick start

```sh
mise install
mise run hooks:install
export CABANON_SECRET_KEY_BASE="$(openssl rand -hex 32)"
mise run run
curl http://127.0.0.1:8080/healthz
```

`CABANON_SECRET_KEY_BASE` is mandatory. Keep the generated value in a secret manager or a root-owned environment file; never commit it.

## Development commands

```sh
mise run format
mise run check
mise run test
mise run verify
mise run package
mise run ci
mise tasks
```

`mise run package` creates an Erlang shipment archive in `dist/`. Deploy it directly to the application LXC; the target needs Erlang/OTP, but not Gleam, Mise, Docker, or Podman.

See [Development](docs/development.md) for the local PostgreSQL workflow and [Operations](docs/operations.md) for the direct systemd deployment model.

## Repository layout

```text
src/cabanon/
  domain/          Pure household and construction rules
  web/             HTTP routing and middleware
  env.gleam        Small boundary for mandatory runtime configuration
src/cabanon.gleam  Application bootstrap
test/              Domain unit tests
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
