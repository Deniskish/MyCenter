# MeshCentral UI smoke-check

## Test scope

| Item | Value |
|---|---|
| Date | 2026-07-30 (Europe/Moscow) |
| Branch | `master` |
| Commit | `bd48e8a9d36d86cf860fb2a32617ac6e398274e8` |
| MeshCentral | `1.2.4` |
| Node.js | `v24.18.0` |
| URL | `https://localhost:8443/` |
| Server mode | LAN |
| HTTPS bind | `127.0.0.1:8443` |
| Data directory | `C:\projects\meshcentral-data` |
| Database | NeDB |
| MPS | Disabled (`mpsPort: 0`) |

The check used the unchanged server at the audited commit. No MeshAgent was connected or installed, no firewall or Defender setting was changed, and no dependency update or branding change was performed.

One local administrator was created through the first-account registration UI. The test account identifier, password, password hash, cookies and session data were not captured in this document or emitted by the automated checks.

## Method

The server was launched from the checkout:

```powershell
cd C:\projects\MyCenter
node .\meshcentral.js
```

The initial registration and UI navigation were completed manually in the local browser because the browser tab was not available to automation. The user confirmed that the requested UI flow worked. Server-side checks independently inspected only aggregate, non-sensitive facts:

- number of users, site administrators and nodes;
- HTTP behavior without a session;
- login behavior with an intentionally incorrect password;
- active listeners and owning processes;
- hashes and timestamps of `config.json` and public certificates;
- Git status.

No database document, account identifier, credential, cookie, token, private key or certificate content is included below.

## Results

| Check | Expected result | Actual result | Status |
|---|---|---|---|
| Server start | MeshCentral starts without application error | `MeshCentral v1.2.4, LAN mode`; HTTPS listener started | PASS |
| Local-only exposure | Only loopback HTTPS is owned by MeshCentral | The only MeshCentral listener was `127.0.0.1:8443` | PASS |
| First administrator registration | First local account becomes site administrator | Registration completed manually; sanitized DB check found exactly 1 user and 1 site administrator | PASS |
| Successful authentication | Valid local administrator can sign in | Main page opened after registration; user confirmed the UI flow works | PASS |
| Main page | Authenticated application shell loads | Confirmed manually | PASS |
| Device inventory | Empty list is displayed before any agent is connected | Confirmed manually; sanitized DB check found 0 node records | PASS |
| My Account | Account section opens | Confirmed manually | PASS |
| Site/server settings | `My Server → General` opens | Confirmed manually | PASS |
| Event journal | `My Events → Events` opens | Confirmed manually | PASS |
| User management | `My Users → Users` opens | Confirmed manually | PASS |
| Administrator visible | Created administrator is listed | Confirmed manually; aggregate DB check found 1 site administrator | PASS |
| Logout | Logout returns to unauthenticated state | Confirmed manually | PASS |
| Access after logout | Protected panel is unavailable after logout | Confirmed manually; anonymous HTTP request independently returned the login page, not the main panel | PASS |
| Repeated login | Administrator can sign in again | Confirmed manually without exposing the password | PASS |
| Wrong password | Incorrect password must not create a session | HTTP login returned the login page with no panel; one expected `authfail` event was recorded | PASS |
| Anonymous root request | Unauthenticated request cannot access dashboard | HTTPS response was 200 with login UI and without the authenticated main panel | PASS |
| Persistence across restart | User and administrator rights survive restart | After a correct stop/start, aggregate state remained 1 user, 1 site administrator and 0 nodes; the server no longer printed the first-user message | PASS |
| Database retained | Existing logical NeDB data is not reset | User, administrator rights and event data remained after restart | PASS |
| Configuration retained | `config.json` is loaded without unexpected change | SHA-256 and last-write timestamp were identical before and after restart | PASS |
| Certificates retained | Certificates are not regenerated | Public-certificate SHA-256 values and timestamps were unchanged; restart log contained no generation messages | PASS |
| MPS disabled | MeshCentral does not open the MPS listener | No MeshCentral listener on port 4433; configuration remained `mpsPort: 0` | PASS |
| HTTP redirect disabled | MeshCentral does not open its HTTP redirect listener | MeshCentral owned only port 8443; no MeshCentral listener on port 80 | PASS |
| External interfaces | MeshCentral does not listen on `0.0.0.0`, `::` or a LAN address | Only `127.0.0.1:8443` was owned by MeshCentral | PASS |
| Tracked files | Source tree has no unexpected tracked changes | `git diff --name-only` and staged diff were empty | PASS |
| Correct shutdown | Ctrl+C invokes normal shutdown and releases listeners | Log ended with `Server Ctrl-C exit...`; parent process exited and ports 8443/4433 were closed | PASS |

## Open ports during the run

MeshCentral-owned listener:

```text
TCP 127.0.0.1:8443
```

No other listener was owned by either the MeshCentral supervisor or child process. Specifically:

```text
MeshCentral port 80:   closed
MeshCentral port 4433: closed
```

The host already had an unrelated process named `ENI` listening on `0.0.0.0:80` (PID 5764). It was not a MeshCentral process, was not created or changed by this test, and no firewall action was taken.

## Runtime persistence evidence

The following values remained identical across the tested restart:

- SHA-256 and timestamp of `config.json`;
- SHA-256 and timestamp of the root public certificate;
- SHA-256 and timestamp of the HTTPS public certificate;
- SHA-256 and timestamp of the MeshAgent server public certificate;
- SHA-256 and timestamp of the code-signing public certificate;
- SHA-256 and timestamp of the MPS public certificate.

NeDB can compact by atomically replacing its physical file, so the filesystem creation timestamp of `meshcentral.db` changed during the run. This is not evidence of a reset: after restart, the same logical account, site-administrator rights and event history remained. The database file was not deleted by the test.

An automatic runtime backup was created:

```text
C:\projects\meshcentral-backups\meshcentral-autobackup-2026-07-30-10-27.zip
```

The archive is sensitive runtime data because it may contain configuration, database records and keys. Its contents were not inspected and it must not be committed.

## Negative checks

| Negative case | Evidence | Status |
|---|---|---|
| Incorrect password authenticates | Intentional bad-password POST returned login UI and no protected panel | PASS |
| Anonymous user sees dashboard | Anonymous HTTPS GET returned login UI and no authenticated main panel | PASS |
| Logged-out browser retains access | User manually confirmed protected UI was unavailable after logout | PASS |
| Server exposed externally | Listener ownership showed only `127.0.0.1:8443` | PASS |
| MPS unexpectedly enabled | No listener on 4433 and no other MeshCentral listener | PASS |
| HTTP redirect unexpectedly enabled | No port 80 listener owned by MeshCentral | PASS |

The incorrect password was synthetic and unrelated to the valid administrator password. The valid password was never requested or recorded.

## Warnings and observations

- The generated HTTPS chain is local/self-signed; a browser may show a trust warning until the generated root CA is trusted locally.
- One `authfail` event is expected from the deliberate wrong-password test.
- NeDB physical file timestamps are not stable identifiers because compaction may replace a file atomically.
- MeshCentral created an automatic backup during the run.
- Port 80 is occupied by an unrelated pre-existing `ENI` process; this did not affect loopback port 8443.
- The final server stdout/stderr contained no application error. The final server message was `Server Ctrl-C exit...`.

## State after shutdown

```text
MeshCentral parent process: not running
MeshCentral child process:  not running
Listener 127.0.0.1:8443:    closed
MPS listener 4433:          closed
```

Runtime data, the administrator and the automatic backup were intentionally retained for later local testing.

## Known limitations

- Detailed UI actions were manually confirmed by the user because the open browser session was not available to browser automation.
- The test did not inspect screenshots, layout at multiple resolutions, accessibility, browser console warnings or network waterfall data.
- The test did not expose, export or validate cookies/session tokens.
- The test did not connect MeshAgent and therefore did not exercise device details, remote desktop, terminal or file transfer.
- No second non-admin account was created, so role-boundary testing beyond anonymous access was not performed.
- Email, 2FA, SSO, password reset, backup restore and production-certificate flows were not tested.
- The unrelated host listener on port 80 was observed but not diagnosed or modified.

## Conclusion

The local UI baseline is **PASS** for first-administrator creation, authentication, core administrative navigation, empty inventory, logout/re-login, anonymous and bad-password rejection, persistence across restart, loopback-only exposure and clean tracked source state.
