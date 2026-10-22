# Security baseline

Cabanon processes household financial information. Treat it as sensitive even when it does not connect directly to a bank.

## Application

- Require `CABANON_SECRET_KEY_BASE` at startup; generate 64 random hexadecimal characters and keep it outside Git in `/etc/cabanon/cabanon.env` at mode `0600`.
- In production, require `CABANON_ENV=production`, `CABANON_DATABASE_URL`, `CABANON_BIND_ADDRESS`, `CABANON_PORT`, and `CABANON_ALLOWED_ORIGIN`. The application fails closed when it cannot initialize PostgreSQL.
- Cabanon is single-user and has no application-level accounts or roles. Pocket ID at the Caddy boundary authenticates the user; do not expose the application until that boundary and the Caddy-only network rule are configured.
- Every `POST`, `PUT`, `PATCH`, and `DELETE` request must carry an `Origin` exactly equal to `CABANON_ALLOWED_ORIGIN`; requests without it or with another value receive `403`. CORS response headers use the same exact origin. This guard complements, but does not replace, Pocket ID or network filtering.
- If multi-user support is added, implement application-level identity mapping and household-scoped authorization. Do not trust browser-supplied identifiers.
- Validate amounts, dates, and ownership on the server. Store money as integer cents.
- Log security-relevant events without passwords, session identifiers, database URLs, or financial descriptions.

## PostgreSQL

- Use a dedicated non-superuser application role with only the privileges it needs.
- Configure password authentication with `scram-sha-256`.
- Keep PostgreSQL on a Unix socket or `127.0.0.1`; do not publish port 5432.
- Use parameterized queries exclusively. The bundled migration script runs as PostgreSQL and applies schema changes under the non-login `cabanon_owner` role.
- Configure encrypted off-host backups and scheduled restore tests before production use. Their destination, credentials, retention, and automation are operator-specific and are not implemented by this repository.

## Delivery and host

- Pin build tools with `mise.toml` and commit `manifest.toml` after dependency changes.
- Run formatting, type checking, tests, Gitleaks, and filesystem/dependency scanning in CI. Successful pushes to `main` publish a `main-<short-sha>` pre-release with the verified release bundle; CI has no deployment credentials.
- Deploy only with the bundled `installer/install.sh` and `installer/deploy.sh`. They verify release checksums and Debian 13 OTP `27.3.4.1`, retain the prior release for rollback, and check `/readyz` after deployment.
- Run the systemd service as the dedicated `cabanon` user. Keep `/etc/cabanon/cabanon.env` owned by root with mode `0600`.
- Apply the hardening controls in `infra/systemd/cabanon.service`; do not enable `MemoryDenyWriteExecute` without testing it against the Erlang JIT.
- Configure the application LXC firewall to accept TCP/8080 only from Caddy's private IP. Allow Caddy publicly only on TCP/80 and TCP/443; Pocket ID and Caddy configuration remain operator-managed.

## Incident response minimum

1. Revoke active sessions and rotate `CABANON_SECRET_KEY_BASE` if the application host may be compromised.
2. Rotate the application database password and any backup credentials.
3. Preserve relevant logs and snapshots before rebuilding the LXC from a known-good release archive.
4. Restore data only from a backup whose restore procedure has been verified.
