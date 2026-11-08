# Exdock Project Specification

This document describes the current backend and standalone-agent architecture.
It is the maintenance contract for command handling, state ownership,
persistence, events, jobs, and protocol compatibility.

## System boundaries

Exdock is a Phoenix application that manages Docker workloads on connected
nodes. The data flow is:

```text
LiveView -> Operations -> Runtime/Jobs -> Connections -> AgentRuntime -> Docker
         <- ReadModel/Events <- Persistence/Runtime <- result/progress -------
```

The public backend boundaries are:

- `Exdock.Operations` accepts every UI or automation command. Accepted commands
  return `{:ok, operation_id}`; validation failures return `{:error, reason}`.
- `Exdock.ReadModel` returns consistent page, node, settings, repository, and
  activity projections. UI code must not retrieve arbitrary server state.
- `Exdock.Events` publishes revisioned messages on stable cluster, settings,
  repositories, activity, and node topics.
- `Exdock.Runtime` validates commands and routes explicit commands, queries, and
  state mutations. It is the only application command gateway.

LiveViews may format browser values and maintain presentation state, but they do
not call storage modules, the job process, or the server state owner directly.

## Runtime and supervision

Backend processes use local OTP registration. `Exdock.Server.Supervisor` uses
`:rest_for_one` ordering so a failed dependency restarts its downstream
consumers without restarting healthy prerequisites. The supervised backend owns
the vault, broadcasts/events, activity, jobs, runtime state, notifications, and
connections.

`Exdock.Server` is the single authoritative in-memory state owner.
`Exdock.Runtime.Command`, `Exdock.Runtime.Query`, and
`Exdock.Runtime.Mutation` make its accepted interface explicit. There are no
parallel stores or dual writes.

Node identifiers are validated strings at connection, runtime, persistence,
job, protocol, and UI boundaries. Controlled atom inputs are normalized at a
small number of compatibility boundaries; no external or persisted node name is
converted into an atom.

## Commands and operations

An operation ID is created before accepted work is dispatched. The ID is
attached to resulting job details/packages and is included in activity events.
Operation lifecycle events distinguish acceptance from terminal completion.

Runtime commands form a finite vocabulary covering:

- cluster and node refresh;
- image pull, delete, and unused-image cleanup;
- container recreate, start, stop, restart, and logs;
- registry and release refresh;
- user, node, image, container, repository, and imported settings changes;
- named automation workflows and activity cleanup.

State mutations use explicit domain/action values. Arbitrary callbacks and
storage-module `apply/3` dispatch are not command interfaces.

## State and persistence

SQLite remains the durable store. Server startup applies pending Ecto migrations
from `priv/repo/migrations`, including the migration that adds image repository
digests. Upgrades use the existing database rather than requiring a manual data
export and import. Back up the database and its matching `DB_VAULT_KEY` before
upgrading; rollback across schema changes requires the matching older images
and database backup. Container configuration remains encrypted by
`Exdock.Database.Vault` with the existing key contract.

Database modules are the schema adapters. `Exdock.Database.NodeName` owns node
validation and schema/runtime conversion without atom allocation. Cluster
snapshot reconciliation is pure until a persistence plan is built. The plan is
committed transactionally before the reconciled snapshot is published. A
failed transaction leaves the prior in-memory projection authoritative.
Settings, tag, container/image preference, and repository refresh mutations
follow the same persist-before-publish rule; batched writes roll back as one
unit.

Missing or corrupt records are handled at the adapter/reconciliation boundary;
they must not produce a partially published snapshot.

## Jobs, activity, and automation

Jobs are represented by explicit details, specs, targets, packages,
dependencies, and terminal results. The dispatcher preserves:

- local and remote execution;
- deduplication and linking;
- dependency and package completion;
- progress updates and activity projection;
- local task monitoring and crash conversion;
- node-disconnection failure cleanup;
- follow-up refreshes after Docker mutations.

The jobs process owns multi-node completion and retains each unfinished node's
disconnect index until that node responds. It accumulates failures and emits
one terminal result after all targets settle. Refresh updates complete jobs
without depending on the logging consumer; restarting logging cannot block a
workflow continuation.

Multi-spec details dispatch each execution under its generated sub-ID. The
parent detail remains pending until every execution settles, retaining the first
failure. Dependencies, packages, workflow continuations, and the parent terminal
event resolve once at that aggregate boundary.

Container recreation preserves existing anonymous volume identities and accepts
locally available image digests. Auto-removing containers are rejected before
any destructive operation. Adapter exceptions and exits enter the same
compensation path as returned errors, restoring the original container when a
replacement step fails.

Refresh failures use protocol-valid empty result sets so terminal errors cannot
crash command dispatch. Partial snapshots retain known containers and images
whose inspections failed, while confirmed absences still synchronize deletion
markers. Partial failures stop required workflow continuations. Refreshes carry
server-generated dispatch generations; late or duplicate generations complete
without replacing a newer committed node snapshot.

Recreation protection matches Exdock names without case sensitivity and also
honors the Docker label `exdock.protected=true`. Both Compose examples set this
label, and the server and container-manager controls use the same policy.
Resource sampling discards history before a cumulative-counter reset and derives
throughput only from the current sample window.

Dispatch failure terminates the exact failed socket owner before releasing its
node name. Client messages carry their originating handler PID and the state
owner checks current registry ownership before applying them, including messages
queued before a connection was replaced.

A saved-snapshot hydration failure leaves a minimal connected node with its
metadata and saved node settings so a live refresh can repair the cache.
Workflow plans retain their automation flag across individual details and bulk
packages. Registry tag updates reject older observation timestamps before cache
mutation, database writes, or notifications; newer observations may still report
an intentional rollback to an older image.

`Exdock.Server.Jobs.State` is a pure reducer. It returns dispatch, monitoring,
package, and continuation effects to the owning `Exdock.Server.Jobs` process,
which alone starts tasks, communicates with nodes, and publishes lifecycle
events.

Automation uses named workflow continuations instead of callback composition.
The standard workflow performs registry refresh, node refresh, container
updates, and release fetching according to settings. A failed required step
stops downstream work.

`Exdock.Events` is the lifecycle source for UI activity and operation
completion. Notification delivery is a consumer of lifecycle events rather than
a state owner.

## Protocol v4

The standalone client and server share
`lib/exdock_client/exdock_protocol`. TLS transport uses OTP `packet: 4`; the
inner frame is:

```text
<<4::8, message_type::8, payload::binary>>
```

Terms are decoded with Erlang safe decoding and then validated by the receiving
endpoint. Wire messages are explicit maps for:

- `hello`
- `runtime_bundle`
- `ready`
- `command`
- `progress`
- `result`
- `resource_sample`
- `heartbeat`
- `error`

The command allowlist is node refresh, container recreate/start/stop/restart/
logs/resource sampling, and image pull/delete. A message cannot choose an
arbitrary module or function. The client invokes the fixed
`Exdock.AgentRuntime` entrypoint and `Exdock.AgentRuntime.Executor` matches each
command shape explicitly.

Runtime bundles are versioned and carry an aggregate SHA-256 digest. The client
validates the digest and module allowlist before loading any BEAM. A `ready`
message must echo the accepted bundle version and digest before the server marks
the connection initialized. It also reports bounded, validated metadata for the
agent platform, agent version, Elixir version, and OTP release. This metadata is
kept only for the lifetime of the connected node and is not persisted.

Protocol v3 is rejected. Version mismatches stop reconnect loops because v4 is
a coordinated server/client cutover, not a rolling-compatible deployment.

The runtime bundle contains exactly `Exdock.AgentRuntime`,
`Exdock.AgentRuntime.Executor`, `Exdock.AgentRuntime.Size`, and
`Exdock.AgentRuntime.Wire`. The executor delegates Docker work to
`Exdock.ClientLib.Jobs`. Those jobs, image mappers, Docker adapters, shared
protocol code, and connection support are packaged in the agent image and are
not replaced by a runtime bundle. Deploy the matching agent image to every node
when upgrading; a server-only deployment cannot deliver changes to that support
code, even when the wire and agent compatibility versions stay the same.

## Connection lifecycle and ownership

The connection handler validates release version, authentication, node name,
duplicate ownership, bundle readiness, and heartbeat state. The TCP server owns
the node-to-handler routing table. A result or progress message is accepted only
from the handler authenticated for that node; spoofed ownership is rejected.

Disconnecting a node removes connection ownership and fails every active remote
job indexed for that node. A replacement connection cannot silently take over a
live name.

Connection-tree startup clears the authoritative online-node projection through
the normal disconnect lifecycle before accepting new clients. This also fails
pending remote jobs when a registry crash has destroyed the old handler monitors.
Agents may then reconnect and establish fresh ownership.

Registry refresh completion commits partial metadata before publishing its
terminal result. Any failed request or worker exit marks the job failed and
stops required workflow continuations; a complete refresh may continue normally.

## UI contract

Routes, controls, settings, status outcomes, and Docker workflows remain
compatible with the pre-rewrite application. UI implementation may consume new
events or projections, but observable workflow outcomes are the compatibility
boundary. Phoenix authentication, login throttling, account persistence, and
telemetry remain unchanged.

## Verification and release procedure

Remote registry metadata is resolved in-process through the `regc` library.
Production releases therefore do not require a separate registry-client
executable.

Before release:

1. Run `mix precommit` in the repository root. This also verifies and tests the
   standalone client and client runtime.
2. Run `mix test.release` on an isolated test host for each deployed Docker Engine
   version. It builds both production images and checks the server-to-agent
   command path against disposable real Docker resources, including update and
   rollback. `scripts/check-release.sh` runs both gates; `mix test.docker` provides
   the smaller production-adapter suite. See `integration/docker/README.md`.
3. Build server and client releases from the same commit.
4. Start the Docker-backed environment and verify authentication and bundle
   readiness for every node.
5. Exercise refresh, image pull/delete, container lifecycle/logs/resources,
   registry/release fetching, settings import, and scheduled automation.
6. Restore a backup into a separate volume, start the matching server/agent
   pair, and verify that pending migrations apply and existing data remains
   readable with the matching vault key. See `docs/BACKUP_RESTORE.md`.

For a protocol upgrade, publish both images first, deploy the server, and then
immediately deploy every client. Old peers are intentionally rejected. Rollback
must restore a matching server/client pair. See
`lib/exdock_client/exdock_protocol/README.md` for the wire-version checklist.

## Change rules

- Add UI actions through `Operations`, reads through `ReadModel`, and observable
  lifecycle changes through `Events`.
- Keep one authoritative state owner and one persistence write path.
- Do not allocate atoms from node names or other external identifiers.
- Do not add arbitrary RPC, serialized server jobs, or module/function command
  payloads to the agent protocol.
- Preserve the SQLite schema and vault format unless a separately planned,
  tested migration is explicitly required.
- Add characterization tests before changing an existing workflow and keep the
  root precommit pipeline green at every deployable stage.
