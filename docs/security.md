# Security baseline

Cabanon processes household financial information. Treat it as sensitive even when it does not connect directly to a bank.

## Application

- Require `CABANON_SECRET_KEY_BASE` at startup; generate it with at least 32 random bytes and keep it outside Git.
- Use Argon2id for password hashing when authentication is introduced. Do not implement password crypto manually.
- Use `Secure`, `HttpOnly`, and `SameSite=Lax` session cookies. Enforce HTTPS before enabling `Secure` cookies.
- Apply CSRF protection to every state-changing browser request.
- Authorize every query by `household_id`; never trust an identifier supplied by the browser without checking membership.
- Validate amounts, dates, and ownership on the server. Store money as integer cents.
- Log security-relevant events without passwords, session identifiers, database URLs, or financial descriptions.

## PostgreSQL

- Use a dedicated non-superuser application role with only the privileges it needs.
- Configure password authentication with `scram-sha-256`.
- Keep PostgreSQL on a Unix socket or `127.0.0.1`; do not publish port 5432.
- Use parameterized queries exclusively. Database migrations run through a separate, short-lived migration role.
- Encrypt backups and test restoring them on a schedule.

## Delivery and host

- Pin build tools with `mise.toml` and commit `manifest.toml` after dependency changes.
- Run formatting, type checking, tests, Gitleaks, and filesystem/dependency scanning in CI.
- Verify the archive checksum before a deployment. Transfer artifacts over SSH and retain the prior release for rollback.
- Run the systemd service as the dedicated `cabanon` user. Keep `/etc/cabanon/cabanon.env` owned by root with mode `0600`.
- Apply the hardening controls in `infra/systemd/cabanon.service`; do not enable `MemoryDenyWriteExecute` without testing it against the Erlang JIT.
- Allow the application LXC to accept TCP/8080 only from Caddy's private IP. Allow Caddy publicly only on TCP/80 and TCP/443.

## Incident response minimum

1. Revoke active sessions and rotate `CABANON_SECRET_KEY_BASE` if the application host may be compromised.
2. Rotate the application database password and any backup credentials.
3. Preserve relevant logs and snapshots before rebuilding the LXC from a known-good release archive.
4. Restore data only from a backup whose restore procedure has been verified.
