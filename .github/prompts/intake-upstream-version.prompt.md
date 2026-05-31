description: "End-to-end guide for intaking a specific upstream release version (e.g. 0.28.2) into the fork, merging it to origin/main, and publishing an updated GHCR image. Use when you want to sync a named release rather than just the latest upstream/main tip."
---

# Intake a Specific Upstream Version Tag

Use this when you need to pull in a named upstream release such as `0.28.2`, merge it into `fork/main`, and publish updated GHCR images.

> For a general continuous upstream sync (latest tip, no specific tag), use [`/sync-upstream`](sync-upstream.prompt.md) instead.
>
> If the fork-specific keep or replace decisions are still unclear, run [`/plan-upstream-upgrade`](plan-upstream-upgrade.prompt.md) first and finish the fork delta ledger before executing the merge.

## Ground Rules

- Treat `origin/main` as the fork runtime baseline. Never push to `upstream`.
- Keep all fork-only commits unless the user explicitly asks to drop them.
- `.env`, `IRONCLAW_HOME_DIR`, and `ironclaw-pgdata` are operator state — not merge inputs.
- If the worktree is dirty, stash or commit before merging.

## Inspect These Sources Together

- [AGENTS.md](../../AGENTS.md)
- [CI/CD rules](../instructions/ci-cd.instructions.md)
- [sync-upstream.prompt.md](sync-upstream.prompt.md)
- [validate-ghcr-upgrade.prompt.md](validate-ghcr-upgrade.prompt.md)
- [update-local-docker-runtime.prompt.md](update-local-docker-runtime.prompt.md)
- [scripts/evaluate_upstream_intake.py](../../scripts/evaluate_upstream_intake.py)
- [FEATURE_PARITY.md](../../FEATURE_PARITY.md)
- [CHANGELOG.md](../../CHANGELOG.md)
- [.github/workflows/docker-publish.yml](../workflows/docker-publish.yml)
- [.github/workflows/sync-upstream.yml](../workflows/sync-upstream.yml)
- [.github/workflows/rebuild-release-image.yml](../workflows/rebuild-release-image.yml)

---

> **Before starting:** Identify the exact upstream version you are intaking (e.g., `0.28.2`). Replace every `<VERSION>` placeholder in the commands below with that version string. The upstream release tag format is currently `ironclaw-v<VERSION>`, for example `ironclaw-v0.28.2`.

## Step 1 — Verify remotes and freeze the fork baseline

```bash
git remote -v
# origin  → your fork (jzkk720/ironclaw)
# upstream → nearai/ironclaw (fetch-only)

git fetch origin upstream --tags
git status --short --branch
git checkout main
git pull --ff-only origin main
```

---

## Step 2 — Find the exact upstream tag

```bash
# List all upstream release tags for the target minor version
git tag -l "ironclaw-v<MAJOR.MINOR>*" --sort=-version:refname

# Confirm which commit the target tag points to
git rev-list -n 1 ironclaw-v<VERSION>
```

Upstream release tags currently use the format `ironclaw-v<VERSION>` (e.g. `ironclaw-v0.28.2`). Keep the raw version string `<VERSION>` for changelog headings and workflow inputs.

---

## Step 3 — Measure divergence and record fork decisions

```bash
# Fork-only commits that must survive the merge
git log --oneline --decorate ironclaw-v<VERSION>..origin/main

# What the tag brings in on top of the fork
git log --oneline --decorate -n 40 origin/main..ironclaw-v<VERSION>

# File-level diff summary
git diff --stat origin/main..ironclaw-v<VERSION>

# Migration files landing?
git diff origin/main..ironclaw-v<VERSION> -- migrations/

# Heuristic intake report (runtime vs. worker rebuild impact)
python scripts/evaluate_upstream_intake.py --fetch --base-ref origin/main
```

If there are new migration files, verify their version numbers don't conflict with any local `migrations/V*.sql` file.

Before moving on, build a keep or reapply ledger for every fork-only commit or conflict-prone file. At minimum, classify each item as `keep`, `reapply`, `replace with upstream`, or `defer`, and record why.

---

## Step 4 — Review critical surfaces before merging

Check these together:

- **Migrations**: new `V*.sql` files — confirm version order and both PostgreSQL + libSQL parity.
- **Cargo.toml / Cargo.lock**: toolchain bumps, new dependencies, security advisories.
- **FEATURE_PARITY.md**: update any status entries (`❌`, `🚧`, `✅`) that reflect this release.
- **CHANGELOG.md**: review what changed in the `<VERSION>` release section to anticipate breaking changes.
- **docker-compose.yml**: check if upstream added or changed services, healthchecks, or image refs.
- **Fork-only patches**: `git log --oneline --decorate ironclaw-v<VERSION>..origin/main` — each fork-only commit must survive or be consciously superseded.
- **Release-channel surfaces**: GHCR workflow tags, `IRONCLAW_APP_IMAGE` or `SANDBOX_IMAGE` defaults, Watchtower uptake, installer or release-note scripts, and docs that tell operators how updates are consumed.

---

## Step 5 — Merge the tag into fork/main

Only start this step after the fork delta ledger is complete and the keep, reapply, replace, or defer decision is explicit for every conflict-prone surface.

```bash
git checkout main
git merge ironclaw-v<VERSION> --no-edit \
   -m "chore: intake upstream ironclaw-v<VERSION> into fork/main"
```

If the merge exits with conflicts:

```bash
git status                  # see conflicting files
# edit conflicted files — look for <<<<<<< markers
git add <resolved files>
git merge --continue
```

After a clean merge:

```bash
# Sanity-check that fork-only commits are still present
git log --oneline --decorate upstream/main..origin/main
```

---

## Step 6 — Update FEATURE_PARITY.md and CHANGELOG.md if needed

If behavior tracked in `FEATURE_PARITY.md` changed, update the status field in the same commit. Add a brief note to `CHANGELOG.md` under the relevant version heading.

---

## Step 7 — Push to origin/main (triggers docker-publish.yml)

```bash
git push origin main
```

`docker-publish.yml` triggers automatically on every push to `main` and builds + pushes:
- `ghcr.io/jzkk720/ironclaw:latest`
- `ghcr.io/jzkk720/ironclaw:sha-<full-sha>`
- `ghcr.io/jzkk720/ironclaw-worker:latest`
- `ghcr.io/jzkk720/ironclaw-worker:sha-<full-sha>`

Monitor the build at: `https://github.com/jzkk720/ironclaw/actions/workflows/docker-publish.yml`

---

## Step 8 — Optionally publish a versioned tag

If you want a pinned version tag in GHCR (not just `:latest`) in addition to the rolling tag:

1. Push the current fork merge commit to the versioned release tag on `origin`:

   ```bash
   git push origin HEAD:refs/tags/ironclaw-v<VERSION>
   ```

2. Trigger `rebuild-release-image.yml` manually from the GitHub Actions UI:
   - **source_ref**: `ironclaw-v<VERSION>`
   - **tag**: `<VERSION>`

   This publishes `ghcr.io/jzkk720/ironclaw:<VERSION>` pointing at the exact release commit.

> `git push origin HEAD:refs/tags/ironclaw-v<VERSION>` avoids colliding with an existing upstream tag of the same name in your local clone. `rebuild-release-image.yml` validates that `source_ref == ironclaw-v<tag>` and that `Cargo.toml` version matches. The input tag must be `<VERSION>` (no `v` prefix, e.g. `0.28.2`).

---

## Step 9 — Validate the published image

```powershell
# From the local machine — check the new image is available
docker pull ghcr.io/jzkk720/ironclaw:latest
docker inspect ghcr.io/jzkk720/ironclaw:latest --format "{{json .RepoDigests}}"

# Cross-check the digest matches the Actions run summary
```

If Watchtower is running, it will pick up `:latest` within its hourly poll. To force it immediately:

```powershell
docker compose exec watchtower /watchtower --run-once
```

---

## Step 10 — Roll out to local runtime

Follow [update-local-docker-runtime.prompt.md](update-local-docker-runtime.prompt.md) for the backup-first local rollout procedure (backup `.env`, `pg_dump`, pull new images, recreate containers, validate `/api/health`).
