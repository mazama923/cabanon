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

## Frontend development

The Lustre frontend is a separate Gleam package in `client/`, compiled for JavaScript. The root package remains the Erlang server.

```sh
mise run frontend:run
```

The Lustre development server is available at `http://localhost:1234` and watches `client/src/` and `client/assets/`. The in-memory browser app has a household calculator and a construction-cost history. It supports custom household expense rows, a configurable household size, equal contributions after applying the available account balance, and construction entries with a date, description, category, and amount. Construction totals update by category, and users can add categories. All client data resets when the page reloads. The JavaScript client and Erlang server both use the pure domain package in `shared/`. No database is needed for frontend development.

Run `mise run frontend:check` to format-check, type-check, and build the browser bundle. The first build downloads Bun through Lustre Dev Tools if it is not already available.

## Local database

PostgreSQL 13 or newer is installed as a native operating-system service, not through Docker or Compose. The first migration creates one `My Home` project, the initial construction categories, and the actual-cost history tables.

For local development, install PostgreSQL with the operating-system package manager, start the service, and create a dedicated disposable integration-test database:

```sh
createuser --pwprompt cabanon_test
createdb --owner=cabanon_test cabanon_test
psql --dbname=cabanon_test --set=ON_ERROR_STOP=1 --file=priv/migrations/0001_construction_cost_history.sql
```

Run the repository integration test by setting a local connection URL. The test wraps its writes in a transaction and rolls them back. Use a dedicated test database; never point the test URL at production or a database containing data you need to keep.

```sh
export CABANON_TEST_DATABASE_URL='postgresql://cabanon_test:URL_ENCODED_PASSWORD@127.0.0.1:5432/cabanon_test?sslmode=disable'
mise run test
```

`mise run test` skips only the PostgreSQL integration test when `CABANON_TEST_DATABASE_URL` is unset. Keep the service bound to a Unix socket or `127.0.0.1`, and do not reuse production credentials or backups. The current HTTP server and browser client are not yet wired to this repository.

## Build a deployable artifact

```sh
mise run package
```

This writes `dist/cabanon-erlang-shipment.tar.gz` and its SHA-256 checksum. The target host needs a compatible Erlang/OTP runtime; it does not need Gleam, Mise, Docker, or Podman.

## Quality gate

```sh
mise run format-check
mise run check
mise run frontend:check
mise run test
mise run security:secrets
mise run ci
```

Run `mise run format` before committing. The Git hook prevents common whitespace errors, private-key commits, and detected secrets. It is a safety net, not a replacement for reviewing diffs.

## Learning path

Start with the pure modules in `shared/src/cabanon/domain/`; they are ordinary Gleam functions with no database or HTTP dependency. Then follow `src/cabanon/persistence/construction_costs.gleam` for the PostgreSQL adapter and `client/src/cabanon_frontend.gleam` for the Lustre model, messages, update function, and view. `mise run test` exercises the shared domain and, when configured, the PostgreSQL repository; `mise run frontend:check` validates the JavaScript client.

1. write the domain type and a failing unit test;
2. implement the pure calculation;
3. add a repository interface and PostgreSQL implementation;
4. expose it through one authenticated web endpoint;
5. add an end-to-end test only where it adds value.
