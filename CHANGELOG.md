# Changelog

Entries describe releases by tag. A release is available only after its GitHub
publication workflow succeeds. The historical `v0.0.1` tag predates this release
pipeline; coordinated public image releases begin with `v0.1.1`.

## [0.1.1]

Initial public release of the current server and standalone Docker agent.

### Features

- Phoenix/LiveView inventory for containers and images across connected agents,
  container logs and resources, registry metadata, and repository release tracking.
- Native Docker start, stop, and restart; recreation with persistent-volume and
  network preservation, replacement readiness checks, rollback, and cleanup alerts.
- Scheduled updates with container priorities and preferences. Finite schedules
  become inactive after their last run and remain inactive across restart.
- Untagged local image support and repository-specific digest comparisons for
  images shared by multiple repository references.
- Serialized container mutations and bounded resource sampling. Reconnection
  waits for active mutations and refreshes state after successful or failed work.
- A source-built quickstart, environment templates, screenshots, security policy,
  and documented upgrade, backup, and restore procedures.

### Compatibility and migration

- Server and agent package versions: `0.1.1` from the same source revision.
- Shared runtime/protocol package versions: `0.1.0`.
- Agent compatibility version: `1.1.0`; server accepts `~> 1.1.0`.
- Wire protocol: `4`; runtime bundle format: `1`.
- Upgrade the server and every agent together; protocol v3 and older are rejected.
- Server startup applies SQLite migrations, including stored repository digests.
  Back up the database and its matching `DB_VAULT_KEY` before upgrading. Keep
  that key stable; rollback across schema changes requires a matching backup.

### Distribution and verification

- The release workflow tests the production server and agent against an isolated
  Docker Engine, exports the passing image pair, and publishes those same images.
- Public images initially target `linux/amd64`; the real Engine suite targets
  Docker `29.8.1`. Other platforms/Engine configurations are not certified by this release.
- The release manifest records the source commit, compatibility versions,
  pinned base images, tested image IDs, and published registry digests.

### Deployment boundary

Use agent connections only on a trusted private network or authenticated tunnel.
Agent TLS currently does not verify server identity. Docker socket access is
administrative access, and the dashboard provides one administrator account.
See `SECURITY.md` and the deployment trust specification before installation.
