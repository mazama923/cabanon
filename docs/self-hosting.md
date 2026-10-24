# Self-hosting Cabanon

This guide describes the supported production shape: a private Debian 13 Proxmox LXC running Cabanon and PostgreSQL, plus a separate public LXC running Caddy and Pocket ID. Cabanon is deployed as an Erlang shipment supervised by systemd. It does not use Docker, Podman, or another OCI runtime.

## Topology

```mermaid
flowchart TD
    Browser[Single user's browser] -->|HTTPS TCP 443| PublicLxc[Public Proxmox LXC\nCaddy + Pocket ID]
    Internet[Internet] -->|HTTP TCP 80\nHTTPS TCP 443| PublicLxc
    PublicLxc -->|Private HTTP TCP 8080| AppLxc[Private Proxmox LXC\nCabanon systemd service]
    AppLxc -->|Unix socket or 127.0.0.1| Database[(PostgreSQL)]
    Backup[Encrypted off-host backup target] <-->|Operator-managed pg_dump\nand restore tests| Database
```

| Component | Location | Responsibility | Network exposure |
| --- | --- | --- | --- |
| Caddy and Pocket ID | Public LXC | TLS termination, single-user authentication boundary, reverse proxy, access logs | Public TCP/80 and TCP/443 only |
| Cabanon | Private LXC | Serves the packaged browser frontend and HTTP API | Private `CABANON_BIND_ADDRESS:8080`; TCP/8080 allowed only from the public LXC |
| PostgreSQL | Same private LXC as Cabanon | Persistent household and construction data | Loopback and Unix socket only; never routed or publicly exposed |
| Backup target | Separate operator-controlled location | Encrypted database backup retention and recovery | Outbound from the private LXC only, as required by the chosen backup system |

Cabanon has no application-level users, roles, or authorization. Pocket ID must authenticate the one user before Caddy proxies any Cabanon route. The application service runs as the non-login `cabanon` system account.

## Prerequisites

Prepare the following before the first installation:

- A Proxmox host with two LXC containers:
  - a public LXC for Caddy and Pocket ID;
  - a private application LXC running **Debian 13** with systemd.
- A private, non-loopback IPv4 or IPv6 address configured on the application LXC. The installer rejects loopback addresses and addresses not present on the host.
- A Debian APT configuration that offers `erlang-base` for Erlang/OTP `27.3.4.1`. The release and installer enforce this exact Debian 13 OTP version.
- Root access on the application LXC, outbound access to Debian package repositories for the initial installation, and at least 1 GiB free space on `/`.
- A public HTTPS origin for Cabanon, such as `https://cabanon.example.com`. It must be an origin only: scheme, host, and optional port; no path.
- A GitHub account or another approved way to obtain the release asset from the repository's GitHub Releases page.
- A firewall policy ready to enforce the rules in [Network and firewall](#network-and-firewall).
- An encrypted off-host PostgreSQL backup destination and a tested restore procedure before storing production data.

Gleam, Mise, Docker, and Podman are not required on the application LXC.

## Release source

A valid `vMAJOR.MINOR.PATCH` tag that passes verification and security scanning publishes a stable GitHub release. Its tag and release bundle use this form:

```text
v1.2.3
cabanon-release-v1.2.3.tar.gz
```

Successful pushes to `main` also publish `main-<12-character-git-sha>` pre-releases for testing. Every bundle is retained as a GitHub Actions artifact for seven days. Prefer stable release assets for normal installation and upgrades. CI has no credentials for, and does not deploy to, the application LXC.

Use the GitHub Releases page to select the required stable release, then download its asset to the application LXC. For example, after replacing the placeholders with the repository owner, repository name, and release tag:

```sh
mkdir -p /root/cabanon-downloads
cd /root/cabanon-downloads
curl --fail --location --remote-name \
  https://github.com/<owner>/<repository>/releases/download/v1.2.3/cabanon-release-v1.2.3.tar.gz
tar -xzf cabanon-release-v1.2.3.tar.gz
```

The extracted directory is named `cabanon-release-v1.2.3`. The bundled installer validates the release manifest and checksums before changing the host. The release asset itself is not separately signed by this repository; obtain it from the expected GitHub repository and protect the GitHub release process accordingly.

## First installation

Run the installer from the extracted release directory as root:

```sh
cd /root/cabanon-downloads/cabanon-release-v1.2.3
./installer/install.sh
```

The installer is interactive. It verifies the release, checks Debian 13 and the expected OTP package, installs Erlang, PostgreSQL, and its required host tools, then configures PostgreSQL and systemd.

### Values requested by the installer

| Prompt | Value | Validation and effect |
| --- | --- | --- |
| `Private Cabanon bind address` | The application LXC private address, for example `10.0.20.10` | Must be a configured non-loopback IPv4 or IPv6 address. Cabanon listens on this address. |
| `Allowed browser origin` | The exact public origin, for example `https://cabanon.example.com` | Must be an absolute `http` or `https` origin without a path. Stored as `CABANON_ALLOWED_ORIGIN`. |
| Installation confirmation | `y` | Shows the release, bind address, origin, local-only PostgreSQL, and service account before changing the host. |
| Provide secrets instead of generating them | Optional `y` | If declined, the installer generates both secrets securely. |
| PostgreSQL password | Only when supplying secrets | At least 32 URL-safe characters: letters, digits, `.`, `_`, `~`, or `-`. |
| `CABANON_SECRET_KEY_BASE` | Only when supplying secrets | Exactly 64 hexadecimal characters. |

The installer creates `/etc/cabanon/cabanon.env`, owned by root with mode `0600`, containing:

```text
CABANON_ENV=production
CABANON_SECRET_KEY_BASE=...
CABANON_DATABASE_URL=postgresql://cabanon_app:...@127.0.0.1:5432/cabanon?sslmode=disable
CABANON_BIND_ADDRESS=<private-application-lxc-address>
CABANON_PORT=8080
CABANON_ALLOWED_ORIGIN=https://cabanon.example.com
```

Keep this file out of Git and backups that are not encrypted. It contains the application secret and database password. On a subsequent run, the installer preserves an existing production environment file and refuses ambiguous database-role recreation.

The installation also:

- configures PostgreSQL to listen only on `127.0.0.1`, uses `scram-sha-256` password authentication for local TCP connections, and keeps Unix-socket access local;
- creates the non-login `cabanon` service account, the `cabanon` database, non-login `cabanon_owner`, and least-privilege `cabanon_app` roles;
- installs `cabanon.service`, enables it, applies database migrations, and installs the first immutable release under `/opt/cabanon/releases/`;
- atomically points `/opt/cabanon/current` at that release and checks both `/healthz` and `/readyz`.

## Network and firewall

Apply these rules at the Proxmox, LXC guest, or both layers according to the local firewall design. The required traffic policy is intentionally small:

| Source | Destination | Protocol and port | Action |
| --- | --- | --- | --- |
| Internet | Public Caddy and Pocket ID LXC | TCP/80 and TCP/443 | Allow |
| Public Caddy and Pocket ID LXC private address | Private application LXC | TCP/8080 | Allow |
| Any other source | Private application LXC | TCP/8080 | Deny |
| Any routed source | Application LXC PostgreSQL | TCP/5432 | Deny |
| Application LXC | Operator-selected backup target | Backup-specific outbound traffic | Allow only as required |

Do not assign the Cabanon application a public listening address. PostgreSQL must remain bound to loopback or use its local Unix socket. Confirm that Pocket ID authenticates every Cabanon route before enabling public access.

## Caddy and Pocket ID

Caddy and Pocket ID are intentionally operated outside this repository. Configure them separately to:

- require Pocket ID authentication for every Cabanon route before proxying;
- proxy only to the private application LXC bind address on TCP/8080;
- preserve `Host` and forwarded headers;
- terminate TLS, retain access logs, and apply request and rate limits;
- keep the Caddy administration API private.

No Caddy or Pocket ID configuration is included here. Do not expose Cabanon directly as a substitute for this boundary.

## Verification

On the application LXC, check service state, the private listeners, and both health endpoints:

```sh
systemctl status cabanon.service
ss -ltnp | grep -E '(:8080|:5432)'
curl --fail http://<private-application-lxc-address>:8080/healthz
curl --fail http://<private-application-lxc-address>:8080/readyz
journalctl -u cabanon.service --since '15 minutes ago'
```

Expected results:

- `cabanon.service` is active and runs as `cabanon`.
- TCP/8080 is bound to the configured private application address.
- PostgreSQL does not listen on a routed address; it is local to the application LXC.
- `/healthz` confirms liveness and `/readyz` confirms application readiness, including database initialization.
- Public access reaches Caddy over HTTPS, Pocket ID challenges unauthenticated requests, and authenticated traffic is proxied to Cabanon.

## Upgrades

Each upgrade is a fresh stable `vMAJOR.MINOR.PATCH` bundle. Download and extract the required release asset, then run its non-interactive deploy script:

```sh
cd /root/cabanon-downloads
curl --fail --location --remote-name \
  https://github.com/<owner>/<repository>/releases/download/v1.2.3/cabanon-release-v1.2.3.tar.gz
tar -xzf cabanon-release-v1.2.3.tar.gz
cd cabanon-release-v1.2.3
./installer/deploy.sh --release-dir .
```

`deploy.sh` requires root, Debian 13, systemd, an existing `cabanon` service account, PostgreSQL tools, and the existing `/etc/cabanon/cabanon.env`. It does not prompt for or overwrite secrets, recreate database roles, or change the public origin.

The deploy script verifies the bundle and Erlang shipment checksums, checks the installed OTP version, applies pending migrations, installs an immutable release under `/opt/cabanon/releases/`, atomically updates `/opt/cabanon/current`, restarts systemd, and waits for `/readyz`. Monitor free disk space because installed releases are retained; this repository does not implement release-retention cleanup.

## Rollback

If a new release cannot restart or become ready, `deploy.sh` automatically restores the previous `/opt/cabanon/releases/<version>` directory through the `current` symlink and restarts the service. On the first installation there is no previous release, so a failed deployment stops the service.

The automatic rollback is an **application release rollback only**. Migrations run before the release is activated, and this repository provides no reverse-migration tool. Do not assume a previous application release is compatible with a newer database schema. Take and test a database backup before upgrades that include migrations.

For a deliberate application-only rollback after confirming database compatibility, point `current` to a known previous release and restart the service:

```sh
ln -s /opt/cabanon/releases/main-<previous-sha> /opt/cabanon/current.new
mv -Tf /opt/cabanon/current.new /opt/cabanon/current
systemctl restart cabanon.service
curl --fail http://<private-application-lxc-address>:8080/readyz
```

If this fails, inspect the service journal before attempting database recovery:

```sh
journalctl -u cabanon.service --since '30 minutes ago'
```

## Backups and restore

The PostgreSQL database lives in the same LXC as the application. A Proxmox snapshot is useful for recovery but is not an off-host backup and does not provide independent failure isolation.

Configure encrypted, off-host logical backups, retention, monitoring, and regular restore tests. A root-operated logical dump can use the local PostgreSQL service account without placing credentials on the command line:

```sh
install -d -o root -g root -m 0700 /root/cabanon-backups
runuser -u postgres -- pg_dump --format=custom \
  --file /root/cabanon-backups/cabanon-<date>.dump cabanon
```

Transfer or create that dump through an operator-managed encrypted backup mechanism, then enforce retention outside the repository. Protect backup contents as household financial data.

Test restoration on a separate PostgreSQL host or separate database, never by first overwriting production. The target must have a compatible PostgreSQL version and the roles required by the dump. A typical test restore is:

```sh
runuser -u postgres -- createdb cabanon_restore_test
runuser -u postgres -- pg_restore --exit-on-error \
  --dbname=cabanon_restore_test /path/to/cabanon-<date>.dump
runuser -u postgres -- dropdb cabanon_restore_test
```

Record the restore date, duration, and result. Also test recovery from a Proxmox snapshot. Before restoring data onto the production LXC, stop `cabanon.service`, preserve the current database and logs, follow the tested restore procedure, then start the service and verify `/readyz`.

## Security limitations

- Cabanon is designed for **one user**. It has no application accounts, roles, identity mapping, or household-scoped authorization. Do not use it for multiple users until application-level authorization exists.
- Pocket ID at the Caddy boundary is the authentication control. The Cabanon application must not be exposed directly to the Internet or treated as authenticated merely because it is on a private address.
- State-changing `POST`, `PUT`, `PATCH`, and `DELETE` requests require an `Origin` exactly equal to `CABANON_ALLOWED_ORIGIN`; requests without that exact origin receive `403`. CORS uses the same exact origin.
- The Origin guard reduces cross-origin request risk but is not authentication, authorization, a substitute for Pocket ID, or a substitute for the Caddy-only firewall rule.
- Keeping Cabanon and PostgreSQL in the same LXC reduces network exposure but does not isolate resource exhaustion or host compromise. Use LXC resource limits, snapshots, encrypted off-host backups, and a tested recovery procedure.
- If the application LXC may be compromised, revoke active sessions at the identity provider, rotate `CABANON_SECRET_KEY_BASE`, the database password, and backup credentials, preserve relevant logs and snapshots, and rebuild from a known-good release.

## Not provided by this repository

This repository deliberately does **not** provide:

- Proxmox host or LXC creation, sizing, snapshot schedules, resource limits, patching policy, or firewall implementation;
- Caddy and Pocket ID installation, configuration, identity-provider setup, TLS certificates, domain or DNS configuration, rate-limit policy, or public-access logging configuration;
- a Caddyfile or other reverse-proxy configuration;
- release-asset signing, a public checksum for the outer GitHub release archive, or deployment credentials in CI;
- automated encrypted off-host backups, backup destination credentials, retention, monitoring, alerting, or restore orchestration;
- reverse database migrations, automatic cleanup of old immutable releases, multi-user identity mapping, or application-level authorization.

These controls are operator responsibilities and must be completed before treating the deployment as production-ready.
