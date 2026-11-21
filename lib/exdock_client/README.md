# Exdock Client

Standalone client release for an Exdock node.

The client connects to the Exdock server over SSL, authenticates with the shared
`AUTH_KEY`, validates and loads a SHA-256-protected runtime bundle, and executes
only validated NodeWire commands through the fixed `Exdock.AgentRuntime` entrypoint.
The server cannot request arbitrary module/function execution.

## Configuration

Runtime configuration is read from environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `NODE_NAME` | `example_name` | Unique client node name shown by the server. |
| `SERVER_HOST` | `localhost` | Exdock server host. |
| `SERVER_PORT` | `5000` | Exdock server TCP port. |
| `AUTH_KEY` | Required in production | Shared secret used to authenticate the client. |

Both the server and client hash `AUTH_KEY` with SHA-256 before comparing it.
Production releases refuse to start when `AUTH_KEY` is missing or empty. Use a
unique, randomly generated value and configure the same value on the server and
every client.

`NODE_NAME` must be unique per connected client. It can be up to 64 characters
long, must start with a letter or number, and may contain only letters, numbers,
underscores, dots, and dashes. The reserved name `local` is not allowed.

Valid example names:

```text
nas-01
docker_host_1
node-01.eu_west
```

Invalid example names:

```text
local
my node
_node
node@host
host:5000
```

## TLS And Trust

The server generates a fresh self-signed certificate at startup. The agent
accepts that certificate with `verify: :verify_none` and requires no CA file.
An optional server certificate and key can be supplied through
`NODEWIRE_CERT_FILE` and `NODEWIRE_KEY_FILE`.

TLS encrypts the connection. Deploy agents on a trusted private network or
authenticated VPN that establishes the server's identity. The shared
`AUTH_KEY` authenticates the agent to the server. The deployment assumptions
are documented in the
[unverified TLS accepted-risk specification](../../docs/UNVERIFIED_TLS_ACCEPTED_RISK_SPEC.md).

## Development

Wire format, compatibility, and upgrade procedures are documented in the
[shared protocol contract README](exdock_protocol/README.md).

For a focused client-only check, run the nested pipeline from this directory:

```powershell
mix precommit
```

Before committing or deploying, run the authoritative pipeline from the
repository root. It includes the client and client-runtime checks:

```powershell
cd ../..
mix precommit
```

## Deployment and upgrades

Server and client releases must be built from a compatible commit and upgraded
together. Protocol v3 and older versions are rejected. A version mismatch stops
automatic reconnect attempts, so this is not a rolling-compatible deployment.

1. Build and publish both release images.
2. Deploy the server.
3. Immediately deploy every client node.
4. Verify that each node authenticates, accepts the runtime bundle, sends
   `ready`, and completes a refresh.

Docker workloads continue running while an agent is disconnected, but Exdock
cannot manage that node. Rollback requires restoring a matching server/client
pair.

Updating only the server does not update the full agent. On connection, the
server delivers exactly four modules:

- `Exdock.AgentRuntime`
- `Exdock.AgentRuntime.Executor`
- `Exdock.AgentRuntime.Size`
- `Exdock.AgentRuntime.Wire`

The executor delegates Docker work to `Exdock.ClientLib.Jobs`. Jobs, image
mappers, Docker adapters, connection handling, and shared protocol code remain
the versions packaged in the agent image. For example, fixes to dangling-image
inspection require replacing that image even if the runtime bundle has updated
successfully and the compatibility versions have not changed.

For the standalone Compose example, select the matching image release and run
these commands on each agent host using its existing configuration:

```sh
docker compose pull client
docker compose up -d client
```

For source deployments, rebuild and recreate each agent. Build the client image
from the repository root so its packaged support code is included:

```powershell
docker build -f lib/exdock_client/Dockerfile .
```
