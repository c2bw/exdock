# Coordinated releases

The first prepared public release is `v0.1.1`. Preparing files does not create a
Git tag, GitHub release, or public container package. The destination GitHub
repository and its package settings must exist before publication.

## Release identity and compatibility

A public release identifies a server/agent pair from one source commit. Package,
wire, and agent-compatibility versions are separate contracts:

| Component | v0.1.1 value | Source of truth |
| --- | --- | --- |
| Server and standalone agent packages | `0.1.1` | `build/project_config.exs`, control-plane track |
| Shared runtime and protocol packages | `0.1.0` | `build/project_config.exs`, runtime/protocol track |
| Wire protocol | `5` | `Exdock.Protocol.Compatibility` |
| Agent compatibility version / server range | `1.2.0` / `~> 1.2.0` | `Exdock.Protocol.Compatibility` |
| Runtime-bundle format | `1` | `Exdock.Protocol.Compatibility` |

`scripts/release_metadata.exs` derives the machine-readable manifest from these
source modules and the release notes from `CHANGELOG.md`. It rejects a tag that
does not match the package version and rejects unpinned or differing base images.
Do not make all version fields equal just because a public release is being cut.
Publication currently accepts stable `x.y.z` versions; prerelease promotion
needs an explicit policy before enabling it. Follow the [protocol versioning rules](../lib/exdock_client/exdock_protocol/README.md)
when changing the wire or agent capability requirements.

The image release initially targets **linux/amd64**, with the real command suite
using Docker Engine **29.8.1**. Source-built images on other platforms are not
certified by that publication workflow. The final manifest includes the tested
Engine version file and the actual image IDs and registry digests.

## Before tagging

Release tooling uses Python 3.9 or later in addition to the source-build/test
toolchain. The publish job uses the Docker CLI and GitHub CLI already installed
on GitHub-hosted Ubuntu runners.

1. Finish the publication review, including the historical credential review
   and [GitHub setup](GITHUB_MAINTENANCE.md). Do not publish private configuration
   or credentials with source history or release assets.
2. Update package/compatibility versions as required and add the corresponding
   `## [VERSION]` entry to `CHANGELOG.md`. The first entry is already prepared.
3. Review the pinned builder and runner digests in **both** Dockerfiles. The
   current builder is Elixir 1.20.5 / OTP 29.1.2; the runner is Alpine 3.24.4.
   Source/unit CI also verifies Elixir 1.20.2 / OTP 29.0.4. Updating a base digest
   requires running the production command checks again. A pinned base does not
   freeze external APK repositories or every build-tool download.
4. Run `scripts/check-release.sh` and lint the workflows. This runs the Python
   publisher safeguard tests, `mix precommit`, and production Docker checks.
5. Commit the reviewed release changes. From a clean checkout of that commit,
   run **Publish coordinated release** manually on the intended branch. This
   verifies and exports the pair but does not publish from a branch event.
6. Once that dry run passes, create and push the annotated release tag:

   ```sh
   git tag -a v0.1.1 -m "Exdock v0.1.1"
   git push github v0.1.1
   ```

   `github` here is the remote for the destination GitHub repository, not
   necessarily the existing `origin`. Configure it for the intended repository
   first. A tag push is the publication trigger. Do not move or reuse a tag after
   its public release succeeds.

## What the workflow publishes

The tag workflow first validates metadata and runs the full source checks. It
then builds both actual production Dockerfiles inside the disposable Engine and
runs the real command suite against them. Builds include OCI source, revision,
version, and MIT license labels, plus project and dependency notices.

Only a passing release suite exports `images.tar` and `images.json`. The verify
job loads that archive and checks both image identities, architecture, and labels
against `release.json`. It uploads this tested pair as a seven-day Actions
artifact. A separate job, with `contents: write` and `packages: write`, loads that
same archive and pushes it to GHCR without rebuilding.

Image identities use the SHA-256 digest of each image's original configuration
bytes, which include its root filesystem layer digests. The publisher re-exports
each loaded image to verify this content identity. This works across classic and
containerd image stores, whose native `docker inspect` IDs can differ for the
same exported image. `images.json` also retains the test daemon's native ID as
`source_image_id`; published registry digests are recorded separately.

For a GitHub repository `OWNER/REPOSITORY`, lowercased image references are:

```text
ghcr.io/owner/repository:v0.1.1
ghcr.io/owner/repository_client:v0.1.1
```

Both images also receive `sha-FULL_SOURCE_COMMIT` tags. After both version tags
are pushed, the workflow updates their `latest` aliases for the existing Compose
examples. These aliases are mutable and not promoted atomically; use explicit
version tags or digest references for coordinated deployments. Registry pushes
are not atomic: a failed run can leave partial image tags. Treat the public GitHub release and its completed `release.json` as the
record of a usable pair, rather than deploying tags from an unfinished run.

The publisher rejects a dirty checkout, branch event, mismatched source/repository,
changed image identity, wrong architecture/labels, or an existing release/draft.
It pushes both images, records their registry digests, creates a draft GitHub
release with assets, and publishes it only after asset upload succeeds.

Release assets contain:

- `release.json`: source revision, package/compatibility versions, base pins,
  image IDs, version/commit tags, and digest-qualified pull references.
- `images.json`: image identities exported from the passing suite.
- `tested-engine.txt`: Docker client/Engine version evidence.
- `compose.release.yml` and `.env.example`: installation configuration templates.

The image archive stays in Actions artifacts, not in the public release assets.
Diagnostic artifacts are separate and contain disposable test credentials; see
[the Docker suite guide](../integration/docker/README.md).

On first publication, verify that **both GHCR packages are public** and linked
to the intended repository. Package visibility is a GitHub setting and is not
changed by this workflow. For an existing package, grant the destination
repository Actions access to publish it if it does not already inherit access. Verify anonymous image pulls before announcing the
release; GitHub repository visibility alone does not guarantee public packages.

## Install a published pair

Use this after the GitHub release and its packages are available. Download its
`compose.release.yml` and `.env.example` assets, or check out that release tag.

```sh
cp .env.example .env.release
chmod 600 .env.release
```

Generate and set the secrets as described in the [installation guide](../README.md).
Add these two fields to `.env.release`, replacing the namespace with the published
GitHub repository's lowercase owner/name:

```dotenv
EXDOCK_IMAGE_PREFIX=ghcr.io/owner/repository
EXDOCK_RELEASE_TAG=v0.1.1
```

Then run:

```sh
docker compose -p exdock --env-file .env.release -f compose.release.yml config --quiet
docker compose -p exdock --env-file .env.release -f compose.release.yml pull
docker compose -p exdock --env-file .env.release -f compose.release.yml up -d
```

This configuration has no build directives and applies the same tag to the
server and agent. It retains the quickstart's loopback UI, internal agent
listener, protected labels, and persistent volume. Use the matching file and
`.env.release` for subsequent commands. For a deployment locked to exact content,
use the digest-qualified references from `release.json` in a Compose override.

Before upgrading, back up the database and matching `DB_VAULT_KEY`. Deploy the
server and every remote agent together. Startup applies migrations; rollback
across a schema change requires the matching older image pair and database backup.
See [backup and recovery](../README.md#back-up).

## Failed publication

A failed validation/test run publishes no images. A registry or GitHub failure
in the publish job may leave image tags or an unpublished draft. Review its logs
and package state before retrying. If a draft was left behind, remove that
**unpublished draft** after review, then rerun the workflow for the same tag; the
publisher intentionally refuses to modify an existing release automatically.
Do not delete/recreate an already published release to replace its images.
Publish a new version for corrections to released content.

## Local export validation

To inspect a candidate without publishing:

```sh
elixir scripts/release_metadata.exs /tmp/exdock-release-candidate
```

Local runs use `local/exdock` as a placeholder namespace unless you set
`GITHUB_REPOSITORY` to the intended owner/repository.

Set `EXDOCK_IMAGE_VERSION`, `EXDOCK_IMAGE_REVISION`, and `EXDOCK_IMAGE_SOURCE` to
the corresponding manifest values, then run:

```sh
EXDOCK_TEST_RELEASE_EXPORT_DIR=/tmp/exdock-release-candidate mix test.release
python3 scripts/publish_release.py --check /tmp/exdock-release-candidate
```

`--check` loads the exported images into the selected local Docker daemon and
validates them without registry authentication or publication. Local metadata
marks uncommitted changes as dirty and labels them with a `-dirty` revision;
such candidates can be checked but cannot be published. Remove test images only
when you have finished inspecting them, using their recorded IDs.
