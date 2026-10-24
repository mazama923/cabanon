# Production operations

## Deployment topology

- **Caddy and Pocket ID LXC**: public reverse proxy, TLS termination, access logs, and the single-user authentication boundary.
- **Application LXC**: systemd-managed Cabanon release, listening on its configured private `CABANON_BIND_ADDRESS:CABANON_PORT` and serving both the API and packaged frontend.
- **PostgreSQL**: native service in the application LXC, accessed only over `127.0.0.1` with a dedicated role.

Cabanon has no application-level accounts or roles. A production deployment must configure Pocket ID to authenticate the single user before Caddy proxies requests to the application. The application rejects unsafe requests unless their `Origin` exactly matches `CABANON_ALLOWED_ORIGIN`; the network firewall must allow TCP/8080 only from Caddy's private address.

## Application LXC bootstrap

Install from a downloaded and extracted `main-<short-sha>` GitHub pre-release on a Debian 13 LXC. Run the bundled interactive installer as root:

```sh
sudo ./installer/install.sh
```

The installer verifies the bundle checksums and Debian 13 OTP `27.3.4.1`, installs Erlang and PostgreSQL, configures local-only PostgreSQL with SCRAM authentication, writes `/etc/cabanon/cabanon.env` at mode `0600`, creates the `cabanon` service account and database roles, installs the systemd unit, applies migrations, and verifies `/healthz` and `/readyz`.

For a new installation it prompts for the private non-loopback bind address and exact public browser origin, then generates or securely accepts the database password and `CABANON_SECRET_KEY_BASE`. The resulting environment sets `CABANON_ENV=production`, `CABANON_DATABASE_URL`, `CABANON_BIND_ADDRESS`, `CABANON_PORT`, and `CABANON_ALLOWED_ORIGIN`. Preserve this environment file; it contains the application and database secrets. The installer can be rerun after a failed installation: it preserves these secrets, waits for the selected PostgreSQL cluster to accept local connections, and completes missing database objects and grants.

## Release deployment

Use the `main-<short-sha>` GitHub pre-release produced by the successful CI run. CI runs verification and security scanning, builds the frontend and release bundle, retains it as a seven-day Actions artifact, and attaches it to the pre-release. CI has no deployment credentials and never accesses the application LXC.

For an update, download and extract the release bundle on the application LXC, then run its non-interactive deployment script:

```sh
sudo ./installer/deploy.sh --release-dir ./cabanon-release-main-<short-sha>
```

`deploy.sh` verifies the bundle and shipment checksums, confirms Debian 13 OTP compatibility, applies pending migrations, installs an immutable release, updates the `current` link atomically, restarts systemd, and waits for `/readyz`. If the new release fails to start or become ready, it restores the preceding release automatically. It does not recreate database roles, overwrite the environment file, or prompt for secrets.

## Caddy and Pocket ID requirements

Caddy and Pocket ID are intentionally outside this repository and remain operator-managed. Before production use, configure Pocket ID to require authentication for every Cabanon route, proxy only to the application LXC's private bind address, preserve `Host` and forwarded headers, and enable TLS, access logs, request limits, and rate limits. Do not expose the Caddy admin API publicly.

Restrict the application LXC firewall to TCP/8080 from Caddy's private address only. Do not treat the application Origin guard as a replacement for Pocket ID or network filtering.

## Database backup and recovery

A same-LXC database is not a backup. This repository does not configure automated off-host backups or their credentials. The operator must configure encrypted off-host logical backups, retention, monitoring, and regular restore tests before production use.

Perform restore tests on a separate database or host, record their date, duration, and result, and also test recovery from a Proxmox snapshot. Snapshots alone are not a substitute for encrypted off-host backups.

## Readiness checklist

- [ ] Pocket ID protects every public route and Caddy is the only public entry point.
- [ ] The application LXC firewall allows TCP/8080 only from Caddy's private address.
- [ ] PostgreSQL is not listening on a routed interface.
- [ ] Application secret and database password are stored outside Git in `/etc/cabanon/cabanon.env` at mode `0600`.
- [ ] `/healthz` and `/readyz` are monitored from the private network.
- [ ] The systemd service runs as `cabanon` and systemd hardening is active.
- [ ] LXC CPU, memory, disk, and log rotation limits are configured.
- [ ] Automatic security updates or a regular patch window are configured.
- [ ] Operator-managed encrypted off-host backups and a restore test have completed successfully.
