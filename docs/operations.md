# Production operations

## Deployment topology

- **Caddy LXC**: public reverse proxy, TLS termination, and access logs.
- **Application LXC**: systemd-managed Cabanon Erlang shipment on private TCP/8080.
- **PostgreSQL**: native service in the application LXC, bound to loopback or a Unix socket only.

Use a private bridge or VLAN between Caddy and the application LXC. Do not rely on an unadvertised IP address as a security boundary; enforce the allow-list in the Proxmox firewall and inside the application LXC.

## Application LXC bootstrap

Install Erlang/OTP from the operating-system package manager. Its major version must match the build environment in `mise.toml` (currently OTP 28). Install PostgreSQL natively and create a non-login service account for Cabanon.

```sh
sudo useradd --system --home-dir /var/lib/cabanon --create-home --shell /usr/sbin/nologin cabanon
sudo install --directory --owner=root --group=cabanon --mode=0750 /etc/cabanon
sudo install --directory --owner=root --group=root --mode=0755 /opt/cabanon/releases
sudo install --directory --owner=cabanon --group=cabanon --mode=0750 /var/lib/cabanon
sudo install --owner=root --group=root --mode=0644 infra/systemd/cabanon.service /etc/systemd/system/cabanon.service
sudo install --owner=root --group=root --mode=0600 infra/systemd/cabanon.env.example /etc/cabanon/cabanon.env
sudoedit /etc/cabanon/cabanon.env
sudo systemctl daemon-reload
sudo systemctl enable cabanon
```

Set `CABANON_SECRET_KEY_BASE` in `/etc/cabanon/cabanon.env` to a unique value generated with `openssl rand -hex 32`.

## Release deployment

Build the artifact in CI or on a trusted build host:

```sh
mise run package
scp dist/cabanon-erlang-shipment.tar.gz dist/cabanon-erlang-shipment.tar.gz.sha256 app-lxc:/tmp/
```

On the application LXC, verify the checksum, extract an immutable release directory, switch the `current` symlink, then restart systemd:

```sh
cd /tmp
sha256sum -c cabanon-erlang-shipment.tar.gz.sha256
sudo install --directory --owner=root --group=root --mode=0755 /opt/cabanon/releases/0.1.0
sudo tar --no-same-owner -xzf cabanon-erlang-shipment.tar.gz --directory /opt/cabanon/releases/0.1.0 --strip-components=1
sudo ln -sfn /opt/cabanon/releases/0.1.0 /opt/cabanon/current
sudo systemctl restart cabanon
curl --fail http://127.0.0.1:8080/healthz
```

Keep the previous release directory. Roll back by repointing `/opt/cabanon/current` and restarting `cabanon`.

## Caddy requirements

Caddy must proxy only to the private address of the application LXC. Preserve `Host` and forward headers, set a request-body limit appropriate for the application, and enable access logs with rotation. Do not expose a Caddy admin API to the public network.

Example upstream shape:

```caddyfile
budget.example.net {
    reverse_proxy 10.10.20.10:8080
}
```

Use the real private address and domain during deployment. Add rate limiting before exposing authentication endpoints.

## Database backup and recovery

A same-LXC database is not a backup. Schedule encrypted, off-host logical backups and keep a defined retention policy.

```sh
pg_dump --format=custom --file /var/backups/cabanon/cabanon-$(date +%F).dump cabanon
pg_restore --clean --if-exists --dbname cabanon_restore /var/backups/cabanon/cabanon-YYYY-MM-DD.dump
```

Perform the restore test on a separate database or host. Record the date, duration, and result. Also test recovery from a Proxmox snapshot; snapshots alone are not a substitute for off-host backups.

## Readiness checklist

- [ ] Caddy is the only public entry point.
- [ ] PostgreSQL is not listening on a routed interface.
- [ ] Application secret and database password are stored outside Git and readable only by the service account.
- [ ] Health check `GET /healthz` is monitored from the private network.
- [ ] The systemd service runs as `cabanon` and systemd hardening is active.
- [ ] LXC CPU, memory, disk, and log rotation limits are configured.
- [ ] Automatic security updates or a regular patch window are configured.
- [ ] An encrypted backup and a restore test have completed successfully.
