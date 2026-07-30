# MeshCentral local baseline run

## Scope

| Item | Actual value |
|---|---|
| Check date | 2026-07-30 (Europe/Moscow) |
| Repository | `C:\projects\MyCenter` |
| Branch | `master` |
| Commit | `bd48e8a9d36d86cf860fb2a32617ac6e398274e8` |
| MeshCentral package version | `1.2.4` |
| Node.js | `v24.18.0` LTS, x64 |
| npm | `11.16.0` |
| Node executable | `C:\Program Files\nodejs\node.exe` |
| npm executables | `C:\Program Files\nodejs\npm`, `C:\Program Files\nodejs\npm.cmd` |

This report captures the server baseline before the administrator was created. Statements below that no administrator exists and backup directories are empty describe the end of this stage; the later [UI smoke-check](UI_SMOKE_TEST.md) records the administrator and subsequent runtime backup.

The official Windows x64 MSI `node-v24.18.0-x64.msi` was downloaded from `https://nodejs.org/dist/v24.18.0/`. Its SHA-256 was checked against the official `SHASUMS256.txt`; both values were:

```text
e30cd4ca15529583afe0efc978f1ae3ab3a93c2400c222d0752d17900552ebb3
```

The MSI installed Node.js for all users and added it to the machine `PATH`. No global npm packages were installed. This version satisfies the repository requirement `node >=20.0.0` in [`package.json`](../package.json#L60).

The machine PowerShell execution policy blocks `npm.ps1`. The verification and install were therefore run in a new PowerShell process with process-local policy only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass
```

No user or machine execution policy was changed. Alternatively, `npm.cmd` can be invoked directly without a policy override.

## Environment verification

Commands:

```powershell
node --version
npm --version
where.exe node
where.exe npm
```

Actual output:

```text
v24.18.0
11.16.0
C:\Program Files\nodejs\node.exe
C:\Program Files\nodejs\npm
C:\Program Files\nodejs\npm.cmd
```

## Dependency installation

Command:

```powershell
cd C:\projects\MyCenter
npm ci
```

Result: success, exit code `0`.

```text
added 221 packages, and audited 222 packages in 3s
50 packages are looking for funding
8 high severity vulnerabilities
```

Additional npm messages:

- `glob@10.5.0` was reported as deprecated;
- npm offered an upgrade from `11.16.0` to `12.0.2`;
- npm suggested `npm audit fix` and `npm audit fix --force`.

No update or audit-fix command was run. `package.json` and `package-lock.json` were not intentionally updated.

### Windows bootstrap caveat

The first server process detected the Windows-only runtime modules `node-windows@0.1.14` and `loadavg-windows@1.1.1` as missing. MeshCentral's own bootstrap includes these modules on Windows ([`meshcentral.js`](../meshcentral.js#L4388-L4393)) and installs missing modules with `npm install --save-exact` ([`meshcentral.js`](../meshcentral.js#L4235-L4258)). The first output was:

```text
Installing modules [ 'node-windows@0.1.14', 'loadavg-windows@1.1.1' ]
Module node-windows can't be loaded. Restart MeshCentral.
```

That automatic install modified both manifests. Those automatic changes were reverted to the audited commit immediately; the modules remained in ignored `node_modules`, and the repeated server launch succeeded. Final Git verification confirms that both manifests match `HEAD`.

This is a reproducibility risk on Windows: a fresh `npm ci` removes extraneous modules, so the next first launch may repeat the automatic install and request one restart. Do not commit the resulting manifest changes without a separate dependency-policy decision.

## Safe local configuration

The repository's default data path for a source checkout is the sibling directory `C:\projects\meshcentral-data` ([`meshcentral.js`](../meshcentral.js#L4137-L4146)). To ensure that the baseline never listened on an external interface, this runtime-only configuration was created before launch:

**Path:** `C:\projects\meshcentral-data\config.json`

```json
{
  "$schema": "https://raw.githubusercontent.com/Ylianst/MeshCentral/master/meshcentral-config-schema.json",
  "settings": {
    "cert": "localhost",
    "port": 8443,
    "portBind": "127.0.0.1",
    "redirPort": 0,
    "mpsPort": 0,
    "WANonly": true,
    "exactPorts": true
  },
  "domains": {
    "": {
      "newAccounts": true
    }
  }
}
```

This leaves TLS enabled, uses no production domain, disables the HTTP redirect and MPS listeners, and binds HTTPS only to loopback. Because the certificate common name is `localhost` and has no dot, MeshCentral reports `LAN mode` ([`meshcentral.js`](../meshcentral.js#L1891-L1896)).

## Server launch

Exact command:

```powershell
cd C:\projects\MyCenter
node .\meshcentral.js
```

After the Windows-module bootstrap restart described above, the server started successfully.

| Item | Actual value |
|---|---|
| Local URL | `https://localhost:8443/` |
| Protocol | HTTPS |
| Port | `8443` |
| Bound address | `127.0.0.1` only |
| Data directory | `C:\projects\meshcentral-data` |
| Configuration | `C:\projects\meshcentral-data\config.json` |
| Server database | NeDB, default |

Main first-start messages:

```text
Generating certificates, may take a few minutes...
Generating root certificate...
Generating HTTPS certificate...
Generating MeshAgent certificate...
Generating code signing certificate...
Generating Intel AMT MPS certificate...
MeshCentral v1.2.4, LAN mode.
Code signed MeshService.exe.
Code signed MeshService64.exe.
Code signed MeshServiceARM64.exe.
Code signed MeshCmd.exe.
Code signed MeshCmd64.exe.
Code signed MeshCmdARM64.exe.
Server has no users, next new account will be site administrator.
MeshCentral HTTPS server running on port 8443.
```

The code-signed agent executables were written to the runtime `signedagents` directory. The tracked originals under `agents/` were unchanged in the final working tree.

## HTTPS and UI verification

The page was requested using the generated MeshCentral root CA with certificate validation enabled (`rejectUnauthorized: true`). No insecure TLS option was used.

Actual result:

```text
TLS_AUTHORIZED=true
TLS_SUBJECT_CN=localhost
TLS_ISSUER_CN=MeshCentralRoot-ffe2bd
HTTPS_STATUS=200
CONTENT_TYPE=text/html; charset=utf-8
LOGIN_PAGE=true
CREATE_ACCOUNT_CONTROL=true
```

Therefore:

- the HTTPS listener is reachable locally;
- the generated chain and hostname validate when the generated root CA is supplied;
- the web application returns HTTP 200;
- the login page is rendered;
- the account-creation control is present.

A first attempt with Windows `curl` and the same CA failed only at the Schannel revocation check:

```text
CERT_TRUST_REVOCATION_STATUS_UNKNOWN
```

The test was repeated with Node's TLS client rather than bypassing certificate validation.

## Runtime files and directories

Created in `C:\projects\meshcentral-data`:

```text
config.json
root-cert-private.key
root-cert-public.crt
webserver-cert-private.key
webserver-cert-public.crt
agentserver-cert-private.key
agentserver-cert-public.crt
codesign-cert-private.key
codesign-cert-public.crt
mpsserver-cert-private.key
mpsserver-cert-public.crt
meshcentral.db
meshcentral-events.db
meshcentral-power.db
meshcentral-stats.db
serverstate.txt
signedagents\
```

Created under `signedagents`:

```text
MeshCmd.exe
MeshCmd64.exe
MeshCmdARM64.exe
MeshService.exe
MeshService64.exe
MeshServiceARM64.exe
```

Sibling runtime directories:

```text
C:\projects\meshcentral-data
C:\projects\meshcentral-files
C:\projects\meshcentral-backups
```

`meshcentral-files` and `meshcentral-backups` were empty at the end of the check. `meshcentral-recordings` was not created.

Generated certificate/private-key pairs:

- root CA: `root-cert-private.key` / `root-cert-public.crt`;
- HTTPS server: `webserver-cert-private.key` / `webserver-cert-public.crt`;
- MeshAgent server identity: `agentserver-cert-private.key` / `agentserver-cert-public.crt`;
- code signing: `codesign-cert-private.key` / `codesign-cert-public.crt`;
- Intel AMT MPS: `mpsserver-cert-private.key` / `mpsserver-cert-public.crt`.

Private keys, runtime database files and backups are sensitive runtime data and must not be committed.

## Restart persistence

The server was stopped and started again with the same command:

```powershell
cd C:\projects\MyCenter
node .\meshcentral.js
```

Second-start output:

```text
MeshCentral v1.2.4, LAN mode.
Server has no users, next new account will be site administrator.
MeshCentral HTTPS server running on port 8443.
```

There were no certificate-generation messages on the second start. The configuration and public-certificate SHA-256 hashes remained unchanged, the listener was again exactly `127.0.0.1:8443`, and the validated HTTPS request again returned 200. This confirms that `config.json`, certificates and the NeDB files remained present across the restart.

## Creating the first administrator

No administrator credentials were created during this automated baseline.

Supported interactive method:

1. start the server;
2. open `https://localhost:8443/`;
3. choose **Create account**;
4. create the first account.

The startup message explicitly confirms that the next new account becomes site administrator:

```text
Server has no users, next new account will be site administrator.
```

MeshCentral also implements the local `--createaccount` and `--adminaccount` CLI operations ([`meshcentral.js`](../meshcentral.js#L1026-L1047), [`meshcentral.js`](../meshcentral.js#L1089-L1099)). They were not used in this baseline: `--createaccount` accepts the password as a command-line argument, so the browser registration flow above avoids placing it in shell history or documentation.

## Correct stop and repeat start

For an interactive console, press `Ctrl+C`. MeshCentral handles `SIGINT`, calls `meshserver.Stop()` and exits ([`meshcentral.js`](../meshcentral.js#L4263-L4264)); a correct shutdown prints:

```text
Server Ctrl-C exit...
```

The automated background check sent the equivalent Windows `CTRL_C_EVENT`. Final verification showed no parent process and no listener on port 8443.

Repeat start:

```powershell
cd C:\projects\MyCenter
node .\meshcentral.js
```

## Removing only local runtime data

Warning: this irreversibly deletes local users, device records, events, certificates, private keys, uploaded files and backups. Stop MeshCentral first. Verify the exact paths before removal:

```powershell
$meshRuntimeTargets = @(
    'C:\projects\meshcentral-data',
    'C:\projects\meshcentral-files',
    'C:\projects\meshcentral-backups',
    'C:\projects\meshcentral-recordings'
)

$meshRuntimeTargets | ForEach-Object {
    if (Test-Path -LiteralPath $_) {
        Resolve-Path -LiteralPath $_
    }
}
```

Only after confirming that every resolved path is one of the four explicit targets:

```powershell
$meshRuntimeTargets | ForEach-Object {
    if (Test-Path -LiteralPath $_) {
        Remove-Item -LiteralPath $_ -Recurse -Force
    }
}
```

This does not remove the repository or Node.js. `node_modules` is dependency state rather than MeshCentral runtime data; it can separately be recreated with `npm ci`.

## Warnings and errors

### Expected/non-blocking

- npm reported 8 high-severity dependency findings.
- npm reported deprecated `glob@10.5.0`.
- The generated root is self-signed and is not trusted by Windows globally; it was supplied explicitly for the local TLS test.
- Windows Schannel could not obtain revocation status for the local self-signed CA.
- No administrator exists yet; this is intentional.

### Observed bootstrap issues

- The first launch installed Windows-only runtime modules and asked for restart.
- That bootstrap temporarily modified `package.json` and `package-lock.json`; both were restored exactly to `HEAD`.
- Windows Defender temporarily quarantined three tracked MeshCentral executables while the repository was being inspected. They were restored from the audited commit; Defender settings and exclusions were not changed.
- During development of the background stop procedure, a direct Windows `process.kill(..., "SIGINT")` terminated the child with exit code 1, so the supervisor logged a critical error and restarted it. No `mesherrors.txt` remained in the runtime directory. Subsequent and final shutdowns used a real `CTRL_C_EVENT` and completed with `Server Ctrl-C exit...`.

No application error appeared on the final start, HTTPS check or final shutdown.

## Baseline checklist

- [x] Node.js is at least version 20 (`v24.18.0` LTS).
- [x] `npm ci` completes successfully.
- [x] Server starts from the current checkout.
- [x] Listener is restricted to `127.0.0.1:8443`.
- [x] Web interface opens over HTTPS.
- [x] TLS certificate and hostname validate with the generated root CA.
- [x] Login page is displayed.
- [x] Administrator creation is available; the server confirms the first account becomes site administrator.
- [x] No administrator/password was created or stored by this check.
- [x] `config.json` loads correctly.
- [x] Data, configuration and certificates persist after restart.
- [x] Final shutdown is correct and port 8443 is closed.
- [x] No MeshAgent was installed.
- [x] No firewall or system network setting was changed.
- [x] No production domain or external listener was used.
- [x] `package.json` and `package-lock.json` match `HEAD`.
- [x] No unexpected tracked-file changes remain.
- [x] No files were staged and no commit was created.
