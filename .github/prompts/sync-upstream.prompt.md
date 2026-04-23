---
description: "Step-by-step guide to manually merge upstream/staging into fork/main. Use when the weekly sync-upstream workflow fails due to conflicts, or when you want to manually pull upstream changes."
---

# Manual Upstream Sync

Use this when `sync-upstream.yml` fails with a merge conflict, or when you want to pull upstream changes on demand.

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

## Step 2 — Fetch upstream

```bash
git fetch upstream
```

## Step 3 — Check what's coming in

```bash
# How many commits behind?
git rev-list --count HEAD..upstream/staging

# Summary of incoming changes
git log --oneline HEAD..upstream/staging | head -20

# Migrations landing?
git diff HEAD..upstream/staging -- migrations/
```

If there are new migrations, check the version numbers don't conflict with any local migration files.

## Step 4 — Merge

```bash
git checkout main
git merge upstream/staging --no-edit -m "chore: merge upstream/staging ($(git rev-parse --short upstream/staging)) into fork/main"
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
- `Cargo.toml` / `Cargo.lock` — usually take upstream version numbers, preserve any fork-specific dependencies
- `migrations/` — never delete upstream migrations; if there's a version clash, renumber the fork's migration to be higher
- `src/extensions/manager.rs`, `src/channels/wasm/setup.rs` — the owner_id fix from the fork must be preserved

## Step 6 — Check for new migrations

```bash
ls migrations/ | sort -V | tail -5
```

If upstream added a new migration (e.g., V25), verify it also exists in `libsql_migrations.rs` for the libSQL backend.

## Step 7 — Verify build

```powershell
# Windows — use Docker
docker compose up -d --build ironclaw
docker compose exec ironclaw cargo test 2>&1 | tail -20
```

## Step 8 — Push

```bash
git push origin main
```

This triggers `docker-publish.yml` automatically, which builds and pushes fresh GHCR images.

## Step 9 — Update FEATURE_PARITY.md

After merging, check if upstream added or changed any tracked features:
```bash
git diff origin/main~1..origin/main -- FEATURE_PARITY.md
```

If the upstream merge changed feature behavior, update `FEATURE_PARITY.md` to reflect current status.
