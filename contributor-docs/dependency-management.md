# Dependency Management Guide

Dependency updates are deliberate, manual changes. Keep the selected update
scope small enough to review, update every declaration of the selected packages,
regenerate the root lockfile, and validate the affected workflows before
committing.

## Before Starting

Start from a clean worktree or create a checkpoint commit so dependency changes
remain distinguishable from unrelated work:

```bash
git status --short
```

Choose the packages and update target before editing. Review release notes and
migration guides for major versions, prereleases, and packages that participate
in one of the coordinated groups described below.

## Discover Available Updates

Use `npm-check-updates` without `-u` to report available updates without changing
the repository:

```bash
pnpm dlx npm-check-updates --deep --packageManager pnpm --target minor
```

Replace `minor` with `patch` for a narrower update or `latest` when intentionally
considering major versions. Discovery uses the npm registry and may include more
updates than should be combined in one change.

## Locate Every Version Declaration

Search all manifests and workspace policy before editing. For example:

```bash
rg -n -F '"effect":' \
  package.json pnpm-workspace.yaml packages docs examples scripts tests
```

Check each of these locations when relevant:

- Root, package, docs, example, script, and test `package.json` files.
- Root `pnpm-workspace.yaml#overrides`.
- Example-local `package.json#pnpm.overrides` blocks.
- `pnpm-workspace.yaml#packageExtensions` entries that mention the package.
- `pnpm-workspace.yaml#minimumReleaseAgeExclude` for explicitly exempted
  versions.
- `packages/@local/shared/src/CONSTANTS.ts` when a version is presented in the
  documentation.
- `patches/` and workaround documentation for packages with local changes.

Search for the old version after editing to catch declarations that do not use
the package name directly:

```bash
rg -n -F 'OLD_VERSION' \
  package.json pnpm-workspace.yaml packages docs examples scripts tests
```

## Update Package Manifests

The repository normally uses explicit versions for regular and development
dependencies. Update every intended occurrence consistently.

Workspace dependencies use the `workspace:` protocol and should not be replaced
with registry versions:

```json
"@livestore/utils": "workspace:^"
```

Published peer dependencies use explicit compatibility ranges. A peer range
describes versions supported by consumers, so review it independently instead
of mechanically copying an exact development version:

```json
"peerDependencies": {
  "react": "^19.0.0"
}
```

Confirm that the package's development dependency exercises a version allowed by
its peer range. Peer warnings must be investigated even when installation or the
build succeeds; `strictPeerDependencies` is disabled for this workspace.

## Reconcile PNPM Policy

After editing manifests, inspect `pnpm-workspace.yaml` and each affected
example's `pnpm.overrides`. Resolution overrides must agree with the versions
selected for the update or they can silently keep the workspace on an older
version.

When adding a dependency that runs an installation script, review
`pnpm-workspace.yaml#allowBuilds` and allow only the packages whose scripts are
required and trusted. Do not add an entry merely to suppress an installation
warning.

The workspace currently has no pnpm catalog. Do not introduce `catalog:`
references without a separate decision to adopt and document a catalog policy.

## Coordinated Updates

### Effect

Update `effect` and the selected `@effect/*` packages as a coordinated group.
Reconcile exact development versions, published peer ranges, root overrides,
example overrides, `@livestore/peer-deps`, and `EFFECT_VERSION` when it represents
the version required by the public documentation.

Effect prereleases can contain breaking changes. Review the Effect release notes
and run the full TypeScript and unit-test validation below.

### React, React DOM, Expo, and React Native

Update `react` and `react-dom` together. Verify compatibility with the Expo and
React Native versions checked into `docs/src/content/_assets/code/package.json`;
do not derive constraints from a different or unreleased Expo SDK.

After changing this group, run:

```bash
pnpm --filter docs-code-snippets exec expo install --check
```

Review `REACT_VERSION` separately. It is used in contributor documentation and
must describe the value intended by that documentation.

### Playwright

Update all `@playwright/test` development dependencies together and review the
peer range in `@livestore/effect-playwright`. CI installs Chromium through the
Playwright version resolved in `tests/integration`, so regenerate the lockfile
and run the affected Playwright suites after an update.

### Patched or Vendored Dependencies

Before updating a package referenced under `patches/` or in a workaround guide:

1. Confirm whether the patch is actively configured and still required.
2. Check whether the new upstream version includes the fix.
3. Rebuild and verify the patch when it remains necessary.
4. Remove obsolete patch files and workaround instructions together.

Do not assume that a file under `patches/` is applied. Confirm the active pnpm
configuration before relying on it.

### `wa-sqlite`

The root `pnpm-lock.yaml` is the sole lockfile for the pnpm workspace. The
vendored `packages/@livestore/wa-sqlite` subtree is the exception: its build uses
its Nix flake and retains package-local `flake.lock` and `yarn.lock` files. Update
those files only as part of a deliberate `wa-sqlite` dependency or build update.

## Regenerate the Lockfile

After all manifests and overrides agree, install from the repository root:

```bash
pnpm install
```

Commit the resulting root `pnpm-lock.yaml`. Do not create package-local pnpm
lockfiles.

## Review the Complete Change

Review both the changed-file list and the full dependency diff:

```bash
git diff --stat
git diff -- \
  package.json pnpm-workspace.yaml pnpm-lock.yaml \
  ':(glob)**/package.json' \
  packages/@local/shared/src/CONSTANTS.ts
git diff --check
```

Confirm that:

- Only intended packages and transitive resolutions changed.
- All repeated exact versions and relevant overrides agree.
- Peer ranges express supported consumer versions.
- No unrelated dependencies moved unexpectedly in `pnpm-lock.yaml`.
- Version constants and documentation still describe the selected versions.
- New lifecycle scripts are understood and explicitly allowed when necessary.

## Validate

Run the repository-wide checks for every dependency update:

```bash
pnpm run lint:full:fix
pnpm run lint:full
pnpm run ts:build
pnpm run test:unit
```

`lint:full` includes a frozen-lockfile installation check. Also run every
affected integration, performance, docs, or example workflow. Examples include:

```bash
pnpm run docs:build
pnpm run examples:test
pnpm run test:integration:playwright
pnpm run test:integration:sync-provider
pnpm run test:perf
```

Select the relevant commands rather than running unrelated long-lived suites.
Record exactly which checks ran and any intentionally skipped checks in the pull
request.

## Troubleshooting

When an update fails, capture the current and attempted versions, the complete
error, affected peer ranges or overrides, and relevant upstream release notes or
issues. Reduce a large update until the incompatible package is isolated.

Do not use `git checkout .` or another repository-wide restore to recover from a
failed update. If the dependency work is isolated and should be discarded,
restore only the explicitly reviewed files, or reset them manually from the
checkpoint created before starting.
