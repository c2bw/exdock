# Client Connection Flow

This document describes how a standalone Exdock node agent connects to the
server. It does not describe browser/Phoenix LiveView connections.

## Overview

```text
Client                                      Server
  |                                            |
  |-- TCP + TLS handshake -------------------->|
  |-- hello ---------------------------------->|
  |                                            | validate versions, token,
  |                                            | node name, and uniqueness
  |<-- runtime_bundle -------------------------|
  |                                            |
  | validate and load BEAM modules             |
  | start AgentRuntime                         |
  |-- ready ---------------------------------->|
  |                                            | verify bundle version/digest
  |                                            | mark node online
  |<-- command: node_refresh ------------------|
  |-- result: containers/images -------------->|
  |-- resource_sample(s), if enabled --------->|
  |-- heartbeat every 10 seconds ------------->|
```

## Transport and framing

The agent opens a raw binary TLS socket. Each peer owns a NodeWire session
that negotiates Exdock application protocol version 6 by exact manifest
fingerprint. The session accepts fragmented and coalesced TLS chunks and
validates each application payload against the shared JSON schema. The maximum
application payload is 8 MiB. The server allows up to 128 concurrent TLS
handshakes and gives each five seconds to complete.

TLS uses a server-generated self-signed certificate and neither side verifies a
CA or hostname. The connection is encrypted, but the client does not
cryptographically authenticate the server. The shared authentication key only
authenticates the client to the server.

## Message identifiers

| ID | Message |
|---:|---|
| 9 | `error` |
| 10 | `hello` |
| 11 | `runtime_bundle` |
| 12 | `ready` |
| 13 | `command` |
| 14 | `progress` |
| 15 | `result` |
| 16 | `resource_sample` |

## Handshake

### 1. Client startup

The client reads its node name, server host, server port, and authentication
key from configuration. It retains the authentication key as:

```elixir
:crypto.hash(:sha256, auth_key) |> Base.encode16()
```

### 2. `hello`

After TLS and NodeWire negotiation succeed, the client sends:

```elixir
%{
  "agent_version" => "1.3.0",
  "auth_token" => "<uppercase SHA-256 Base16 token>",
  "node" => "<configured node name>"
}
```

The server accepts `hello` to begin authentication and checks:

1. The agent release matches `~> 1.3.0`.
2. The token matches using constant-time comparison.
3. The node name is valid and available.

The wire protocol version and agent release version are independent.

### 3. `runtime_bundle`

Once authenticated, the server sends the BEAM modules required by the fixed
agent runtime:

```text
Exdock.AgentRuntime
Exdock.AgentRuntime.Executor
Exdock.AgentRuntime.Size
Exdock.AgentRuntime.Wire
```

The payload is:

```elixir
%{
  "version" => "1",
  "digest" => "<lowercase SHA-256 hex>",
  "modules" => %{
    "Elixir.Exdock.AgentRuntime" => beam_bytes,
    ...
  }
}
```

The digest covers the module names and bytecode. The agent maps names through the fixed allowlist.

The client validates the complete digest and requires exactly the four modules
listed above, with no duplicates or additional modules. It loads each module
with `:code.load_binary/3` and starts `Exdock.AgentRuntime`.

This bundle updates only those four modules when the agent connects. The
executor calls `Exdock.ClientLib.Jobs`, whose Docker support code and image
mappers are compiled into the agent image. The connection and shared protocol
code are also packaged in that image. Updating the server does not replace
these dependencies. Pull and recreate every agent with the matching release,
or rebuild and recreate source-built agents, to receive changes such as image
inspection fixes. See the
[agent upgrade guide](../lib/exdock_client/README.md#deployment-and-upgrades).

### 4. `ready`

After the runtime starts, the client echoes:

```elixir
%{
  "bundle_version" => "1",
  "digest" => "<received bundle digest>",
  "metadata" => %{
    "platform" => "linux/amd64",
    "agent_version" => "1.3.0",
    "elixir_version" => "<Elixir version>",
    "otp_release" => "<OTP release>"
  }
}
```

The server requires an exact version and digest match and validates each
required metadata value as a bounded, non-empty string. Unknown metadata keys
are ignored. TLS establishment, authentication, bundle installation, and
readiness must finish within ten seconds.

Only after `ready` is accepted does the server:

- mark the node online;
- publish node-up events;
- restore any persisted node state;
- attach the reported metadata to the connected node's in-memory state;
- enqueue a hidden live Docker refresh.

Agent metadata is live-only. It is removed when the node disconnects and is not
written to the database.

## Initial node refresh

The first normal command is:

```elixir
%{
  "id" => "<job id>",
  "kind" => "node_refresh",
  "args" => [
    %{"retrieve_resources" => true_or_false}
  ]
}
```

The agent queries its local Docker Engine in this order:

1. List and inspect containers.
2. If that succeeds, list and inspect images.
3. If enabled, schedule resource samples for running containers.

The main refresh does not wait for resource samples.

The final refresh result is:

```elixir
%{
  "id" => "<same job id>",
  "kind" => "node_refresh",
  "node" => "<authenticated node name>",
  "data" => %{
    "containers" => %{
      "ok" => [
        %{
          "name" => "...",
          "id" => "...",
          "is_running" => true_or_false,
          "stack_name" => "... or nil",
          "image_tag" => "... or nil",
          "image_id" => "... or nil",
          "inspect" => docker_inspect_data,
          "resources" => nil
        }
      ],
      "errored" => [...]
    },
    "images" => %{
      "ok" => [
        %{
          "id" => "...",
          "name" => "...",
          "tags" => ["..."],
          "digest" => "...",
          "size" => integer,
          "shared_size" => integer,
          "build_date" => "<ISO-8601 timestamp>"
        }
      ],
      "errored" => [...]
    }
  },
  "error" => nil_or_error
}
```

The server verifies that the job ID was dispatched on this connection, the
command kind matches, and the payload's node matches the authenticated node
name before applying the snapshot.

When resource retrieval is enabled, each running container schedules three
samples roughly three seconds apart:

```elixir
%{
  "node" => "<node name>",
  "container_id" => "<container id>",
  "sample" => docker_container_stats
}
```

## Steady-state commands

Every server command has this shape:

```elixir
%{
  "id" => "<job id>",
  "kind" => "<command kind>",
  "args" => [...]
}
```

Allowed command kinds are:

- `node_refresh`
- `container_recreate`
- `image_delete`
- `image_pull`
- `container_start`
- `container_stop`
- `container_restart`
- `container_logs`
- `container_resources`

Argument shapes are explicitly matched by the agent executor. The protocol does
not support arbitrary module/function RPC.

The client can send progress:

```elixir
%{
  "id" => job_id,
  "kind" => command_kind,
  "node" => node_name,
  "data" => progress_data
}
```

and a final result:

```elixir
%{
  "id" => job_id,
  "kind" => command_kind,
  "node" => node_name,
  "data" => result_data,
  "error" => nil_or_error
}
```

## Heartbeats, errors, and reconnection

Both peers tick NodeWire every 500 ms. NodeWire sends ping/pong heartbeats on
a ten-second interval and closes an idle connection after 30 seconds.

When a socket closes, a heartbeat times out, or a protocol error occurs:

- the server handler terminates;
- the node name is removed from the connection registry;
- the node is marked down;
- in-flight jobs receive synthetic `:nodedown` results;
- the client normally reconnects after 20 seconds.

An explicit unsupported agent release, invalid authentication, duplicate node
name, or invalid node name error disables automatic reconnection. A wire
negotiation failure closes the socket. Commands are never replayed on reconnect.

## Primary implementation files

- `lib/exdock_client/lib/connection/client.ex`
- `lib/exdock_client/lib/connection/protocol.ex`
- `lib/exdock_client/exdock_protocol/lib/exdock/protocol/node_wire.ex`
- `lib/exdock_client/exdock_protocol/lib/exdock/protocol/runtime_bundle.ex`
- `lib/exdock/server/connection/server/tcp_supervisor.ex`
- `lib/exdock/server/connection/handler.ex`
- `lib/exdock/server/connection/protocol.ex`
- `lib/exdock/server/server.ex`
- `lib/exdock/agent_runtime/executor.ex`
- `lib/exdock/agent_runtime/wire.ex`
