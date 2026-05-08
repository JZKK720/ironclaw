---
description: "Step-by-step guide to compare fork/main with upstream/main, preserve fork-only commits and customizations, and manually merge upstream/main into fork/main. Use when the weekly sync-upstream workflow fails due to conflicts, when preparing a major intake such as v0.28, or when you want to pull upstream changes on demand."
---

# Manual Upstream Sync

Use this when `sync-upstream.yml` fails with a merge conflict, when you want to pull upstream changes on demand, or when you need a release-line intake such as `v0.28` without losing fork-only patches.

## Ground Rules

- Treat `origin/main` as the fork baseline and `upstream` as compare-only. Never push to `upstream`.
- Keep fork-only commits unless the user explicitly asks to drop or rewrite them.
- `.env`, `IRONCLAW_HOME_DIR`, and local database volumes are operator state, not merge inputs. Do not claim they were "synced" from upstream.

## Step 1 — Verify remotes

```bash
git remote -v
# origin  should point to your fork (JZKK720/ironclaw)
# upstream should point to nearai/ironclaw
```

If `upstream` is missing:
```bash
git remote add upstream https://github.com/nearai/ironclaw.git
```

## Step 2 — Freeze the fork baseline

```bash
git status --short --branch
git fetch origin upstream --tags
git checkout main
git pull --ff-only origin main
```

If the worktree is dirty, stop and stash or commit the local changes first. Do not merge upstream on top of unrelated uncommitted work.

## Step 3 — Check both sides of divergence

```bash
# Fork-only commits that must survive the merge
git log --oneline --decorate upstream/main..origin/main

# Incoming upstream commits
git log --oneline --decorate -n 40 origin/main..upstream/main

# Left/right view of both sides together
git log --left-right --graph --cherry-pick --oneline origin/main...upstream/main

# Summary of upstream file changes
git diff --stat origin/main..upstream/main

# Migrations landing?
git diff origin/main..upstream/main -- migrations/

# Heuristic intake summary, including GHCR rebuild impact
python scripts/evaluate_upstream_intake.py --fetch --base-ref origin/main
```

If there are new migrations, check the version numbers don't conflict with any local migration files.

For release-line intakes such as `v0.28`, identify the exact upstream tag first with `git tag -l "v0.28*" --sort=-version:refname`, then compare that tag to `origin/main` before merging `upstream/main`.

## Step 4 — Merge

```bash
git checkout main
git merge upstream/main --no-edit -m "chore: merge upstream/main ($(git rev-parse --short upstream/main)) into fork/main"
```

## Step 5 — Resolve conflicts (if any)

If `git merge` exits with conflicts:
```bash
git status                  # see conflicting files
# edit conflicted files — look for <<<<<<< markers
git add <resolved files>
git merge --continue
```

**Common conflict areas:**
- `Cargo.toml` / `Cargo.lock` — usually take upstream version numbers and toolchain movement, then re-apply intentional fork-specific overrides
- `migrations/` — never delete upstream migrations; if there's a version clash, renumber the fork's migration to be higher and preserve PostgreSQL/libSQL parity
- `src/extensions/manager.rs`, `src/channels/wasm/setup.rs` — preserve fork-specific behavior around extension/channel setup and identity handling
- release/update surfaces (`docker-compose.yml`, release workflows, install docs) — preserve fork-owned GHCR and release-channel wiring

## Step 6 — Check for new migrations

```bash
ls migrations/ | sort -V | tail -5
```

If upstream added a new migration (e.g., V25), verify it also exists in `libsql_migrations.rs` for the libSQL backend.

## Step 7 — Verify build

```powershell
# Windows — use Docker
docker compose config
docker compose up -d --build ironclaw
docker compose exec ironclaw cargo test
```

## Step 8 — Push

```bash
git push origin main
```

This triggers `docker-publish.yml` automatically, which builds and pushes fresh GHCR images.

After pushing, run [Validate GHCR Upgrade](validate-ghcr-upgrade.prompt.md) before telling operators to pull new images, and use [Update Local Docker Runtime](update-local-docker-runtime.prompt.md) for backup-first local rollouts.

## Step 9 — Update FEATURE_PARITY.md

After merging, check if upstream added or changed any tracked features:
```bash
git diff origin/main~1..origin/main -- FEATURE_PARITY.md
```

If the upstream merge changed feature behavior, update `FEATURE_PARITY.md` to reflect current status.
