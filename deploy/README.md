# MyCenter production deployment

This directory deploys the current MyCenter checkout directly on Ubuntu Server
24.04 LTS x86_64. It does not pull an upstream MeshCentral image, modify the
MeshAgent protocol, expose MPS, or use MeshCentral self-update.

## Architecture

- Image: `mycenter:<12-character-git-commit>`.
- Runtime: official Node.js 24 LTS image, UID/GID 10001.
- Runtime files: process `umask 077`; the application container has no backup-volume mount.
- Public ports: TCP 80 and TCP 443 only.
- TLS: MeshCentral's built-in Let's Encrypt integration, staging first.
- Database: the checkout's default local NeDB database for one server replica.
- Container restart policy: `unless-stopped`.
- Host boot reconciliation: enabled `mycenter.service` runs the exact deployed
  Compose snapshot after Docker starts, unless a persistent incomplete-maintenance
  marker requires manual recovery.
- Persistent Docker volumes:
  - `meshcentral-data` — database, server identity, certificates and logs;
  - `meshcentral-files` — uploaded and user-managed server files;
  - `meshcentral-web` — persistent web overrides, if used later;
  - `meshcentral-backups` — daily and weekly archives.
- Runtime deployment state: `/opt/mycenter/deploy`, including the root-owned
  Compose definition that is paired with the running image.
- Source checkout: `/opt/mycenter/src`.
- Operational metadata: `/opt/mycenter/state`.
- Version-paired, root-owned operational scripts:
  `/opt/mycenter/state/releases/<tag>/tools`, selected atomically through
  `/opt/mycenter/deploy/current-tools`.
- Protected restore scratch space: `/opt/mycenter/restore-tmp`.

The image build preinstalls two exact upstream optional runtime modules:

- `acme-client@4.2.5`, selected by MeshCentral when `letsEncrypt` is enabled;
- `wildleek@2.0.0`, selected by `passwordRequirements.banCommonPasswords`.

They are installed only in the image and are not global npm packages. The
tracked `package.json` and `package-lock.json` are not rewritten.

## Prerequisites

Before the first SSH connection, prepare:

- a new Ubuntu Server 24.04 LTS x86_64 VPS;
- at least 2 vCPU, 4 GB RAM and 40 GB SSD;
- a public IPv4 address;
- key-based SSH access through a sudo-capable account;
- a DNS A record from the MyCenter FQDN to the VPS IPv4;
- no AAAA record unless IPv6 is deliberately configured on the VPS;
- free TCP ports 80 and 443.
- Git available on the VPS before cloning the transferred bundle.

Never copy the private SSH key, MyCenter administrator password, session key,
2FA secret, MeshID, ServerID, cookies or tokens into this repository.

## Transfer without GitHub

Create and verify a Git bundle outside the source checkout on the development
computer, copy it with `scp`, and clone it on the VPS:

```bash
sudo install -d -o root -g root -m 0750 /opt/mycenter
sudo git clone /path/to/mycenter-production.bundle /opt/mycenter/src
sudo git -C /opt/mycenter/src status --short
sudo git -C /opt/mycenter/src log -1 --oneline --decorate
for agent_blob in MeshCmd.exe MeshCmd64.exe MeshService.exe MeshService64.exe; do
  sudo git -C /opt/mycenter/src cat-file -e "HEAD:agents/${agent_blob}"
done
```

The last checks ensure that Microsoft Defender's local quarantine did not
remove tracked Windows agent blobs from the commit used to build the image.

## VPS preparation

Run from the clean bundle checkout:

```bash
cd /opt/mycenter/src
sudo env MYCENTER_TIMEZONE=UTC ./deploy/install-vps.sh
```

The script inventories the server, refuses to replace a service already using
80 or 443, installs Docker Engine from Docker's official Ubuntu repository,
installs the Compose plugin, configures unattended security updates and bounded
journald retention, and installs—but does not yet enable—the boot reconciliation
unit or backup timer. Initial deployment enables the boot unit only after a
healthy staging service exists.

It does not enable UFW, alter SSH authentication, remove services, or open any
additional port.

## Runtime environment and secrets

Create the production environment outside the Git checkout:

```bash
sudo install -d -o root -g root -m 0750 /opt/mycenter/deploy
sudo cp /opt/mycenter/src/deploy/.env.example /opt/mycenter/deploy/.env
sudo chown root:root /opt/mycenter/deploy/.env
sudo chmod 600 /opt/mycenter/deploy/.env
sudoedit /opt/mycenter/deploy/.env
```

Set only the real domain, ACME email and VPS IPv4. Leave:

```ini
MYCENTER_IMAGE_TAG=SET_FROM_GIT
MYCENTER_SESSION_KEY=GENERATE_ON_VPS
MYCENTER_REGISTRATION_TOKEN=GENERATE_ON_VPS
MYCENTER_BOOTSTRAP_ACTIVE=true
ACME_PRODUCTION=false
MYCENTER_NEW_ACCOUNTS=false
```

`deploy.sh` derives the versioned image tag from Git and generates a 96-character
cryptographic session key and a 256-bit protected bootstrap credential with
OpenSSL. It never prints either secret. The real `.env` remains root-owned with
mode 600. The generated runtime config is
owned by UID/GID 10001, has mode 600, is outside Git, and is mounted read-only
into the application container.

The local container entrypoint sets `umask 077` before Node.js starts. Only the
root-operated backup and restore helpers mount `meshcentral-backups`; the
application service cannot write to that archive volume.

Do not place `/opt/mycenter/deploy/.env` or the generated `config.json` under
`/opt/mycenter/src`.

## Firewall activation

Complete this gate before the first Compose deployment publishes ports 80 and
443. Determine the actual SSH port, keep the original session open, and verify a
second key-authenticated SSH session before enabling UFW:

```bash
SSH_PORT="$(sudo sshd -T | awk '$1 == "port" {print $2; exit}')"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow "${SSH_PORT}/tcp"
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

Docker publishes only 80/tcp and 443/tcp. MPS 4433, database ports, Docker API
and Node debug ports are neither published nor enabled. Docker-published ports
can interact with firewall chains, so the Compose file itself must continue to
publish no port except 80 and 443. Verify the second SSH session before closing
the first.

## Initial staging deployment

Confirm that DNS resolves to the VPS and that no unwanted AAAA record exists,
then run:

```bash
sudo /opt/mycenter/src/deploy/deploy.sh
```

The command validates the clean checkout, verifies the tracked Windows agent,
renders the config, builds `mycenter:<short-commit>`, starts Compose, waits for
container health and verifies that the staging certificate and key files were
created. It refuses `ACME_PRODUCTION=true` for the initial deployment and
deliberately leaves `mycenter-backup.timer` disabled.

During ACME staging, the certificate is intentionally not publicly trusted.
The container healthcheck therefore verifies the HTTP redirect and the TCP/443
listener without performing an insecure TLS request. It never uses `curl -k`.

Wait until both staging files exist without printing their contents:

```bash
sudo docker exec mycenter test -s /opt/meshcentral/meshcentral-data/letsencrypt-certs/staging.crt
sudo docker exec mycenter test -s /opt/meshcentral/meshcentral-data/letsencrypt-certs/staging.key
```

Review logs for ACME errors:

```bash
sudo docker compose \
  --project-name mycenter \
  --env-file /opt/mycenter/deploy/.env \
  --file /opt/mycenter/deploy/docker-compose.yml \
  logs --tail 200 mycenter
```

The custom container startup does not print `config.json`.

## Promote Let's Encrypt to production

Only after staging succeeds:

```bash
sudo /opt/mycenter/deploy/current-tools/deploy.sh --promote-acme
```

This explicit action:

1. revalidates DNS;
2. verifies that both staging artifacts exist;
3. stops MyCenter;
4. removes only `staging.crt` and `staging.key`;
5. switches `ACME_PRODUCTION=true` in the root-only `.env`;
6. renders the runtime config and starts the same versioned image;
7. waits for a publicly trusted certificate and validates HTTPS without `-k`.

If production issuance or validation fails, the script switches the protected
runtime configuration back to ACME staging and attempts to restore a healthy
staging service. It reports failure either way; production is never claimed
unless trusted hostname validation succeeds.

In production mode the container healthcheck resolves the configured hostname
to loopback with curl's `--resolve`, preserving normal certificate hostname and
trust-chain validation.

## First administrator and registration closure

MeshCentral permits its first account even while `newAccounts` is false. MyCenter
therefore generates a high-entropy `newAccountsPass` bootstrap token in the
root-only `.env`; staging and first-account creation are protected without ever
opening general registration. After trusted HTTPS is available, copy that token
through the authenticated SSH channel directly to a local password manager or
clipboard without printing or logging it, then open `https://MYCENTER_DOMAIN/`
and manually create the first administrator. Do not pass the username, account
password, or token through Git, chat, or shell history.

After confirming that the administrator can log in, close registration:

```bash
sudo /opt/mycenter/deploy/current-tools/deploy.sh --close-registration ADMIN_CREATED
```

This keeps `newAccounts` false, invalidates the disclosed bootstrap credential
by rotating it to a new, unrevealed 256-bit registration guard, marks bootstrap
closed, recreates MyCenter and waits for health. The permanent guard remains in
the root-only `.env` and rendered config so an empty or damaged user database
cannot reactivate unprotected first-user signup. Clear the old clipboard copy
afterward. Enable 2FA from the web interface; never export its secret or recovery
codes.

After production TLS and registration closure are verified, create and validate
the initial backup, then enable the timer with one explicit action:

```bash
sudo /opt/mycenter/deploy/current-tools/deploy.sh --enable-backups
```

The action requires registration to be closed, creates a backup, runs the
default restore dry-run against it and enables the timer only if both operations
succeed. The maintenance lock is released before the persistent timer starts.

## Health and service state

```bash
sudo docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' mycenter
curl --fail --silent --show-error https://MYCENTER_DOMAIN/health.ashx
sudo docker compose \
  --project-name mycenter \
  --env-file /opt/mycenter/deploy/.env \
  --file /opt/mycenter/deploy/docker-compose.yml \
  ps
```

`health.ashx` is a liveness signal, not a complete DB or agent-channel test.
Production smoke-checks must also cover login, WebSocket, `agent.ashx`, Devices,
Account, Server, Events, Users, logout and persistence after restart.

## Backups

The systemd timer runs daily at 02:15 with up to 15 minutes of randomized delay:

```bash
sudo systemctl status mycenter-backup.timer
sudo systemctl list-timers mycenter-backup.timer
sudo systemctl status mycenter.service
```

Manual backup:

```bash
sudo /opt/mycenter/deploy/current-tools/backup.sh
```

The script uses the shared MyCenter maintenance lock, gracefully stops the running
server, snapshots data/files/web plus deployment metadata, creates SHA-256,
restarts the server and waits for health. It retains 7 daily archives and 4
weekly archives. Weekly archives are taken from Sunday's daily backup in the
configured VPS timezone. A root-only `/run` marker allows the systemd service to
restart MyCenter only when an interrupted scheduled backup had actually stopped
a previously running container. The enabled `mycenter.service` performs boot
reconciliation if power was lost during a consistent snapshot.

Backups intentionally include the runtime `config.json` and root-only `.env` so
that the server identity and session configuration can be recovered. Therefore
every archive contains secrets and private certificate material. The backup
volume directories are mode 700 and archives/checksums are mode 600. Never make
them world-readable. Encrypt archives with a separately managed key before any
off-site copy; do not store that key in Git or in the same backup volume.

The Docker volume location can be inspected without printing backup contents:

```bash
sudo docker volume inspect meshcentral-backups --format '{{.Mountpoint}}'
```

Backups on the same VPS protect against application mistakes, not disk or VPS
loss. A production disaster-recovery plan requires an encrypted off-site copy.

## Restore

Dry-run is the default and never modifies production volumes:

```bash
sudo /opt/mycenter/deploy/current-tools/restore.sh
sudo /opt/mycenter/deploy/current-tools/restore.sh --dry-run daily/ARCHIVE.tar.gz
```

It verifies checksum, rejects absolute and parent-traversal archive paths,
checks available temporary space, extracts to a mode-700 directory under
`/opt/mycenter/restore-tmp`, validates JSON/domain/session-key shape and removes the temporary
directory. It refuses to continue if a stale exact-name restore directory is
present after an abnormal prior termination. It does not print file contents.
Apply mode additionally checks a pessimistic bound in the backup volume and
recalculates whether free space on each actual Docker-volume filesystem plus the
soon-to-be-replaced data can hold the extracted payload before deleting target
data.

An actual restore is intentionally explicit:

```bash
sudo /opt/mycenter/deploy/current-tools/restore.sh \
  --apply daily/ARCHIVE.tar.gz --confirm APPLY
```

Before replacing data, the script creates a fresh pre-restore backup. It restores
the persistent session key by atomically updating only that field in the current
runtime config; current registration and ACME policy are not replaced by archived
flags. The current release snapshot is synchronized only after health succeeds.
Before replacing data it writes `/opt/mycenter/state/maintenance-incomplete`.
While that marker exists, boot reconciliation fails closed; a failed destructive
restore stops the public container and retains the marker for manual diagnosis.
Recover an interrupted restore only with the exact pre-restore archive:

```bash
sudo /opt/mycenter/deploy/current-tools/restore.sh \
  --recover-incomplete daily/mycenter-YYYY-MM-DDTHHMMSSZ.tar.gz \
  --confirm RECOVER_INCOMPLETE
```

The guarded mode requires a `restore` marker and removes it only after health,
metadata and `unless-stopped` are verified.
Do not run apply mode during the initial production validation; use dry-run only.

## Update and rollback

Before replacing or switching `/opt/mycenter/src`, use the currently deployed
checkout and scripts to create and validate a recovery point:

```bash
sudo /opt/mycenter/deploy/current-tools/backup.sh
sudo /opt/mycenter/deploy/current-tools/restore.sh --dry-run
```

Only after both commands succeed, transfer and verify a new Git bundle and
switch `/opt/mycenter/src` to the desired clean commit. Then run:

```bash
sudo /opt/mycenter/src/deploy/update.sh
```

The procedure creates a second, immediate pre-update backup using the currently
deployed maintenance tools, builds a new commit-tagged image, preserves the previous runtime
config, deployed Compose definition and config template, starts the new image,
waits for health and automatically returns to the previous release snapshot if
health fails. Version-paired Compose, template and protected config snapshots
and operational-tool snapshots are retained under
`/opt/mycenter/state/releases/<tag>` for explicit rollback;
current secret and registration-policy values are reconciled before an older
snapshot is started. The root-owned `current-tools` link changes only after the
candidate runtime is healthy, protecting scheduled maintenance from a switched
or defective source checkout.
The process never uses MeshCentral self-update and never prunes the previous
working image.

Rollback to the recorded previous image:

```bash
sudo /opt/mycenter/deploy/current-tools/update.sh --rollback
```

An image rollback intentionally does not rewrite the Git checkout, so source
`HEAD` can remain newer than the deployed tag. Runtime Compose/template/config
files and maintenance tools come from the selected per-tag snapshot; a later
roll-forward runs the reviewed candidate update again. A persistent maintenance
marker prevents boot from exposing a partially switched runtime. Do not treat
source `HEAD` alone as proof of the active production version.

If the marker reports an interrupted `update`, `rollback`, or `recovery`, return
to the release recorded in `state/current-image-tag` with:

```bash
sudo /opt/mycenter/deploy/current-tools/update.sh \
  --recover-current RECOVER_CURRENT
```

Do not clear `maintenance-incomplete` manually; see the detailed update and
restore runbooks for read-only triage and operation-specific recovery.

Image rollback does not automatically restore data. If an incompatible data
migration ever occurs, validate and explicitly apply the pre-update backup.

## Original MeshAgent validation

Use only the agent downloaded from the production MyCenter UI. Confirm that its
server address is the production FQDN, then manually approve the normal UAC
installation. Do not inspect or publish `.msh`, MeshID or ServerID.

For the first smoke-check, only open Details, Terminal, Files and Desktop. Do
not run commands or modify files. Restart the MyCenter container and verify that
the same device reconnects without creating a duplicate.

## Licensing and attribution

MyCenter is based on the MeshCentral and MeshAgent open-source projects. Preserve
the repository `LICENSE`, copyright notices, attribution and all third-party
license material. The original MeshAgent remains an upstream-compatible
component and is not functionally modified by these deployment files.
