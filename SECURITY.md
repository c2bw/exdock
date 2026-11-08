# Security policy

Exdock is a self-hosted Docker management tool for a single trusted operator or
administrative team. Its server and agents belong to the same trust domain.

## Report a vulnerability privately

For the GitHub-hosted repository, use **Security / Advisories → Report a
vulnerability** when private vulnerability reporting is enabled. Reports through
that form are private to the repository's security maintainers.

If that option is unavailable, open an issue containing only a request for a
private security contact. Wait for the maintainer to establish a private channel
before sending the vulnerability details. Do not publish exploit instructions,
credentials, affected private endpoints, or unredacted logs in a public issue,
pull request, or discussion.

Include the following in the private report:

- The source commit or release, and both server and agent versions.
- Docker Engine version, host platform, and relevant deployment/network setup.
- A description of the impact and reproducible steps or a minimal proof of concept.
- Sanitized logs and whether the problem occurs within the supported trust
  boundary described below.

Use example credentials and remove tokens, vault keys, session cookies, and
sensitive container configuration from reproductions. The maintainer will
coordinate investigation, a fix, and disclosure through the private channel.
There is no guaranteed response time or long-term backport support policy.
Please identify whether your report reproduces on the current default branch
or the latest published release; older versions may require an upgrade.

## Deployment trust boundary

### Agent connections require a trusted path

Agent TLS currently uses `verify: :verify_none`. It encrypts traffic but does
not verify the server certificate or hostname. `AUTH_KEY` authenticates agents
to the server; it does not authenticate the server to agents.

Keep the agent TCP listener accessible only to expected agent hosts over an
operator-controlled private network or an authenticated VPN/tunnel. A guest LAN,
untrusted multi-tenant network, or direct public-Internet connection is outside
this deployment model. A server impersonator on an untrusted path could obtain
the reusable authentication token and deliver runtime code to the agent.

Server-supplied runtime loading is intentional. Treat control of the server or
its connection to an agent as control of that agent's Docker host. The detailed
assumptions and conditions requiring a TLS design change are recorded in
[EXDOCK-SEC-001](docs/UNVERIFIED_TLS_ACCEPTED_RISK_SPEC.md).

The local [quickstart](compose.quickstart.yml) keeps the agent listener inside
the Compose network. Its optional remote-agent override binds to a selected
private/VPN interface. Apply network access controls to that interface.

### Docker access is administrative access

Agents mount the Docker socket and can inspect, start, stop, pull, and recreate
workloads. Running the agent process as an unprivileged user with socket-group
access does not make Docker operations unprivileged. Restrict access to the
agent, its configuration, and the Docker socket as host-administrator access.
The `exdock.protected` label prevents Exdock recreation of selected containers;
it is an operational safeguard, not an authorization or isolation boundary.

### The dashboard has one administrator

`UI_EMAIL` and `UI_PASSWORD` configure the server's administrator at startup.
Exdock does not provide tenant isolation, per-host roles, or separate read-only
accounts. Give dashboard access only to trusted administrators. For remote
browser access, use an HTTPS reverse proxy or an authenticated tunnel; configure
WebSocket forwarding and the browser hostname as described in the
[installation guide](README.md).

Set `TRUSTED_PROXY_IPS` only to literal IP addresses of proxies you control when
using forwarded client addresses for login throttling. Do not trust arbitrary
`X-Forwarded-For` headers from clients.

### Preserve and protect secrets

Generate fresh production secrets; development defaults are for isolated local
development. All agents sharing a server use its `AUTH_KEY`, so protect it on
every host and rotate it across the server and all agents if disclosed.

`DB_VAULT_KEY` encrypts stored container configuration, not the entire SQLite
database. Keep that key stable and preserve it with database backups. Other
state, logs, and backups can still contain sensitive information. Restrict their
permissions and storage access, and redact diagnostic output before sharing.
The repository's Docker integration artifacts use disposable test credentials;
never reuse those values for an installation.

The [backup and restore procedure](README.md#back-up) covers the Exdock database
and its matching configuration. It does not back up application data in managed
Docker workloads.

## Server and agent compatibility

Deploy compatible server and agent revisions together. The current wire
protocol is v4, and incompatible agents cannot manage their host until upgraded.
Check the [protocol contract](lib/exdock_client/exdock_protocol/README.md) and
run the documented release checks before deploying modified code.
