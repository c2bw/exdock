# Exdock agent protocol

Both Mix projects share `Exdock.Protocol.NodeWire`. NodeWire negotiates the
exact application manifest, handles framing over raw TLS, and provides
heartbeat and idle deadlines. Its JSON codec validates application events.
Exdock validates authentication, runtime readiness, command arguments, node
ownership, and job correlation.

The current application wire version is 6. The Mix dependency follows the
NodeWire Git `main` branch and the lockfiles pin its commit. Fetching
dependencies requires access to the LAN Git server. Switch the shared Mix
dependency to the published Hex package for hosted CI and Docker builds.

Refresh results carry individual JSON snapshot records. Each record is
validated independently, and the whole result remains subject to NodeWire's
8 MiB application payload limit.

## Coordinated cutover

Build both peers from the same Exdock revision. Deploy the server and then
immediately upgrade all standalone agents. Verify that every node reconnects,
loads its runtime bundle, and refreshes. Roll back both peers together.

Wire version, standalone agent version, server acceptance range, and runtime
bundle version describe separate contracts. Keep application message IDs
stable. Changes to the manifest affect NodeWire negotiation even when the
payload change is otherwise additive. Update the shared application version,
endpoint tests, and release metadata together for a breaking change.
