---
description: "Planning-first guide for upgrading the fork to an upstream release such as 0.29.0. Use when you need to compare origin/main with upstream, classify fork-only commits and conflict-prone files as keep, reapply, replace, or defer, decide whether upstream features should supersede fork behavior, map the GHCR rebuild or publish path, and prepare the local Docker rollout plus upgrade notes before executing anything."
---

# Plan an Upstream Upgrade

Use this when the job is to decide how to intake an upstream release such as `0.29.0` before touching `origin/main`, rebuilding fork GHCR images, or rolling local Docker containers.

> If the user already approved execution, continue with [intake-upstream-version.prompt.md](intake-upstream-version.prompt.md) for the merge and publish flow, then use [update-local-docker-runtime.prompt.md](update-local-docker-runtime.prompt.md) for the local rollout.

## Ground Rules

- This prompt is planning-first. Inspect, compare, and decide before merging, pushing, or recreating containers.
- Treat `origin/main` as the fork runtime baseline and `upstream` as fetch-only.
- Keep fork-only behavior unless the evidence says upstream supersedes it or the user explicitly wants to retire it.
- `.env`, `IRONCLAW_HOME_DIR`, and the external `ironclaw-pgdata` volume are operator state, not merge inputs.
- Separate the output into three distinct decisions: source merge plan, GHCR publication plan, and local Docker rollout plan.

## Inspect These Sources Together

- [AGENTS.md](../../AGENTS.md)
- [.github/copilot-instructions.md](../copilot-instructions.md)
- [FORK_WORKFLOW.md](../FORK_WORKFLOW.md)
- [sync-upstream.prompt.md](sync-upstream.prompt.md)
- [intake-upstream-version.prompt.md](intake-upstream-version.prompt.md)
- [validate-ghcr-upgrade.prompt.md](validate-ghcr-upgrade.prompt.md)
- [update-local-docker-runtime.prompt.md](update-local-docker-runtime.prompt.md)
- [validate-installer-release-channel.prompt.md](validate-installer-release-channel.prompt.md)
- [scripts/evaluate_upstream_intake.py](../../scripts/evaluate_upstream_intake.py)
- [docker-compose.yml](../../docker-compose.yml)
- [docs/drafts/install/updating.mdx](../../docs/drafts/install/updating.mdx)
- [docs/drafts/platforms/docker-compose.mdx](../../docs/drafts/platforms/docker-compose.mdx)
- [.github/workflows/docker-publish.yml](../workflows/docker-publish.yml)
- [.github/workflows/rebuild-release-image.yml](../workflows/rebuild-release-image.yml)
- [.github/workflows/sync-upstream.yml](../workflows/sync-upstream.yml)
- [CHANGELOG.md](../../CHANGELOG.md)
- [FEATURE_PARITY.md](../../FEATURE_PARITY.md)

## Workflow

1. Freeze the baseline and identify the exact upstream target.

```bash
git remote -v
git fetch origin upstream --tags
git status --short --branch
git checkout main
git pull --ff-only origin main
git tag -l "ironclaw-v<MAJOR.MINOR>*" --sort=-version:refname
git rev-list -n 1 ironclaw-v<VERSION>
```

2. Measure divergence from both sides.

```bash
git log --oneline --decorate ironclaw-v<VERSION>..origin/main
git log --oneline --decorate -n 60 origin/main..ironclaw-v<VERSION>
git log --left-right --graph --cherry-pick --oneline origin/main...upstream/main
git diff --stat origin/main..ironclaw-v<VERSION>
git diff origin/main..ironclaw-v<VERSION> -- migrations/
python scripts/evaluate_upstream_intake.py --fetch --base-ref origin/main
```

3. Build a fork delta ledger before recommending any merge.

For every fork-only commit or conflict-prone file, record:

| Surface | Fork behavior today | Incoming upstream change | Decision | Why | Execution note |
|---------|----------------------|--------------------------|----------|-----|----------------|

Allowed decisions:

- `keep`: preserve the fork behavior as-is through the merge
- `reapply`: take upstream, then reapply the fork delta on top
- `replace with upstream`: retire the fork delta in favor of upstream behavior
- `defer`: do not carry the change in this intake; track it as a follow-up

Call out these surfaces explicitly when they appear in the diff:

- `docker-compose.yml`, `.env`-driven image pins, `IRONCLAW_APP_IMAGE`, and `SANDBOX_IMAGE`
- Watchtower labels or any pull-based rollout assumptions
- `.github/workflows/docker-publish.yml`, `.github/workflows/rebuild-release-image.yml`, and release-tag behavior
- install and update docs, release notes, and other downstream update-channel surfaces
- migrations, Cargo or toolchain changes, and runtime versus worker image coupling

4. Decide whether upstream features should supersede fork behavior.

- If upstream touched the same area as a fork patch, say which side should win and what must be retested.
- If the fork currently ships a modified setting or workflow, state whether that difference is still intentional after the upstream release.
- If the release adds new migrations, verify there is no numbering conflict and that PostgreSQL and libSQL support stay aligned.
- If the release changes GHCR, compose, or release assets, explain whether the fork can keep its own publication channel or can safely inherit upstream behavior.

5. Produce the GHCR publication plan.

- State whether pushing the merge to `origin/main` is sufficient because `docker-publish.yml` will publish fresh `latest` and `sha-*` images.
- State whether a versioned rebuild through `rebuild-release-image.yml` is also required for a pinned `<VERSION>` tag.
- Record the expected image outputs for both `ironclaw` and `ironclaw-worker`.
- Note any required `CHANGELOG.md`, `FEATURE_PARITY.md`, docs, or release-note updates that must ship with the upgrade.

6. Produce the local rollout and rollback plan.

- Back up `.env`, the current compose image references, the external Postgres volume metadata, and the active `IRONCLAW_HOME_DIR`.
- Pull the exact target image tags or digests declared by compose and `.env`.
- Recreate the runtime with `docker compose up -d --no-build postgres ironclaw` unless source-build validation is intentionally required.
- List the required health checks and smoke tests after rollout.
- State what conditions require rollback and which pins or backups restore the previous state.

## Required Output

Report findings first. Then end with:

1. `Upgrade decision`: `ready`, `ready with follow-ups`, or `blocked`
2. `Fork delta ledger`: the table covering keep, reapply, replace, or defer decisions
3. `GHCR plan`: exact workflows, tags, and blockers
4. `Local rollout plan`: backups, pull or recreate commands, smoke tests, and rollback conditions
5. `Upgrade notes`: docs, release surfaces, and operator instructions that still need updates