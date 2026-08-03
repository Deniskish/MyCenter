# MyCenter Backup and Restore

## Backup model

MyCenter uses a host systemd timer and [`deploy/backup.sh`](../deploy/backup.sh). MeshCentral's internal automatic backup is disabled to avoid two independent schedules.

The backup script:

1. takes the shared exclusive MyCenter maintenance lock, also used by deployment, update, and restore;
2. detects whether the MyCenter container is running;
3. stops it with the Compose grace period for a consistent NeDB snapshot;
4. archives the persistent data, files, custom web volume, rendered config, protected runtime `.env`, and deployment state;
5. creates a SHA-256 checksum;
6. applies retention;
7. restarts the service if it was running and waits for health.

The backup volume contains:

```text
daily/mycenter-YYYY-MM-DDTHHMMSSZ.tar.gz
daily/mycenter-YYYY-MM-DDTHHMMSSZ.tar.gz.sha256
weekly/mycenter-week-YYYY-WW.tar.gz
weekly/mycenter-week-YYYY-WW.tar.gz.sha256
```

Retention is the seven newest daily archives and four newest weekly archives.

## Sensitive contents

Backups contain databases, private certificate keys, the rendered configuration,
the runtime `.env`, deployed Compose/template files and per-tag release snapshots.
Treat every archive as a secret:

`backup.sh` refuses to run while bootstrap is active. After administrator creation,
the disclosed credential is rotated to an unrevealed permanent registration guard;
that guard is intentionally present in `.env`, `config.json`, release snapshots and
backups so a lost/empty user database cannot enable unprotected first-user signup.

- backup directories are mode 700 where applicable;
- archives and checksum files are mode 600;
- access is limited to root/the deployment operator;
- never commit, attach to tickets, or paste archive contents into chat;
- encrypt before copying off the VPS, with keys managed separately from the VPS.

A copy on the same VPS protects against operational mistakes but not host loss. Add tested encrypted off-site storage after the initial baseline.

## Schedule

[`deploy/mycenter-backup.timer`](../deploy/mycenter-backup.timer) runs daily at 02:15 in the VPS timezone with up to 15 minutes randomized delay and catches missed runs after downtime.

After production ACME, administrator creation, and registration closure are verified, run the guarded activation action:

```bash
sudo /opt/mycenter/deploy/current-tools/deploy.sh --enable-backups
sudo systemctl status mycenter-backup.timer
sudo systemctl list-timers mycenter-backup.timer
```

The activation action requires public registration to be closed, creates the initial backup, runs a restore dry-run, releases the maintenance lock, and enables the timer only if both checks succeed.

Before stopping a running container, a scheduled backup writes a root-only
restart-needed marker under `/run`. Its `ExecStopPost` helper takes the same lock,
terminates only the exact named backup helper if one was stranded, and restarts
MyCenter only when that marker proves the backup stopped a previously running
service. The separately enabled `mycenter.service` reconciles the deployed
runtime after every VPS boot unless destructive maintenance is incomplete.

Inspect the most recent service result:

```bash
sudo systemctl status mycenter-backup.service
sudo journalctl -u mycenter-backup.service --since today
```

Logs must not contain secret values or archive contents.

If a killed backup client leaves `/run/mycenter-backup-restart-needed` or the
exact `mycenter-backup-worker` helper behind, the systemd `ExecStopPost` normally
invokes recovery. For a direct/manual backup, run the same guarded helper:

```bash
sudo /opt/mycenter/deploy/current-tools/backup-recover.sh
```

It takes the maintenance lock, removes only the exact named helper, refuses to
start anything during incomplete destructive maintenance, and restarts MyCenter
only when the restart-needed marker proves a running service had been stopped.

## Manual backup

```bash
sudo /opt/mycenter/deploy/current-tools/backup.sh
```

The command reports only the generated relative archive name. It does not print `.env`, keys, database records, or configuration values.

Before production acceptance, verify:

- the service returned healthy after the backup;
- one archive and matching `.sha256` exist;
- the archive/checksum are not world-readable;
- the checksum validates;
- the archive lists the expected top-level `data`, `files`, `web`, `deployment`, and `state` directories.

## Restore dry-run

Dry-run is the default and is safe for the production volumes:

```bash
sudo /opt/mycenter/deploy/current-tools/restore.sh
```

That selects the newest daily archive. To select one explicitly:

```bash
sudo /opt/mycenter/deploy/current-tools/restore.sh --dry-run \
  daily/mycenter-YYYY-MM-DDTHHMMSSZ.tar.gz
```

The dry-run verifies the checksum, rejects absolute and parent-traversal paths, checks available temporary space, extracts into a mode-700 `/opt/mycenter/restore-tmp/mycenter-restore-dryrun.*` directory outside the backed-up state tree, parses `config.json`, checks the domain and session-key format, and removes the temporary extraction when complete. It refuses to proceed if an exact-name stale directory remains after an abnormal termination, and it never displays the session key. Apply mode then checks a pessimistic bound on the actual backup volume and groups target capacity by the actual Docker-volume filesystem before deleting target contents.

The initial production acceptance test performs only this dry-run.

## Applying a restore

Applying a restore is destructive and is not part of the baseline smoke-check. It requires an explicit archive and confirmation token:

```bash
sudo /opt/mycenter/deploy/current-tools/restore.sh --apply \
  daily/mycenter-YYYY-MM-DDTHHMMSSZ.tar.gz \
  --confirm APPLY
```

The script first runs the full dry-run and creates a new pre-restore backup. It
then stops MyCenter, replaces only the MyCenter data/files/web volumes, restores
the persistent session key by atomically updating that field in the current
config, starts the same versioned image, and waits for health. Only after health
succeeds is the current per-tag config snapshot synchronized. Archived
registration and ACME flags do not overwrite the current security policy. The
script writes `/opt/mycenter/state/maintenance-incomplete` immediately before
volume replacement and runs the restored container with restart policy `no`.
Only after health and metadata synchronization does it restore
`unless-stopped` and remove the marker. A post-mutation failure stops the
container and retains the marker so boot cannot expose partial state.

Operational rules:

- keep the current SSH session open;
- confirm the archive belongs to the expected domain;
- do not restore over a running container by hand;
- never delete or replace Docker volumes outside the reviewed script;
- if restore fails after volume replacement, keep the service stopped for diagnosis and use the automatically created pre-restore backup;
- perform UI, authentication, certificate, Agent identity, and backup checks after any real restore.

## Interrupted restore recovery

If `/opt/mycenter/state/maintenance-incomplete` contains exactly `restore`, do
not delete it and do not start the container manually. Review the journal and
list backup filenames without extracting or printing secret contents:

```bash
sudo cat /opt/mycenter/state/maintenance-incomplete
sudo journalctl --since today | grep -E 'Creating a pre-restore backup|Backup created|Restore'
sudo docker run --rm --network none \
  --volume meshcentral-backups:/backups:ro \
  --entrypoint /bin/sh "mycenter:$(sudo cat /opt/mycenter/state/current-image-tag)" \
  -c 'find /backups/daily -maxdepth 1 -type f -name "mycenter-*.tar.gz" -printf "%f\n" | sort'
```

After identifying the exact pre-restore archive created immediately before the
failed operation, run the guarded recovery:

```bash
sudo /opt/mycenter/deploy/current-tools/restore.sh \
  --recover-incomplete daily/mycenter-YYYY-MM-DDTHHMMSSZ.tar.gz \
  --confirm RECOVER_INCOMPLETE
```

This mode requires the `restore` marker and an explicit archive. It performs the
full checksum/path/domain dry-run, does not back up potentially partial target
volumes again, proves the exact container stopped, checks actual target-volume
capacity, replaces data/files/web, starts with auto-restart disabled, waits for
health, synchronizes the release config, restores `unless-stopped`, and only then
removes the marker. On any failure it retains the marker and makes a best effort
to prove the public container stopped. If the pre-restore archive cannot be
identified with certainty, stop and recover on a disposable host first.

## Database boundary

This procedure is designed for the initial single-node NeDB deployment. If MyCenter later uses MongoDB, PostgreSQL, MySQL/MariaDB, SQLite, AceBase, or another external backend, raw volume snapshots are not sufficient. Add a backend-specific consistent dump/restore procedure and test it before changing production storage.

## Disaster-recovery exercise

After the baseline is stable, schedule a separate exercise on a disposable host:

1. copy and decrypt one off-site archive;
2. validate checksum and paths;
3. restore into new empty volumes and a non-production domain/environment;
4. verify admin login, certificates, device inventory, one Agent reconnect, and files;
5. record recovery time and any manual dependencies;
6. destroy only the disposable environment after verifying its exact path and resources.
