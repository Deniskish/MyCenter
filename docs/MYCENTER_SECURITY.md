# MyCenter Security Baseline

## Scope

This document defines the minimum security posture for the MyCenter production service. MyCenter keeps the MeshCentral server and the original, protocol-compatible MeshAgent. The rebranding and pixel interface do not alter `agent.ashx`, `meshrelay.ashx`, MeshID, ServerID, NodeID, the agent handshake, authorization checks, or relay channels.

## Network boundary

- Publish only `80/tcp` for ACME HTTP-01 and HTTP-to-HTTPS redirection, and `443/tcp` for HTTPS/WSS.
- Keep MPS disabled with `mpsPort: 0`; do not expose 4433 unless a later, separately reviewed Intel AMT use case requires it.
- Do not publish database, Docker API, Node inspector, or container-internal management ports.
- Determine and allow the real SSH port before enabling UFW. Verify a second key-authenticated SSH session before changing firewall state.
- Treat Docker-published ports and UFW as separate controls: the Compose file must not publish any port that UFW is expected to hide.

## TLS and DNS

- `cert` and the ACME name must exactly match the production FQDN.
- Validate the DNS A record before deployment. Remove an AAAA record unless IPv6 is intentionally configured and tested end to end.
- Run Let's Encrypt staging first, then remove only the staging certificate artifacts while the container is stopped and switch to production issuance.
- The initial deployment rejects production ACME mode; production issuance is reachable only through the explicit promotion action.
- If production issuance or trusted validation fails, the deployment workflow returns the protected runtime configuration to staging and attempts to restore staging health before stopping for diagnosis.
- Never use `-k`, `--insecure`, disabled certificate validation, certificates issued for an IP address, or `skipChallengeVerification: true`.
- Production health checks validate the public hostname and trusted chain. A TCP-only check is acceptable only during the staging phase and is not production proof.

## Authentication and sessions

- Keep `newAccounts: false` throughout bootstrap. Upstream permits the first account regardless, so protect it with a generated 256-bit `newAccountsPass` token stored only in the root-owned runtime `.env`.
- Enter the bootstrap token only over trusted production HTTPS. After a successful first-administrator login is confirmed, use the explicit `ADMIN_CREATED` closure confirmation. The action rotates the disclosed value to a new, unrevealed 256-bit permanent guard, marks bootstrap closed, recreates the container, and verifies health. The guard remains in the protected `.env` and rendered config because removing it would make an empty or damaged user database fall back to the upstream unprotected first-user exception.
- Do not create or record administrator passwords through deployment scripts or shell history.
- Enable 2FA from the UI. Never copy the 2FA secret or recovery codes into tickets, chat, logs, or Git.
- Keep `allowLoginToken: false` and `passwordRequirements.loginTokens: false` unless a separately reviewed integration requires login tokens.
- Use a cryptographically random persistent `sessionKey` generated on the VPS. Store it only in the mode-600 runtime `.env`; rendered `config.json` must also be readable only by the deployment owner and container user.
- Keep explicit password complexity and invalid-login throttling enabled.

## Container hardening

- Build from the exact MyCenter commit with Node.js 24 LTS and a versioned image tag.
- Run the application as fixed UID/GID 10001 where supported; grant only `NET_BIND_SERVICE` and drop all other capabilities.
- Enable `no-new-privileges`, a read-only root filesystem, and a size-limited `/tmp` tmpfs after the first permissions smoke-check.
- Mount only the required persistent data, files, backups, web override, and read-only config paths. Never mount the Docker socket.
- Disable MeshCentral self-update. Updates occur by building and selecting a new versioned image.
- Use `restart: unless-stopped` and `SIGINT` with a grace period for shutdown.
- Update and destructive restore temporarily create/recreate the container with
  restart policy `no`. They restore and verify `unless-stopped` only after health
  and release metadata agree; a persistent host marker blocks systemd boot
  reconciliation while destructive maintenance is incomplete.
- Set process `umask 077` before Node.js starts, verify generated private-key modes after staging, and keep the backup volume out of the application container.

## Secrets and sensitive data

Never commit or print:

- `.env` or `sessionKey`;
- the temporary first-account registration token or permanent registration guard;
- SSH private keys or passphrases;
- administrator passwords, cookies, session tokens, MeshID, ServerID, NodeID, or `.msh` contents;
- private certificate keys, database contents, 2FA secrets, or recovery codes;
- backups or transfer bundles.

The repository ignores deployment `.env`, rendered runtime config, Git bundles, and local deployment runtime artifacts. A secret scan and explicit staged-file review are required before every commit.

## Agent boundary

- Distribute the original MeshAgent generated by the compatible server.
- Do not modify its handshake, certificate verification, identity storage, update protocol, or command channels.
- First production Agent smoke-check is observation-only: Details, Terminal, Files, and Desktop may be opened, but no terminal command or user-file modification is performed.
- Verify the agent uses the intended HTTPS/WSS domain and does not create a duplicate device after server restart.

## Data protection and backup

- Persist server data, files, certificates, databases, custom web data, and backups outside the container writable layer.
- Backup archives and checksum files must be owner-only; backup directories must not be world-readable.
- Deployment, backup, update, and restore serialize through one shared maintenance lock; nested backup checks reuse the already-held lock.
- Scheduled backup and recovery execute root-owned, per-release scripts selected
  through `/opt/mycenter/deploy/current-tools`, never a mutable SSH-user checkout.
- Backup crash recovery is conditional on an owner-only `/run` marker proving
  that the backup stopped a previously running container; it does not
  unconditionally start an intentionally stopped service.
- A local backup on the same VPS is recovery from operational mistakes, not disaster recovery. Add an encrypted off-site copy with separately managed credentials after the baseline deployment.
- Restore defaults to verification and extraction into a protected temporary directory. Production application requires an explicit operator action, a pre-restore backup, and a stopped service; it atomically restores the session-key field while preserving current registration and ACME policy instead of trusting archived flags.

## Dependency findings

The local audit is read-only; `npm audit fix` was not run.

- A clean `npm ci` followed by `npm audit --omit=dev` reported one
  high-severity package finding for locked `brace-expansion@2.1.2`, reached
  through the existing `archiver` and `express-handlebars` dependency trees.
- The Windows local bootstrap subsequently added upstream runtime packages `node-windows@0.1.14` and `loadavg-windows@1.1.1` only inside the temporary smoke snapshot. Auditing that temporary tree reported four findings: one high and three critical, with the critical path through the old `node-windows` dependency chain.
- The Linux production image does not require those Windows-only runtime packages. Its final dependency inventory and `npm audit --omit=dev` output must be captured on Ubuntu before release.

These findings require dependency-risk review; they do not authorize an automatic lockfile or upstream dependency update in this project stage.

## Operational checks

Before declaring production ready, verify:

- trusted HTTPS and HTTP redirect;
- only the expected SSH, 80, and 443 listeners are public;
- account registration is closed;
- container health and restart persistence;
- no secrets in container logs;
- backup creation, archive listing, checksum validation, and restore dry-run;
- an Online original MeshAgent and working Details, Terminal, Files, and Desktop;
- clean local Git status except explicitly documented artifacts, and no push.
