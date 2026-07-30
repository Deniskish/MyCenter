# MeshAgent local connection check

## Scope

| Item | Value |
|---|---|
| Date | 2026-07-30 (Europe/Moscow) |
| Branch | `master` |
| Repository commit | `7ad65483a13fcb41f6fa30541843bdadbab66d1c` |
| Upstream source baseline | `bd48e8a9d36d86cf860fb2a32617ac6e398274e8` |
| MeshCentral | `1.2.4` |
| MeshAgent build | `2026-Feb-15 16:43:44-0800`, Windows x64 |
| Operating system | Microsoft Windows 10 IoT Enterprise LTSC, version `10.0.19044`, x64 |
| Local server URL | `https://localhost:8443/` |
| MeshCentral data directory | `C:\projects\meshcentral-data` |
| Normal server mode | LAN |
| HTTPS bind | `127.0.0.1:8443` |
| MPS | Disabled (`mpsPort: 0`) |

The purpose of this check was to install one original Windows x64 MeshAgent, connect it to the unchanged local MeshCentral server, and verify the read-only opening of Device Details, Terminal, Files and Desktop.

No MeshCentral source file, dependency, firewall rule, system proxy, environment variable or system DNS setting was changed. No command was entered in Terminal, no user file was changed, and no remote desktop input was performed. Passwords, account names, cookies, session tokens, MeshID, ServerID, certificate contents, private keys, database contents and MeshAgent configuration contents were not captured in this report.

## Relevant implementation points

- The server registers the WebSocket endpoint and passes accepted connections to `CreateMeshAgent` in [`webserver.js`](../webserver.js#L7861-L7896) and [`meshagent.js`](../meshagent.js#L18).
- Agent download generation uses `agentAliasDNS` as the connection host in [`webserver.js`](../webserver.js#L6221-L6231).
- A domain with `agentNoProxy: true` adds the `ignoreProxyFile=1` instruction in [`webserver.js`](../webserver.js#L6256-L6259).
- Both temporary settings are documented by the project configuration schema in [`meshcentral-config-schema.json`](../meshcentral-config-schema.json#L381-L385) and [`meshcentral-config-schema.json`](../meshcentral-config-schema.json#L1978-L1982).

## Download and installation

The agents were downloaded manually from the authenticated Device Group UI. Installation and each update were performed with the original MeshAgent installer and manually approved through UAC.

| Attempt | Downloaded file | Size (bytes) | SHA-256 | Connection result |
|---|---|---:|---|---|
| Initial LAN package | `meshagent64-LocalMeshAgentTest.exe` | 3,489,704 | `010398D59247683562A246A31CC0BA86FBABC0575EA25BB935C0FAA1487A0618` | No TCP connection |
| Direct dotted-localhost package | `meshagent64-LocalMeshAgentTest (1).exe` | 3,489,712 | `66BB81B56077DCC256441441743C5CD69617560A169C44E9654436BB2FA763F7` | No TCP connection |
| Direct dotted-localhost, no-proxy package | `meshagent64-LocalMeshAgentTest (2).exe` | 3,489,736 | `3F5BC982E3315831DAA346A0A9F5E90ED8BC1A0A375A1CA7E70B1E69201BD10D` | No TCP connection |
| Numeric IPv4, no-proxy package | `meshagent64-LocalMeshAgentTest (3).exe` | 3,489,736 | `94957BB9E3AFC7DD35A22DB067E6A8BF10666B9965F96AB7B4EE8E223A71115A` | Connected |

All four files reported the same MeshAgent build version. An Authenticode signature was present. Windows returned `UnknownError` for trust validation because the local MeshCentral signing chain was not trusted by the host; this is recorded as a warning rather than as an absent signature.

After the final UAC-approved **Update**:

- service `Mesh Agent` existed, was `Running`, and had automatic start mode;
- process `MeshAgent.exe` existed;
- the installed executable SHA-256 exactly matched the final downloaded executable;
- the installed connection target was verified only as the safe boolean fact “numeric IPv4 endpoint present”; identifiers and configuration contents were not extracted.

## Connection path

```text
MeshAgent service
  -> direct IPv4 TCP on loopback
  -> 127.0.0.1:8443
  -> validated TLS
  -> WebSocket /agent.ashx
  -> MeshCentral agent handler
  -> test device shown Online
```

During 45 consecutive one-second samples, the MeshAgent process had an established direct connection to `127.0.0.1:8443` in every sample. No connection to the configured local proxy port was observed, and no IPv6 or `::1` endpoint was observed.

An independent client connected to `127.0.0.1:8443` with certificate verification enabled, the generated local root CA and SNI `localhost`. TLS authorization passed, and a raw WebSocket upgrade request to `/agent.ashx` returned:

```text
HTTP/1.1 101 Switching Protocols
```

## Results

| Check | Expected result | Actual result | Status |
|---|---|---|---|
| Windows x64 package download | Original MeshAgent installer is downloaded from the Device Group UI | Download completed; final file metadata and SHA-256 were recorded | PASS |
| MeshAgent version | Installer exposes a build version | `2026-Feb-15 16:43:44-0800` | PASS |
| Digital signature presence | Authenticode signature is present when provided by the server | Signature present; local trust validation warning recorded | PASS |
| Standard update | Existing installation is updated through the original installer | UAC-approved **Update** completed manually | PASS |
| Service | `Mesh Agent` service exists and runs automatically | Service present, `Running`, start mode `Auto` | PASS |
| Process | MeshAgent process starts | `MeshAgent.exe` present | PASS |
| Installed binary | Installed executable matches the downloaded package | SHA-256 values identical | PASS |
| Direct IPv4 | Agent connects to the IPv4-only server listener | Stable established connection to `127.0.0.1:8443` | PASS |
| Proxy avoidance | Final package does not contact the configured proxy | No connection to the proxy port in 45 samples | PASS |
| IPv6 avoidance | Final package does not connect to `::1` | No IPv6 or `::1` endpoint in 45 samples | PASS |
| TLS | Local TLS chain validates without disabling verification | TLS authorized with the generated local CA | PASS |
| WebSocket endpoint | `/agent.ashx` accepts an upgrade | HTTP `101 Switching Protocols` | PASS |
| Device registration | Device appears in the intended Device Group | Confirmed manually by the user | PASS |
| Online | Device is shown Online | Confirmed manually by the user | PASS |
| Device Details | Details page opens | Opened successfully; no changes performed | PASS |
| Terminal | Terminal session opens | Opened successfully; no command entered | PASS |
| Files | File browser opens | Opened successfully; no upload, deletion or modification performed | PASS |
| Desktop | Desktop session opens | Opened successfully; no remote input performed | PASS |
| Local-only listener | MeshCentral owns only loopback HTTPS | Only `127.0.0.1:8443` was owned by MeshCentral | PASS |
| MPS disabled | MeshCentral does not open port 4433 | No MeshCentral MPS listener | PASS |
| Redirect disabled | MeshCentral does not open port 80 | No port 80 listener owned by MeshCentral | PASS |
| Runtime configuration restore | Original `config.json` is restored byte-for-byte | Original SHA-256 restored and reloaded successfully | PASS |
| Certificate preservation | Experiment does not regenerate certificates or keys | Deterministic manifest of all 10 relevant certificate/key files was unchanged | PASS |
| Normal mode restore | Server returns to its original mode | Restart reported `MeshCentral v1.2.4, LAN mode` | PASS |
| Correct shutdown | Server releases its listener | Parent and child exited; port 8443 closed | PASS |
| Tracked source files | MeshCentral source remains unchanged | No tracked source diff; only this report is new | PASS |

## Diagnostic conclusion

The controlled A/B test isolated the connection failure to hostname/address selection:

1. With direct `localhost.` and `agentNoProxy: true`, the agent produced no TCP connection.
2. The server remained intentionally bound to IPv4 only at `127.0.0.1:8443`.
3. The final experiment changed only the generated agent host to numeric `127.0.0.1`, retaining the same no-proxy setting and network restrictions.
4. The updated agent immediately established and maintained the IPv4 connection, registered, appeared Online and opened all four tested functions.

The proxy hypothesis was therefore not confirmed. The A/B result establishes that replacing the dotted localhost name with numeric IPv4 resolved the failure under otherwise identical tested settings. The most likely mechanism is that name resolution offered IPv6 `::1` before IPv4 and the tested agent did not establish a fallback connection. A packet trace was not performed, so that specific internal mechanism remains an inference rather than a separately proven fact.

## Temporary runtime configuration and restoration

The successful experiment temporarily used only:

```json
{
  "settings": {
    "cert": "localhost.",
    "keepCerts": true,
    "agentAliasDNS": "127.0.0.1"
  },
  "domains": {
    "": {
      "agentNoProxy": true
    }
  }
}
```

This excerpt contains only the four temporary non-secret values; it is not a copy of the real configuration.

Before the experiment, `config.json` was copied byte-for-byte. The source file and backup both had SHA-256:

```text
F6B6DFBD7EEA74C681733350B916F8D62A3BDD9D83B8E83F302BFEABD19B603D
```

After testing:

- the original file was restored byte-for-byte and its SHA-256 matched;
- `cert` returned to `localhost`;
- `keepCerts`, `agentAliasDNS` and `agentNoProxy` were absent again;
- `portBind`, `WANonly`, HTTPS, MPS and redirect settings retained their original values;
- a verification restart reported LAN mode and only `127.0.0.1:8443`;
- certificate and key files were unchanged;
- the already installed numeric-IPv4 agent reconnected during the verification restart;
- MeshCentral was then stopped correctly;
- the exact temporary configuration backup and the four log files created specifically for this final IPv4 experiment and restoration verification were deleted; earlier baseline logs were outside this cleanup scope.

## Warnings and limitations

- During the temporary dotted-hostname experiment, MeshCentral reported that `localhost.` did not match the retained certificate name `localhost`. This was expected from `keepCerts: true` and disappeared after restoring the original configuration.
- Authenticode trust validation returned `UnknownError` for the locally generated signing chain. Signature presence was confirmed, but public trust was not established.
- Windows logged a service-control warning that MeshAgent is marked as an interactive service. The service remained running and this did not block connectivity.
- Host port 80 was already occupied by an unrelated process named `ENI`; MeshCentral did not own that listener and it was not modified.
- Device registration, Online state and the four UI sections were confirmed manually because no authenticated browser session was available to automation.
- Terminal, Files and Desktop were checked only for successful opening. No command execution, file operation, clipboard transfer, input injection, performance test or prolonged session test was performed.
- The MeshAgent service remains installed and running. With MeshCentral stopped it has no connection; it can reconnect on the next normal server start.

## Final state

```text
Runtime config:                 original bytes restored
Runtime config SHA-256:         original value restored
Temporary config backup:        removed
Final IPv4 experiment logs:      removed
MeshCentral mode on last start: LAN
MeshCentral process:            stopped
Listener 127.0.0.1:8443:        closed
MeshAgent service:              running, automatic
MeshAgent server connection:    none while server is stopped
Source/dependency changes:       none
Git commit/push:                 not performed
```

The local MeshCentral ↔ original MeshAgent compatibility baseline is **PASS**.
