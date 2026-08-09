# Synchronizing Implementation Changes From Upstream Repository

This fork imports selected changes from `livestorejs/livestore`. Changes are reviewed visually in WebStorm, applied on a synchronization branch, and then fast-forwarded onto the fork's `main` branch.

A normal `git merge` cannot be restricted to paths. This workflow instead starts an ancestry-only `ours` merge and three-way-applies a patch containing only the paths selected during review. The resulting commit records the upstream repository parent, so later synchronizations begin after the last reviewed upstream revision.

This workflow has two separate human approval checkpoints:

1. Select the paths to apply from the complete upstream delta.
2. Review and curate the staged hunks after those paths have been applied.

Path selection does not approve every hunk within those paths. Do not validate, commit, fast-forward, or push until the staged result has received explicit human approval at the second checkpoint.

All commands use Fish shell.

## 1. Start a Synchronization Branch

Refresh both remote-tracking branches before inspecting repository state or calculating the upstream range. This avoids making synchronization decisions from stale local references:

```fish
git fetch origin --prune
git fetch upstream --prune
```

Then begin with a clean worktree:

```fish
git status --short --branch
git switch main
git pull --ff-only origin main
git switch -c igor/chore/sync-upstream
```

Use a unique branch suffix if that name already exists.

Pin the upstream range:

```fish
set new_upstream (git rev-parse upstream/main)
set old_upstream (git merge-base HEAD $new_upstream)

git merge-base --is-ancestor $old_upstream $new_upstream
git rev-list --left-right --count HEAD...$new_upstream
git show --no-patch --oneline $old_upstream $new_upstream
```

Stop if the ancestry check fails. The commit count prints fork-only commits first and new upstream commits second.

## 2. Review Changes in WebStorm

Open the complete upstream delta in WebStorm:

```fish
git \
  -c 'difftool.webstorm.cmd=/opt/homebrew/bin/webstorm diff "$LOCAL" "$REMOTE"' \
  difftool \
  --dir-diff \
  --no-prompt \
  --tool=webstorm \
  $old_upstream \
  $new_upstream
```

The main purpose of this review is to identify the paths that should be imported. Include any related tests, manifests, configuration, patches, or changesets needed to keep the selected implementation coherent.

Keep a list of the selected paths for the next step. Selection at this stage is path-based: a selected path is initially applied in full, and unwanted hunks can be removed during the later curation pass.

**Human checkpoint 1:** Stop and obtain explicit confirmation of the selected path list before applying the patch. This confirmation authorizes only the initial path-level application; it does not replace the staged hunk review in step 4.

## 3. Apply the Selected Paths

Start a pending merge whose initial tree is exactly the fork's tree:

```fish
git merge \
  --strategy=ours \
  --no-commit \
  --no-ff \
  $new_upstream

git rev-parse MERGE_HEAD
echo $new_upstream
```

The two hashes must match. Pass the paths chosen in WebStorm after `--`. Use as many path arguments as needed:

```fish
if git diff --quiet $old_upstream $new_upstream -- \
    path/to/selected-directory \
    path/to/selected-file.ts
  echo "No changes in the selected paths"
else
  git diff --binary $old_upstream $new_upstream -- \
    path/to/selected-directory \
    path/to/selected-file.ts \
    | git apply --3way --index
end
```

`git apply --3way` can return a nonzero status when it leaves conflicts. Do not rerun it; resolve the conflicts in WebStorm.

## 4. Resolve, Curate, and Verify

Use WebStorm's Git conflict resolver for every unmerged file. Reconcile the fork and upstream versions, save the merged result, and mark the conflict resolved.

After resolving conflicts in WebStorm, stage the complete result:

```fish
git add --all
```

Confirm that WebStorm resolved every conflict:

```fish
git diff --name-only --diff-filter=U
```

This command must print nothing.

Review the staged result in WebStorm and curate the selected paths. Edit files to remove unwanted hunks and delete newly added files that should not be imported. This review is required even when the patch applied cleanly and every selected path appears appropriate.

When an existing file was modified or deleted upstream but the fork should retain its complete pre-merge version, restore it to `HEAD`:

```fish
git restore --source=HEAD --staged --worktree -- path/to/file
```

Stage all WebStorm edits, new-file deletions, and restored paths:

```fish
git add --all
```

Repeat the WebStorm review until the staged changes contain exactly what should reach the fork. Then confirm that no conflict or whitespace error remains:

```fish
git diff --name-only --diff-filter=U
git diff --cached --check
```

Inspect the final path list and confirm that it contains only paths intentionally selected in WebStorm:

```fish
git diff --cached --name-only HEAD
```

**Human checkpoint 2:** Stop and ask the reviewer to inspect the complete staged diff in WebStorm. Wait for explicit approval of the staged result before continuing to validation or commit. Approval of the path list from step 2 must never be inferred as approval of the staged hunks.

## 5. Validate and Commit

Begin this step only after the reviewer has explicitly approved the staged result at human checkpoint 2.

Run focused Vitest files for affected behavior, then the required repository checks:

```fish
./node_modules/.bin/vitest run path/to/affected.test.ts \
  --testNamePattern 'affected behavior'

pnpm run lint:full:fix
pnpm run lint:full
pnpm run ts:build
pnpm run test:unit
```

Run affected integration or performance suites when necessary. Review fixer output in WebStorm, stage it with `git add --all`, then repeat the verification checks and staged WebStorm review.

Commit the filtered merge:

```fish
git commit \
  -m "chore: sync upstream repo" \
  -m "Merge selected implementation paths from livestorejs/livestore through $new_upstream."

git show --no-patch --format='%H%nparents: %P%nsubject: %s' HEAD
```

The commit must have the previous fork commit and `$new_upstream` as its two parents.

## 6. Fast-Forward the Fork's Main Branch

Capture the synchronization branch, fast-forward `main` to its merge commit, and push the fork's `main` branch:

```fish
set sync_branch (git branch --show-current)

git switch main
git merge --ff-only $sync_branch
git push origin main
```

The synchronization changes now reside on both the local and fork-hosted `main` branches.

## 7. Clean Up

After the push succeeds, delete the merged local synchronization branch:

```fish
git branch -d $sync_branch
```

The safe `-d` mode refuses to delete a branch that is not fully merged into `main`. No remote synchronization branch needs deletion because only `origin/main` was pushed.

Verify the final state:

```fish
git status --short --branch
git log -1 --oneline --decorate
```

The current branch must be `main`, the worktree must be clean, and local `main` must be aligned with `origin/main`.

## Recovery

Before committing, discard the complete synchronization attempt with:

```fish
git merge --abort
```

Restore an individual unwanted path to the pre-merge fork tree with:

```fish
git restore --source=HEAD --staged --worktree -- path/to/unwanted-file
```

If the selected patch is empty, the ancestry-only merge can still be committed to record that the upstream range was reviewed. On the next synchronization, `git merge-base HEAD upstream/main` resolves to the upstream parent recorded by the previous filtered merge, so only newer upstream changes are considered.
