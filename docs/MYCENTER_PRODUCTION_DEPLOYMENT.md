# MyCenter Production Deployment

## Target architecture

MyCenter runs as one Docker Compose service on Ubuntu Server 24.04 LTS x86_64. MeshCentral terminates HTTPS directly and performs ACME HTTP-01 through its built-in Let's Encrypt integration. Only ports 80 and 443 are published by Compose; MPS is disabled. NeDB is used for the initial single-node deployment.

Expected layout:

```text
/opt/mycenter/
|-- src/                     # root-owned checkout cloned from the verified bundle
|-- deploy/                  # mode-600 .env, config, Compose, current-tools link
|-- restore-tmp/             # protected restore validation workspace
`-- state/
    |-- releases/<tag>/      # config, Compose and root-owned operational tools
    `-- maintenance-incomplete  # present only while recovery must fail closed

Docker named volumes:
meshcentral-data
meshcentral-files
meshcentral-backups
meshcentral-web
```

The application image is tagged `mycenter:<short-commit>`. `latest` is not the
sole production tag and MeshCentral self-update is disabled. An enabled
`mycenter.service` reconciles the deployed Compose snapshot at boot, in addition
to the container's `unless-stopped` restart policy. It refuses to start while
the persistent incomplete-maintenance marker exists. Update and destructive
restore run an unverified container with restart policy `no`, returning to
`unless-stopped` only after health and release metadata are consistent.

## Required operator input

Before the first SSH connection, supply values through the approved interactive channel:

```text
VPS_IP=<PUBLIC_IPV4>
VPS_SSH_USER=<SUDO_USER>
VPS_SSH_KEY=<LOCAL_PRIVATE_KEY_PATH>
MYCENTER_DOMAIN=<FQDN>
ACME_EMAIL=<VALID_EMAIL>
```

Supply only the local path to the SSH key. Do not paste private-key contents, key passphrases, root passwords, MyCenter passwords, or provider API tokens.

Create this DNS record before certificate issuance:

```text
MYCENTER_DOMAIN  A  VPS_IP
```

Do not retain an AAAA record unless IPv6 is configured and tested on the VPS.

## Local release gate

From `C:\projects\MyCenter`:

```powershell
git status --short
git branch --show-current
git log -4 --oneline --decorate
git diff --check
@('MeshCmd.exe','MeshCmd64.exe','MeshService.exe','MeshService64.exe') | ForEach-Object {
    git cat-file -e "HEAD:agents/$_"
}
```

The branch must be `feature/mycenter-production`. If Defender has quarantined
working-tree copies of `MeshCmd*.exe` or `MeshService*.exe`, do not disable
Defender and do not stage their deletion. Their tracked Git objects must still
exist; a Linux checkout from the bundle will materialize them for the image build.

Create the transfer artifact outside the repository:

```powershell
$bundlePath = Join-Path ([IO.Path]::GetTempPath()) 'mycenter-production.bundle'
git bundle create $bundlePath feature/mycenter-production
git bundle verify $bundlePath
```

The bundle contains committed source only and does not contain VPS `.env`, runtime data, passwords, or certificates.

## Preflight without changing the VPS

Verify DNS locally:

```powershell
Resolve-DnsName -Type A MYCENTER_DOMAIN
Resolve-DnsName -Type AAAA MYCENTER_DOMAIN -ErrorAction SilentlyContinue
```

The A result must equal `VPS_IP`. Then test key authentication:

```powershell
ssh -i VPS_SSH_KEY VPS_SSH_USER@VPS_IP
```

Do not disable password authentication at this stage.

On the VPS, collect read-only facts first:

```bash
cat /etc/os-release
uname -m
df -h /
free -h
swapon --show
hostnamectl
ss -lntup
sudo ufw status verbose
docker --version 2>/dev/null || true
docker compose version 2>/dev/null || true
systemctl --type=service --state=running
getent ahostsv4 MYCENTER_DOMAIN
getent ahostsv6 MYCENTER_DOMAIN
```

Stop if the OS/architecture is wrong, disk/RAM is insufficient, ports 80/443 are occupied, DNS is incorrect, or the host contains an unknown conflicting service. Do not remove conflicts automatically.

## Transfer without GitHub

From Windows:

```powershell
scp -i VPS_SSH_KEY $bundlePath VPS_SSH_USER@VPS_IP:/tmp/mycenter-production.bundle
```

On the VPS, create a root-owned checkout. Operational systemd units never execute
code from an SSH-user-writable tree:

```bash
sudo install -d -o root -g root -m 0750 /opt/mycenter
sudo git clone /tmp/mycenter-production.bundle /opt/mycenter/src
sudo git -C /opt/mycenter/src switch feature/mycenter-production
sudo git -C /opt/mycenter/src status --short
sudo git -C /opt/mycenter/src log -4 --oneline --decorate
for agent_blob in MeshCmd.exe MeshCmd64.exe MeshService.exe MeshService64.exe; do
  sudo git -C /opt/mycenter/src cat-file -e "HEAD:agents/${agent_blob}"
done
```

After successful transfer and verification, delete only the explicit temporary bundle on each host. Do not delete a computed or broad path.

## VPS preparation

Review [`deploy/install-vps.sh`](../deploy/install-vps.sh) before running it. It installs Docker Engine and the Compose plugin from Docker's official Ubuntu repository, enables security updates, prepares `/opt/mycenter`, and applies only explicitly selected system changes.

Select an IANA timezone explicitly; UTC is the recommended production default:

```bash
sudo env MYCENTER_TIMEZONE=UTC /opt/mycenter/src/deploy/install-vps.sh
```

Firewall sequencing is mandatory:

1. Determine the actual SSH port from `sshd` configuration and the current connection.
2. Open a second key-authenticated SSH session and keep the first open.
3. Allow the actual SSH port, 80/tcp, and 443/tcp.
4. Set incoming deny and outgoing allow.
5. Enable UFW.
6. Verify the second SSH session and public listeners before closing the first.

Never expose Docker API, databases, Node debug ports, container-internal ports, or MPS 4433.
Complete this firewall gate before running the initial deployment that publishes
ports 80 and 443.

## Runtime secrets

Copy `deploy/.env.example` to `/opt/mycenter/deploy/.env` only on the VPS. Use
`umask 077` and mode 600. Populate only the real domain, ACME email and public
IPv4. Leave image/session/registration placeholders and
`MYCENTER_BOOTSTRAP_ACTIVE=true`; `deploy.sh` derives the tag and generates both
secrets without placing their values in shell history.

The checked-in `config.production.template.json` contains placeholders only. `deploy.sh` renders `/opt/mycenter/deploy/config.json` with restricted permissions and never prints the session key.

## Build and staging deployment

On the VPS:

```bash
sudo /opt/mycenter/src/deploy/deploy.sh
sudo docker compose --project-name mycenter \
  --env-file /opt/mycenter/deploy/.env \
  --file /opt/mycenter/deploy/docker-compose.yml ps
sudo docker compose --project-name mycenter \
  --env-file /opt/mycenter/deploy/.env \
  --file /opt/mycenter/deploy/docker-compose.yml \
  logs --tail=200 mycenter
sudo /opt/mycenter/deploy/current-tools/healthcheck.sh
sudo systemctl status mycenter.service
```

The initial action enforces ACME staging, records version-paired root-owned
maintenance tools, and refuses to run while the VPS reports that a reboot is
required.

Verify:

- the image tag equals the source short commit;
- the container is healthy;
- only host ports 80 and 443 are published;
- HTTP redirects to HTTPS;
- the staging certificate files exist in the persistent data volume;
- logs contain no secrets and no dynamic dependency-install loop.

Staging certificates are intentionally untrusted. Do not bypass TLS verification in the production health check.

## Move from ACME staging to production

Proceed only when DNS is correct and ports 80/443 are externally reachable.

1. Stop the Compose service.
2. Remove only `staging.crt` and `staging.key` from `meshcentral-data/letsencrypt-certs`.
3. Render configuration with `letsEncrypt.production: true`.
4. Start the same versioned image.
5. Wait for health and verify issuer, SAN/hostname, chain trust, and expiry without `--insecure`.

Use the reviewed production mode of `deploy.sh`; do not manually edit secrets into the tracked template.
If production issuance or validation fails, `deploy.sh` restores staging mode and attempts to return the staging service to health; the failure must still be diagnosed before retrying production.

## First administrator

After trusted HTTPS and MyCenter branding are confirmed:

1. Keep `newAccounts: false`; upstream still permits the first account.
2. Copy the generated root-only first-account token through authenticated SSH directly to a local password manager or clipboard without printing or logging it.
3. The user enters that token and manually creates the first administrator in the web UI; no operator or script requests the username or password.
4. After confirmation, run `/opt/mycenter/deploy/current-tools/deploy.sh --close-registration ADMIN_CREATED` to rotate the disclosed bootstrap token to a new unrevealed permanent guard, mark bootstrap closed, and recreate the container; never use that confirmation before a successful administrator login.
5. Keep the permanent guard in the protected runtime config. It prevents the upstream first-user exception from becoming unprotected if the user database is ever empty or damaged.
6. Verify the registration option is gone while the administrator can still sign in, clear any clipboard copy, and ask the user to enable 2FA without sharing the secret or recovery codes.

After production TLS, account creation, and registration closure are confirmed, run:

```bash
sudo /opt/mycenter/deploy/current-tools/deploy.sh --enable-backups
```

This requires registration to be closed, creates the initial backup, validates it with a restore dry-run, releases the shared maintenance lock, and only then enables the systemd timer.

## Production verification

Run the checklist in [`MYCENTER_PRODUCTION_SMOKE_TEST.md`](MYCENTER_PRODUCTION_SMOKE_TEST.md). At minimum verify:

- trusted HTTPS and HTTP redirect;
- title, favicon, green pixel login, and responsive layout;
- My Devices, My Account, My Server, My Events, My Users, logout, and re-login;
- registration closed;
- health endpoint and WebSocket path;
- `agent.ashx` reachable as the expected agent endpoint;
- container restart persistence;
- backup, checksum, permissions, and restore dry-run;
- one original Windows x64 MeshAgent Online with Details, Terminal, Files, Desktop, and reconnect after container restart.

Do not execute terminal commands or modify user files during the first Agent smoke-check.

## Service management

```bash
sudo docker compose --project-name mycenter \
  --env-file /opt/mycenter/deploy/.env \
  --file /opt/mycenter/deploy/docker-compose.yml ps
sudo docker compose --project-name mycenter \
  --env-file /opt/mycenter/deploy/.env \
  --file /opt/mycenter/deploy/docker-compose.yml \
  logs --tail=200 mycenter
sudo docker compose --project-name mycenter \
  --env-file /opt/mycenter/deploy/.env \
  --file /opt/mycenter/deploy/docker-compose.yml \
  restart mycenter
sudo /opt/mycenter/deploy/current-tools/healthcheck.sh
```

Update, rollback, backup, and restore procedures are documented separately. Do not use the built-in MeshCentral self-update in the container.

## Known initial limitations

- The baseline uses single-node NeDB; do not run multiple replicas.
- A backup on the same VPS is not off-site disaster recovery.
- Browser automation was unavailable during the Windows local smoke-check; authenticated UI and responsive checks required explicit manual confirmation.
- The production Docker build and shell syntax can only be fully validated on the target Ubuntu/Docker environment.
- No push is required or performed by this deployment flow.
