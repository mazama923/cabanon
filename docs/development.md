# Development

## Prerequisites

[Mise](https://mise.jdx.dev/) installs the pinned Gleam, Erlang, Rebar, pre-commit, and Gitleaks versions.

```sh
mise install
mise run hooks:install
```

Create a local secret for the HTTP session cryptography:

```sh
export CABANON_SECRET_KEY_BASE="$(openssl rand -hex 32)"
```

The application refuses to start when this value is absent. Use a unique random value for every environment.

## Local database

PostgreSQL is intentionally installed as a native operating-system service, not through Docker or Compose. It is not needed until the persistence slice is implemented.

For local development, install PostgreSQL with the operating-system package manager, start the service, and create an isolated development role and database:

```sh
createuser --pwprompt cabanon_dev
createdb --owner=cabanon_dev cabanon_dev
```

Keep the service on a Unix socket or `127.0.0.1`. Do not reuse production credentials or production backups locally.

## Build a deployable artifact

```sh
mise run package
```

This writes `dist/cabanon-erlang-shipment.tar.gz` and its SHA-256 checksum. The target host needs a compatible Erlang/OTP runtime; it does not need Gleam, Mise, Docker, or Podman.

## Quality gate

```sh
mise run format-check
mise run check
mise run test
mise run security:secrets
mise run ci
```

Run `mise run format` before committing. The Git hook prevents common whitespace errors, private-key commits, and detected secrets. It is a safety net, not a replacement for reviewing diffs.

## Learning path

Start in `src/cabanon/domain/`. The modules are ordinary Gleam functions with no database or HTTP dependency, so `gleam test` gives fast feedback. For each feature:

1. write the domain type and a failing unit test;
2. implement the pure calculation;
3. add a repository interface and PostgreSQL implementation;
4. expose it through one authenticated web endpoint;
5. add an end-to-end test only where it adds value.
