# Exdock Protocol Contract

This package is the single source of truth for the binary protocol shared by
the Exdock server and standalone client. It lives inside the client tree so it
is available when the client Docker image is built from `lib/exdock_client`,
and both Mix projects include it as the local `:exdock_protocol` dependency.

The protocol has three layers:

1. `Exdock.Protocol.Contract` owns the wire version, numeric message IDs,
   framing, and Erlang-term serialization.
2. `Exdock.Server.Connection.Protocol` validates payloads accepted by the
   server.
3. `Exdock.Client.Connection.Protocol` validates payloads accepted by the
   client.

The current wire version is `4`. Payloads are validated maps for `hello`,
`runtime_bundle`, `ready`, `command`, `progress`, `result`, `resource_sample`,
`heartbeat`, and `error`. Commands use a fixed allowlist and never carry server
job structs or `{module, function, args}` RPC values.

The authenticated handshake is:

```text
client hello -> server runtime_bundle -> client ready -> command/result traffic
```

The runtime bundle has a version, an aggregate SHA-256 digest, and the BEAM
entries required by the fixed executor. The client validates the complete
bundle before loading it and echoes the version/digest in `ready`, together
with sanitized live agent metadata for platform and runtime versions.

The SSL socket uses `packet: 4`, so Erlang/OTP supplies the outer four-byte
length prefix. The contract handles only this inner frame:

```text
<<version::8, message_type::8, payload::binary>>
```

## Decide Whether To Bump The Wire Version

Keep the current wire version only when the change preserves both the bytes on
the wire and the set and meaning of accepted payloads. Examples include code
cleanup, better logging, and stricter tests for behavior that was already part
of the contract.

Bump the wire version when changing any of the following:

- frame layout or serialization format;
- a numeric message ID;
- the shape or meaning of a message payload;
- which side may send a message or at what handshake stage;
- validation in a way that makes previously valid peers incompatible;
- the message map, unless old peers have an explicitly tested fallback.

Message IDs are permanent protocol identifiers. Never reuse an old numeric ID
for a different meaning. New IDs must fit in one byte and should use the next
available value.

Wire, agent release, accepted agent range, and runtime-bundle versions are
separate values owned by `Exdock.Protocol.Compatibility`. Change the relevant
value when shipping a new client or changing runtime capability requirements;
do not use a release-version change as a substitute for a wire-version bump.

## Upgrade Procedure

1. Change `Exdock.Protocol.Compatibility` and `Exdock.Protocol.Contract` first.
   - Increment the compatibility module's wire version for a breaking change.
   - Add new message names and IDs to `@message_types`.
   - Do not renumber or repurpose existing IDs.
2. Update both endpoint codecs in the same commit.
   - Add or change their `encode_message/1` clauses.
   - Add payload decoding and validation for the receiving endpoint.
   - Keep trust-boundary validation out of the shared contract.
3. Update message routing and handlers after decoding.
4. Update the client release version and server minimum requirement when the
   client runtime itself has changed.
5. Update the fixed version and message-map assertions in
   `test/exdock/protocol/contract_test.exs`.
6. Extend
   `test/exdock/server/connection/protocol_compatibility_test.exs` so every new
   message is encoded by its sender and decoded by its receiver.
7. Add malformed and unauthorized payload tests to the appropriate endpoint
   protocol test.
8. Update `docs/PROJECT_SPEC.md` and run `mix precommit` from the repository
   root.

The compatibility test must continue to cover every entry returned by
`Exdock.Protocol.Contract.message_types/0`. A message-map change is incomplete
if it is not represented there.

## Deploying A Single-Version Upgrade

The current contract accepts exactly one wire version. A peer on an older
version receives `:version_too_new`; a peer on a newer version receives
`:version_too_old`. The standalone client disables reconnect attempts after a
version mismatch. Consequently, a wire-version bump is a coordinated rollout,
not a rolling upgrade.

Use this order:

1. Build and publish the new client image, but do not roll it out yet.
2. Build the server and client from the same commit.
3. Deploy the server.
4. Immediately roll out every client node.
5. Verify that every node authenticates, initializes, and completes a refresh.

Old clients will disconnect between steps 3 and 4. Docker workloads continue
to run, but Exdock cannot manage disconnected nodes during that interval.
Rollback requires restoring compatible server and client versions together.

## Supporting A Rolling Upgrade

If a deployment cannot tolerate the coordinated disconnect window, implement
dual-version support before changing the wire format. This is a protocol
feature, not just a larger list of accepted version numbers. It requires:

- immutable message maps and payload adapters for each supported version;
- `decode_frame/1` returning the received version;
- the server handler remembering the version selected by the client's first
  frame;
- encoding replies with that selected version rather than always using the
  newest version;
- compatibility fixtures and bidirectional tests for every supported version;
- retaining the old decoder and encoder through the entire rollout and
  rollback window.

After all nodes have upgraded and the rollback window has closed, remove the
old version in a separate change. Never mutate an old version's contract after
it has been deployed.

## Review Checklist

- [ ] Wire-version decision is documented in the change.
- [ ] Existing message IDs were not reused or renumbered.
- [ ] Server and client codecs were changed together.
- [ ] Payload validation remains at the correct trust boundary.
- [ ] Bidirectional compatibility covers every message type.
- [ ] Malformed, unknown, and unauthorized frames remain rejected.
- [ ] Client image build includes the local protocol dependency.
- [ ] Server and client deployment and rollback versions are identified.
- [ ] `mix precommit` passes.

Image snapshots include an optional `repo_digests` list containing the full
repository-qualified manifest references. New senders preserve every reference;
receivers accept older snapshots without this field and fall back to `digest`.
This additive wire-v4 field is stored with image facts and used to compare each
container against its own repository.
