# GitHub publication and CI maintenance

Repository files define the workflow and security policy. GitHub settings such
as private vulnerability reporting and branch protection must also be enabled
on the destination repository; committing these files does not enable them.

## Initial setup

1. Create the destination GitHub repository privately and push the intended
   default branch after reviewing the source and history for credentials.
2. Allow the Actions used by `.github/workflows/docker-commands.yml` and keep
   workflow token permissions read-only. These validation jobs do not need
   production credentials or repository write access. Do not run untrusted pull
   requests on a self-hosted runner with access to production Docker hosts.
3. Run **Docker command release gate** on that branch. Verify both `precommit`
   and `docker-release` pass on GitHub-hosted runners, including after a cache
   hit. Local checks do not establish that the hosted workflow has run.
4. Configure the default branch's ruleset or branch protection to require those
   two status checks before merging. Keep these job identifiers stable so the
   configured requirements continue to match. Disable force pushes and branch
   deletion for that branch. Choose review requirements appropriate to the
   maintainer team; a sole maintainer should not require an approval they cannot
   supply.
5. When making the repository public, enable **private vulnerability reporting**
   before announcing the release. Confirm the repository's advisory page offers
   **Report a vulnerability** to a reporter without maintainer permissions.
   `SECURITY.md` describes this route and a contact-request fallback; it does not
   itself activate the reporting form.
6. Link the README/security policy from the repository's description or relevant
   community-health settings, and verify the rendered documentation links and
   screenshots in the published repository.

GitHub's current setup instructions:

- [Configure private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository).
- [Required checks and protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).
- [Actions settings and permissions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository).

## Release publication

The separate **Publish coordinated release** workflow handles release tags.
Branch-triggered manual runs verify and export candidates without publishing;
matching release-tag runs can push the tested server/agent pair and create the
GitHub release. Only its publish job requests package/release write permissions.
Review [release preparation](RELEASING.md) before creating a tag. Enable Actions
package publishing on the destination repository and verify package visibility
before announcing the first public release.

## Cache correctness

The precommit job caches dependencies and `_build`, which includes Dialyzer's
PLT. Shared protocol and client-runtime packages are local path dependencies.
Their types can change without changing a lockfile. A key based only on
`mix.lock` can therefore restore stale exported types and fail analysis even
when the source compiles correctly.

The cache key includes:

- Runner OS and CPU architecture.
- The OTP and Elixir versions declared once in the workflow's `env` block.
- Lockfiles and Mix project definitions across the packages.
- Shared build configuration and server/agent configuration.
- Every shared-protocol and client-runtime `.ex` source file.

Changes to those inputs create a new cache namespace. The `precommit-v2` prefix
also separates this policy from the previous lockfile-only cache. There are no
broad `restore-keys`, which could restore the very PLT the new key invalidates.
A first run after a protocol/runtime change may consequently take longer.

When adding another path dependency or compile-time input, include its type or
build inputs in the cache key. When changing the toolchain, update the workflow
`env` values; both setup-beam steps and the key read those same values.

For a stale local PLT after editing path dependencies, run:

```sh
MIX_ENV=test mix dialyzer --force-check
mix precommit
```

Do not suppress type warnings to accommodate a stale cache. On GitHub, first
check whether a new dependency/input is missing from the key. Bump the cache
prefix or delete the affected Actions cache if a one-time reset is necessary.
See [GitHub's cache matching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).

## Action pins

Both validation and publication workflows pin every external `uses:` reference
to a full 40-character commit SHA, with the reviewed release tag recorded in a
comment. Checkout disables persisted credentials because these jobs do not push
source code. Validation jobs retain read-only `contents` permission; only the
release publisher receives package/release write permissions.

To update a pin:

1. Read the action's upstream release notes and runner/toolchain requirements.
2. Resolve the intended release tag from the action's own upstream repository,
   not a fork. For annotated tags, use the peeled `^{}` commit rather than the
   tag object's SHA.
3. Replace every occurrence of the action SHA and its version comment in the
   workflow.
4. Lint the workflow, run `mix precommit`, and verify both hosted jobs pass.

For example, inspect checkout's tag from upstream:

```sh
git ls-remote https://github.com/actions/checkout.git 'refs/tags/v4.4.0' 'refs/tags/v4.4.0^{}'
```

A full SHA makes the selected action code immutable; updates still need review.
See [GitHub's secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use).

## Docker diagnostics

The Docker job uploads `.docker-test-artifacts/` on success and failure with a
seven-day retention period. Diagnostics include generated test credentials and
disposable fixture data, as described in the
[Docker suite guide](../integration/docker/README.md). Do not reuse those values
or pass production credentials to the suite. Review and redact artifacts before
sharing them beyond the intended audience. Dependency/build caches must also
remain free of production secrets.
