---
name: releasing-to-hex
description: Use when asked to cut, publish, or ship a release of this library to Hex — e.g. "release patch", "release minor", "release major", "release rc"/"pre-release". Drives the version bump, changelog, git tag, and build monitoring.
---

# Releasing to Hex

Cut a release of `a2a_sdk` by bumping the version, updating the changelog, and
**pushing a `vX.Y.Z` git tag**. The tag is what publishes: it triggers
`.github/workflows/release.yml`, which re-runs the full CI suite, guards that the
tag matches `mix.exs`, and runs `mix hex.publish`. **You never run
`mix hex.publish` yourself** — pushing the tag is the whole job.

The tag push is irreversible and outward-facing (it publishes to a public
registry that cannot be un-published). There is exactly **one human checkpoint**:
show the computed version + drafted changelog and get an explicit "yes" before
tagging. Everything before that is reversible.

## Release kinds & version bump

Read the current version from `@version` in `mix.exs` (the source of truth), then
bump per SemVer:

| Request | From `0.1.4` → | Rule |
| --- | --- | --- |
| `patch` | `0.1.5` | bump patch |
| `minor` | `0.2.0` | bump minor, zero patch |
| `major` | `1.0.0` | bump major, zero minor+patch |
| `rc` / pre-release | `0.1.5-rc.1` | target the **next patch**, `-rc.N` (N from 1; if already on `-rc.k`, go `-rc.(k+1)`) |

## Branch policy (check FIRST — abort if violated)

| Kind | Allowed where |
| --- | --- |
| `patch` / `minor` / `major` | **`main` only**, clean tree, up to date with `origin/main` |
| `rc` / pre-release | `main` **or** a feature branch (clean tree) |

## Procedure

1. **Preflight.** `git fetch origin`. Confirm `git status --porcelain` is empty
   (clean tree — abort if not). Confirm the branch matches the policy above; for
   non-rc, confirm `git rev-parse HEAD == git rev-parse origin/main`. Confirm CI is
   green on HEAD: `gh run list --branch <branch> --limit 1`. Confirm the publish
   secret exists: `gh secret list | grep HEX_API_KEY` (if missing, stop and point
   the user at the README "Releasing" one-time setup — the publish job will fail
   without it).
2. **Compute the version** from `@version` per the table. Verify the tag is free:
   `git tag -l "v<new>"` must be empty.
3. **Draft the changelog.** List commits since the last tag:
   `git log $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD)..HEAD --oneline`
   (first release: use full `git log --oneline`). Draft `### Added/Changed/Fixed`
   bullets from them, user-facing and terse. In `CHANGELOG.md`: rename
   `## [Unreleased]` → `## [<new>] - <YYYY-MM-DD>` (today), insert a fresh empty
   `## [Unreleased]` above it, and update the link refs at the bottom (add a
   `[<new>]: …/releases/tag/v<new>` line; point `[Unreleased]` compare at
   `v<new>...HEAD`).
4. **Bump `mix.exs`** — `@version "<new>"`.
5. **CHECKPOINT (the one human gate).** Show the user: the new version, the branch,
   and the drafted changelog diff. Wait for an explicit "yes". Do not proceed on
   silence or a non-answer.
6. **Local gate.** Run `mix precommit` — must be fully green.
7. **Commit + tag + push.**
   ```
   git add mix.exs CHANGELOG.md
   git commit -m "Release v<new>"
   git push origin <branch>
   git tag v<new>
   git push origin v<new>
   ```
   (If `git push origin main` is rejected by branch protection, stop and open a PR
   for the release commit instead — the tag must point at the merged commit.)
8. **Monitor the build.** Find the run the tag triggered and watch it to
   completion:
   ```
   gh run list --workflow=release.yml --limit 1        # get its <id>
   gh run watch <id> --exit-status                     # blocks until done, non-zero on fail
   ```
   On failure, surface the failing job with `gh run view <id> --log-failed` and
   report to the user — do not retry blindly.
9. **Confirm & report.** On success, verify the package is live
   (`mix hex.info a2a_sdk` shows `<new>`, or check `https://hex.pm/packages/a2a_sdk`
   and `https://hexdocs.pm/a2a_sdk/<new>`) and tell the user it published.

## Common mistakes

- **Running `mix hex.publish` directly.** The tag + CI does this. Publishing
  locally bypasses the CI gate and the version guard.
- **Monitoring by branch name (`gh run list --branch v0.1.5`).** Tag runs don't
  live under a branch of the tag's name. Use `--workflow=release.yml`.
- **Tagging without the checkpoint.** The push publishes permanently; always get
  the explicit yes on version + changelog first.
- **`patch`/`minor`/`major` off `main`.** Only pre-releases may ship from a
  feature branch.
- **Empty release.** If there are no user-facing commits since the last tag,
  say so and confirm the user still wants to cut it before proceeding.
- **Stale tree.** A dirty working tree or a `main` behind `origin/main` means
  stop and reconcile first — never tag a tree that isn't what CI validated.
