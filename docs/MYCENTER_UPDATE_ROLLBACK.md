# MyCenter Update and Rollback

## Principles

- Updates are image-based and use an exact commit-derived tag.
- MeshCentral self-update remains disabled.
- Source arrives through a verified Git bundle; production does not require GitHub or a push.
- Every update starts with a consistent backup.
- The previous working image remains available at least through the next successful backup.
- Image rollback does not automatically roll database contents backward.

## Prepare a new revision

On the trusted development workstation:

1. build and test changes on `feature/mycenter-production`;
2. review staged files and create the intended commits;
3. confirm no secrets, runtime data, `.env`, bundles, or Defender-caused `agents/MeshCmd*.exe`/`agents/MeshService*.exe` deletions are committed;
4. create and verify a new bundle outside the repository;
5. transfer it through SCP using the existing key-authenticated channel.

On the VPS, before replacing or switching the current checkout, create and
validate a recovery point using the scripts that belong to the deployed image:

```bash
sudo /opt/mycenter/deploy/current-tools/backup.sh
sudo /opt/mycenter/deploy/current-tools/restore.sh --dry-run
```

Stop if either command fails. This pre-switch recovery point prevents a defect
or incompatibility in the incoming maintenance scripts from being the only
backup path. Then import the reviewed commit into `/opt/mycenter/src` without
discarding local state. Before update:

```bash
cd /opt/mycenter/src
git status --short
git log -5 --oneline --decorate
for agent_blob in MeshCmd.exe MeshCmd64.exe MeshService.exe MeshService64.exe; do
  git cat-file -e "HEAD:agents/${agent_blob}"
done
```

The checkout must be clean and HEAD must be the approved release commit.

## Update

```bash
sudo /opt/mycenter/src/deploy/update.sh
```

The script:

1. acquires the shared MyCenter maintenance lock used by deployment, backup, and restore;
2. runs a second, immediate backup with the active release's root-owned
   `current-tools/backup.sh`;
3. derives a new 12-character commit tag;
4. builds `mycenter:<new-tag>` without overwriting the old image;
5. snapshots the exact current config, Compose definition and config template;
6. updates the protected runtime image tag and renders candidate configuration without printing secrets;
7. disables Docker auto-restart on the old runtime, writes the persistent
   incomplete-maintenance marker, and atomically installs candidate definitions;
8. starts the new image with restart policy `no` and waits for health;
9. records current/previous tags plus version-paired config, Compose, template,
   and root-owned operational tools under `/opt/mycenter/state/releases/<tag>`;
10. atomically selects the new `current-tools`, verifies `unless-stopped`, and
    only then removes the maintenance marker.

After success, run the trusted HTTPS health check and UI smoke-check. For changes that could affect agents, verify one original MeshAgent reconnects without creating a duplicate device.

## Automatic failure handling

If the new image fails health:

- the pre-update rendered config is restored;
- the protected `.env` image tag is returned to the old tag;
- the deployed Compose definition is returned to the previous known-good copy;
- the deployed config template and image-tag metadata are restored;
- Compose starts the old image with restart policy `no`;
- the script waits for old-image health and reports that the update was rolled back.
- the previous operational-tool link and `unless-stopped` policy are restored
  before the persistent marker is removed.

If the old image also fails, root-only recovery snapshots are retained in
`/opt/mycenter/state`; stop automated mutation and diagnose logs, volume
permissions, configuration, certificates, and database migration state. Do not
perform an automatic data restore. The public container is stopped and
`maintenance-incomplete` remains, so `mycenter.service` fails closed at boot.

## Interrupted update or rollback recovery

After a power loss or failed automatic recovery, inspect only non-secret state:

```bash
sudo cat /opt/mycenter/state/maintenance-incomplete
sudo cat /opt/mycenter/state/current-image-tag
sudo readlink -f /opt/mycenter/deploy/current-tools
sudo docker inspect --format '{{.Config.Image}} {{.State.Running}} {{.HostConfig.RestartPolicy.Name}}' mycenter
```

If the marker says `update`, `rollback`, or `recovery`, restore the exact release
recorded by `current-image-tag` with the guarded action:

```bash
sudo /opt/mycenter/deploy/current-tools/update.sh \
  --recover-current RECOVER_CURRENT
```

The action validates the recorded image, config security policy and per-release
tools, stops the exact container with a Docker fallback, atomically restores the
recorded Compose/template/config and `.env` tag, starts with restart policy `no`,
waits for health, restores `unless-stopped`, and only then removes the marker.
It refuses a marker that says `restore`; use the operation-specific recovery in
[`MYCENTER_BACKUP_RESTORE.md`](MYCENTER_BACKUP_RESTORE.md). Never delete the
marker manually before the container, health, active tools and restart policy
have all been proven consistent.

## Manual image rollback

The previous recorded image can be selected with:

```bash
sudo /opt/mycenter/deploy/current-tools/update.sh --rollback
```

The rollback script verifies that the previous image and its per-tag
Compose/template/config/tool snapshot exist, creates a fresh backup, installs
that version's runtime definition, reconciles the config with the current
protected session key, ACME mode and permanent registration guard, starts it
with auto-restart disabled, waits for health, atomically selects its tools,
restores `unless-stopped`, and swaps the current/previous tag records. A pending
OS reboot blocks a new update but does not block this emergency rollback.

Run afterward:

```bash
cd /opt/mycenter/deploy
sudo docker compose --env-file .env \
  -f /opt/mycenter/deploy/docker-compose.yml ps
sudo /opt/mycenter/deploy/current-tools/healthcheck.sh
```

Then verify login, main UI sections, registration state, database continuity, Agent Online/reconnect, and backup timer status.

Image rollback does not rewrite `/opt/mycenter/src`; its `HEAD` may therefore
remain newer than the deployed image tag. Runtime Compose/template/config and
operational tools are selected from the per-tag release snapshot, and the protected `.env` plus
`state/current-image-tag` are the authoritative active-version records. A later
roll-forward runs the reviewed candidate update again.

## Data compatibility

An older image over newer data is safe only when the underlying MeshCentral release supports that direction. The update script deliberately does not restore old data during image rollback.

If an update performs an incompatible data migration:

1. keep the service stopped or on the last diagnostically safe state;
2. identify the pre-update backup;
3. run `/opt/mycenter/deploy/current-tools/restore.sh --dry-run` against it;
4. obtain explicit operator approval for a destructive restore;
5. use the documented `--apply ... --confirm APPLY` workflow;
6. repeat the full production smoke-check.

## Image retention

Do not prune the current or previous working image automatically. Remove older images only after:

- the new version has passed health, UI, Agent, persistence, and backup checks;
- at least one subsequent backup and restore dry-run succeeded;
- the exact retained current and previous tags are recorded;
- the removal target is explicitly listed and reviewed.

Never use a broad Docker prune as part of an automated update.
