# Development

## Prerequisites

[Mise](https://mise.jdx.dev/) installs the pinned Gleam, Erlang/OTP `27.3.4.1`, Rebar, pre-commit, and Gitleaks versions.

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

The Lustre development server is available at `http://localhost:1234` and watches `client/src/` and `client/assets/`. The household calculator remains in the browser; the current budget autosaves, while monthly contribution snapshots are recorded only when you explicitly choose a month and select **Save this month**. Archived months cannot be replaced and retain their expense details and calculation results. The history panel compares each period's expenses, balance used, contributions, and base share per person with the closest earlier archived month. The construction screen loads its history and categories from the Erlang API and saves new entries to PostgreSQL. The JavaScript client and Erlang server both use the pure domain package in `shared/`.

Run `mise run frontend:check` to format-check, type-check, and build the production browser bundle. The first build downloads Bun through Lustre Dev Tools if it is not already available.

`mise run frontend:demo` builds the static GitHub Pages demo with synthetic in-memory data. It is deployed automatically by `.github/workflows/pages.yaml` after verification on pushes to `main`, at `https://mazama923.github.io/cabanon/`. The demo does not make API requests and all changes stay in the current browser session.

## Local database

PostgreSQL 13 or newer is installed as a native operating-system service, not through Docker or Compose. Migration `0001` creates one `My Home` project and the construction history tables. Migration `0002` adds the single-household budget snapshot used by automatic household saving. Migration `0003` adds an audit history for corrected construction costs. Migration `0004` adds immutable monthly household contribution snapshots.

For local development, install PostgreSQL with the operating-system package manager, start the service, and create separate application and disposable integration-test databases. Run the migration as the owner of each database so that role can access the tables:

```sh
createuser --pwprompt cabanon_dev
createdb --owner=cabanon_dev cabanon_dev
psql --host=127.0.0.1 --username=cabanon_dev --dbname=cabanon_dev \
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0001_construction_cost_history.sql
psql --host=127.0.0.1 --username=cabanon_dev --dbname=cabanon_dev \
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0002_household_budget.sql
psql --host=127.0.0.1 --username=cabanon_dev --dbname=cabanon_dev \\
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0003_construction_cost_corrections.sql
psql --host=127.0.0.1 --username=cabanon_dev --dbname=cabanon_dev \\
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0004_household_contribution_history.sql

createuser --pwprompt cabanon_test
createdb --owner=cabanon_test cabanon_test
psql --host=127.0.0.1 --username=cabanon_test --dbname=cabanon_test \
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0001_construction_cost_history.sql
psql --host=127.0.0.1 --username=cabanon_test --dbname=cabanon_test \
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0002_household_budget.sql
psql --host=127.0.0.1 --username=cabanon_test --dbname=cabanon_test \\
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0003_construction_cost_corrections.sql
psql --host=127.0.0.1 --username=cabanon_test --dbname=cabanon_test \\
  --set=ON_ERROR_STOP=1 --file=priv/migrations/0004_household_contribution_history.sql
```

Each migration command prompts for the role's password. If earlier migrations were already applied, run only the unapplied migrations in order. Run migrations as the database/schema owner when possible. If an existing schema is owned by a different role, the migration role needs `CREATE` on the schema and `SELECT` and `INSERT` on `schema_migrations`; migration `0003` also requires `REFERENCES` on `construction_costs` and `construction_categories`. Use a URL-encoded password in the PostgreSQL connection URL if it contains reserved URL characters. Set the server environment and launch both processes together:

```sh
export CABANON_SECRET_KEY_BASE="$(openssl rand -hex 32)"
export CABANON_DATABASE_URL='postgresql://cabanon_dev:URL_ENCODED_PASSWORD@127.0.0.1:5432/cabanon_dev?sslmode=disable'
mise run dev
```

`mise run dev` starts the Erlang backend and the Lustre frontend in parallel. Open `http://localhost:1234`; press `Ctrl-C` to stop both. Development defaults to `127.0.0.1:8080` and permits only `http://localhost:1234` as the browser origin. If `CABANON_DATABASE_URL` is unset or invalid, development still starts but database-backed API requests and `/readyz` return `503`. Household changes are saved automatically after about 450 ms without typing; the page shows whether the budget is loading, saving, saved, invalid, or unavailable. Monthly history is a separate manual action and never runs as part of this autosave.

Run the repository integration tests against the separate test database. They use transactions and roll back their writes; never point the test URL at production or a database containing data you need to keep.

```sh
export CABANON_TEST_DATABASE_URL='postgresql://cabanon_test:URL_ENCODED_PASSWORD@127.0.0.1:5432/cabanon_test?sslmode=disable'
mise run test
```

`mise run test` skips the PostgreSQL persistence and API integration tests when `CABANON_TEST_DATABASE_URL` is unset. Keep PostgreSQL bound to a Unix socket or `127.0.0.1`, and do not reuse production credentials or backups.

## Build a deployable artifact

```sh
mise run package
```

This writes `dist/cabanon-erlang-shipment.tar.gz` and its SHA-256 checksum. The target host needs Debian 13 Erlang/OTP `27.3.4.1`; it does not need Gleam, Mise, Docker, or Podman.

For a complete production release bundle, use `./scripts/package-release.sh`. It includes the Erlang shipment, compiled frontend, migrations, systemd unit, installer scripts, manifest, and checksums. CI runs it after verification and security scanning: a `vMAJOR.MINOR.PATCH` tag creates a stable GitHub release, while a successful push to `main` creates a `main-<short-sha>` pre-release. Each archive is also retained as a seven-day GitHub Actions artifact. The workflow has no deployment credentials and does not deploy the artifact.

## Publish a stable release

Create annotated tags only from the reviewed commit on `main`. The CI workflow validates the tag format, verifies the source, then publishes the release asset without accessing production:

```sh
git switch main
git pull --ff-only origin main
git tag -a v1.2.3 -m "v1.2.3"
git push origin v1.2.3
```

Use only `vMAJOR.MINOR.PATCH` tags. Treat published tags as immutable; publish a new patch version for a correction.

## Production configuration

Set `CABANON_ENV=production` only through the root-owned `/etc/cabanon/cabanon.env` created by the installer. Production requires all of the following values and fails closed if the database cannot be initialized:

```text
CABANON_ENV=production
CABANON_SECRET_KEY_BASE=<random 64 hexadecimal characters>
CABANON_DATABASE_URL=postgresql://cabanon_app:<url-encoded-password>@127.0.0.1:5432/cabanon?sslmode=disable
CABANON_BIND_ADDRESS=<private Cabanon LXC address>
CABANON_PORT=8080
CABANON_ALLOWED_ORIGIN=https://cabanon.example.com
```

`CABANON_BIND_ADDRESS` must be the private address reachable only from Caddy. `CABANON_ALLOWED_ORIGIN` is the exact browser origin: it controls API CORS responses and is required on every `POST`, `PUT`, `PATCH`, and `DELETE` request. The production server serves the bundled frontend, `/healthz` reports process liveness, and `/readyz` verifies PostgreSQL connectivity.

## Quality gate

```sh
mise run format-check
mise run check
mise run frontend:check
mise run frontend:demo
mise run test
mise run security:secrets
mise run ci
```

Run `mise run format` before committing. The Git hook prevents common whitespace errors, private-key commits, and detected secrets. It is a safety net, not a replacement for reviewing diffs.

## Learning path

Start with the pure modules in `shared/src/cabanon/domain/`; they are ordinary Gleam functions with no database or HTTP dependency. Then follow `client/src/cabanon_frontend.gleam` for the Lustre model, messages, effects, automatic-save debounce, and view; `src/cabanon/web/household_api.gleam` for JSON and HTTP handling; and `src/cabanon/persistence/household_budget.gleam` for PostgreSQL queries. `mise run test` exercises the shared domain and, when configured, the PostgreSQL persistence and API integration tests; `mise run frontend:check` validates the JavaScript client.

1. write the domain type and a failing unit test;
2. implement the pure calculation;
3. add a repository interface and PostgreSQL implementation;
4. expose it through a narrow web endpoint, protect unsafe requests with the Origin guard, and retain the Pocket ID boundary for the single-user deployment;
5. add an end-to-end test only where it adds value.
