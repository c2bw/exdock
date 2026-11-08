# Real Docker command checks

These tests use real Docker Engine requests. They complement the fake-adapter
unit tests and deliberately live outside `test/`, so ordinary `mix test` stays
fast and does not require Docker.

From the repository root:

```sh
mix test.docker   # production agent adapter against a disposable real Engine
mix test.release  # the same checks plus packaged server -> TLS agent -> Engine
```

Install the standalone client dependencies first, as for the existing nested
precommit pipelines:

```sh
mix deps.get
(cd lib/exdock_client_runtime && mix deps.get)
(cd lib/exdock_client && mix deps.get)
```

Run `scripts/check-release.sh` before deploying. It executes `mix precommit` and
`mix test.release` in separate BEAM instances. The GitHub Actions workflow
`Docker command release gate` also runs the release suite after precommit.
Configure its `docker-release` job as a required repository check if merges must
be blocked on Docker compatibility; branch protection is a repository setting.

## Isolation and prerequisites

Use Linux with a local Unix-socket Docker Engine, support for privileged
containers, the Docker buildx plugin, GNU `timeout`, and enough disk space to
build both production images. Image downloads and release builds need internet
access. Initial builds can take several minutes.

Each invocation creates one uniquely named, labelled Docker-in-Docker container.
Its unauthenticated API is bound to a random **parent-host loopback** port; no
production socket is mounted into it. All application containers, fixture images,
networks, volumes, and the local registry live inside that nested daemon. The
release agent mounts only the nested daemon's socket. The harness rejects remote
Docker endpoints rather than guessing where published ports are reachable.

The harness removes its own daemon and anonymous storage volumes on normal exit,
test failure, and setup failure. It never runs host-wide prune commands. A forced
kill or host crash can prevent cleanup; the printed daemon name identifies the
single container to remove with `docker rm -fv <printed-name>`.

The suite fails if Docker or required setup is unavailable; the selected suite
never reports success by silently skipping real-engine tests. `test.docker`
explicitly excludes release-only cases; `test.release` runs both groups.

## Contract checked

Both groups independently use Docker CLI inspect and in-container HTTP checks to
verify outcomes, instead of trusting the API adapter's success response:

- Start and stop, including repeated requests, and restart without changing ID.
- Restart auto-removing (`--rm`) containers without deleting their identity or data.
- Pull a changed registry tag while leaving the running container untouched.
- Recreate running and stopped containers with named and anonymous volumes.
- Preserve environment, command, labels, healthcheck, exposed ports, port
  bindings (including an explicit host port), restart policy, network aliases,
  and persistent data; delete the old container.
- Update image A to B and verify that the application actually serves B.
- Report missing-image pulls as errors, and prevent recreation when update's
  prerequisite pull fails.
- Restore the original container, network, name, and data after Docker rejects
  the replacement's start, with no abandoned replacement left behind.
- Recreate containers using host networking.
- Discover untagged local images, retain their running containers in the server
  snapshot, and restart/recreate them through both adapter and release paths.
- Preserve anonymous volume data when another bind has a similar destination
  (`/data` alongside `/data2`), and recreate containers launched by image ID.
- Roll back replacements that start successfully but exit or become unhealthy.
- Execute a stop submitted during recreation against the finished replacement.
- Disconnect during a live recreation, defer runtime replacement while work is
  active, reconnect, and verify the resulting container and data.

The release group builds the repository's actual Dockerfiles, boots both
production releases, waits for authenticated agent readiness, and submits typed
commands using the existing coordinator API over release RPC. It waits for the
matching terminal operation event and checks failure propagation through pull /
recreate job packages. It adds no test HTTP endpoint to the application. This
covers the runtime command path, not browser clicks or every possible Docker
configuration.

The disposable agent explicitly enables named Erlang distribution for its
release RPC recovery checks. The production agent default remains
`RELEASE_DISTRIBUTION=none`; its release template honors an explicit override.

Container start, stop, restart and recreation commands are queued in arrival
order per container name on each agent. Other containers and read operations can
continue concurrently. The server does not coalesce repeated mutations across
conflicting work (for example, `stop -> start -> stop`).

Container locks belong to command workers, so dispatcher replacement cannot
start a conflicting mutation while an old worker is still finishing. Runtime
bundle installation defers with `runtime_busy` while registered command workers
are active, then retries through the normal reconnect path. Background resource
samples do not block installation. Runtime messages are
sent only after authentication and initialization finish.

Server and agent share a 30-minute Docker request budget. The server allows
31 minutes without job activity, and the agent reports queued/running command
activity every 30 seconds. Matching activity renews the server timer without
changing job identity or refresh generation. If activity stops and the deadline
expires, the connection closes; reconnection waits for agent work to finish
before a fresh snapshot reconciles Docker state. Timeout does not forcibly kill
an in-flight recreation or undo Docker operations already accepted by the Engine.

Every terminal container mutation, including a failure or incomplete rollback,
schedules a node refresh so the dashboard reflects Docker's resulting state.
If recreation succeeds but the old container cannot be deleted, the operation
remains successful and retains a cleanup warning in the status dashboard with
the leftover container name. Clearing alerts dismisses that warning.

Resource sampling permits one active request per container. A new refresh
replaces pending work, waits for the active request, and discards its superseded
result. Further samples are scheduled after completion, and stopping the
scheduler cancels its sample workers.

Before deleting a running original, recreation now waits for the replacement to
be healthy when it has a Docker healthcheck. Without a healthcheck it verifies
that the replacement stays running for one second. Exited/unhealthy replacements,
inspection failures and readiness timeouts trigger rollback. Stopped originals
remain stopped and do not undergo readiness checks. The agent environment variable
`RECREATE_READINESS_TIMEOUT_MS` sets the deadline (default `30000`); use a larger
value for slow startup healthchecks, or `0` to disable readiness verification.
This is a startup check; it cannot guarantee continued application health or
undo changes an application makes to shared volume data during startup.

A local registry and controlled fixture images provide deterministic image
updates. Failure images deliberately lack the original executable, exit after a
successful start, or fail their healthcheck. Only infrastructure pulls/builds have
bounded retries; operations under test are not retried to mask failures. Commands,
readiness waits, and operation completion all have deadlines.

## Engine versions and diagnostics

The default is `docker:29.8.1-dind`. Run the suite for each Engine you deploy:

```sh
EXDOCK_TEST_DIND_IMAGE=docker:29.8.1-dind mix test.release
```

The workflow's manual `docker_image` input supports the same version check.
Fixture base and registry image references can be overridden with
`EXDOCK_TEST_BASE_IMAGE` and `EXDOCK_TEST_REGISTRY_IMAGE`; digest references work
for all three variables. Override them with mirrored/pinned images when required.
A passing run only establishes compatibility for that Engine and the tested
configuration cases.

Logs and the tested client/server Engine versions are saved under
`.docker-test-artifacts/<run-name>/`, including Docker command output and
server/agent/registry logs. CI uploads these on success and failure. They contain
only generated test credentials and disposable fixture data, but should still be
kept as internal build artifacts.

## Exporting a passing release pair

Set `EXDOCK_TEST_RELEASE_EXPORT_DIR` when running `mix test.release` to export
`suite-server:local` and `suite-agent:local` as `images.tar`, with image IDs and
labels in `images.json` and Docker versions in `tested-engine.txt`. Export happens
only after the entire suite passes and before the disposable Engine is removed.
Adapter-only runs reject this option.

`EXDOCK_IMAGE_VERSION`, `EXDOCK_IMAGE_REVISION`, and `EXDOCK_IMAGE_SOURCE` supply
OCI build labels; defaults are `dev`, `unknown`, and an empty source URL for local
checks. Packaging checks run on both images, including readable project and
dependency notices under an unprivileged user. The release workflow supplies
manifest values, verifies the exported IDs, and publishes the archive's images
without a second build. See [release preparation](../../docs/RELEASING.md).
