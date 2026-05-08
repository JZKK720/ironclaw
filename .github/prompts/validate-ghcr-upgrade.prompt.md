---
description: "Validate whether this fork can safely update its GHCR images after upstream main/staging changes. Use when reviewing the pushed GHCR codebase, auditing major upgrades such as v0.28, comparing the fork with upstream main or staging, deciding whether to reuse upstream GHCR or rebuild fork GHCR, or checking whether docker-compose, Watchtower, installers, release notes, and release assets will actually pick up the update."
---

# Validate GHCR Upgrade

Use this when you need to answer: "Can we update the fork GHCR image from upstream changes, and will the downstream install/update paths actually pick it up?"

## Ground Rules

- Treat `origin/main` as the fork runtime baseline unless the user says otherwise.
- Treat `upstream` (`nearai/ironclaw`) as compare-only.
- A GHCR-safe image update is not the same as an installer-safe update. `docker-compose.yml` and Watchtower consume GHCR tags, while some install flows may still point at GitHub release assets.
- If the repo is on Windows, use Docker-based validation for builds/tests rather than host `cargo` invocations.

## Inspect These Sources Together

- [AGENTS.md](../../AGENTS.md)
- [CI/CD rules](../instructions/ci-cd.instructions.md)
- [Manual upstream sync](sync-upstream.prompt.md)
- [Installer and release-channel validation](validate-installer-release-channel.prompt.md)
- [docker-compose.yml](../../docker-compose.yml)
- [README.md](../../README.md)
- [scripts/evaluate_upstream_intake.py](../../scripts/evaluate_upstream_intake.py)
- [Updating draft](../../docs/drafts/install/updating.mdx)
- [Docker Compose platform doc](../../docs/drafts/platforms/docker-compose.mdx)
- [.github/workflows/docker-publish.yml](../workflows/docker-publish.yml)
- [.github/workflows/sync-upstream.yml](../workflows/sync-upstream.yml)
- [.github/scripts/update-release-plz-body.sh](../scripts/update-release-plz-body.sh)
- [.github/scripts/update-staging-promotion-body.sh](../scripts/update-staging-promotion-body.sh)
- [CHANGELOG.md](../../CHANGELOG.md)
- [FEATURE_PARITY.md](../../FEATURE_PARITY.md)

## Workflow

1. Verify the baseline and refresh refs.

```bash
git remote -v
git fetch origin upstream --tags
git status --short --branch
python scripts/evaluate_upstream_intake.py --fetch --base-ref origin/main
```

2. If this is a release-line question such as `v0.28`, pin the exact upstream tag and commit first.

```bash
git tag -l "v0.28*" --sort=-version:refname
git rev-list -n 1 <tag>
git log --oneline --decorate -n 20 origin/main..<tag>
git diff --stat origin/main..<tag>
```

3. Measure divergence against the fork baseline and both upstream branches.

```bash
git log --oneline --decorate upstream/main..origin/main
git log --oneline --decorate -n 40 origin/main..upstream/staging
git log --oneline --decorate -n 40 origin/main..upstream/main
git diff --stat origin/main..upstream/staging
git diff --stat origin/main..upstream/main
```

4. Review major-upgrade surfaces together.

- Migrations and libSQL/PostgreSQL parity.
- Cargo or toolchain changes, version bumps, and any `CHANGELOG.md` / `FEATURE_PARITY.md` implications.
- Whether fork-only commits mean upstream GHCR cannot be treated as equivalent to fork GHCR.
- GHCR workflow/tag logic for both `ironclaw` and `ironclaw-worker`.
- `docker-compose.yml` defaults, Watchtower labels/polling, and operator GHCR login requirements.
- PowerShell/shell/MSI installer paths, release download URLs, release-note scripts, and docs that may still reference upstream `nearai/ironclaw` release assets.
- Fork-specific patches or conflict-prone files that must survive a merge.

5. Run the narrowest executable validation that can falsify the current upgrade hypothesis.

```powershell
docker compose config
```

If a fork GHCR tag already exists and you are validating the published image path, stay in pull mode:

```powershell
docker compose pull ironclaw
docker compose up -d --no-build postgres ironclaw
```

If you are validating source changes before publication, use the local build path instead:

```powershell
docker compose up -d --build ironclaw
```

If image publication logic changed, inspect both workflows because `sync-upstream.yml` pushes do not retrigger `docker-publish.yml`.

6. Decide rollout safety explicitly.

- `Safe to reuse upstream GHCR` only if the release line matches the intended upstream tag or commit and there are no fork-only runtime, worker, or release-channel deltas that must be preserved.
- `Safe to publish GHCR` only if runtime image, worker image, workflow tags, and compose defaults are coherent.
- `Safe for automatic container uptake` only if the published tags match what `docker-compose.yml` and Watchtower poll.
- `Safe for installers` only if installer scripts, MSI/download links, release-note scripts, and release assets point at the same fork-owned channel. If they still point at upstream releases, report that GHCR publication alone will not update those installers.
- For major upgrades such as `v0.28`, summarize which upstream commits were already cherry-picked, which remain missing, and which are intentionally deferred.

## Required Output

Report findings first, then end with a three-part verdict:

1. `GHCR image verdict`: `safe`, `safe with follow-ups`, or `not safe`
2. `Installer/update-channel verdict`: `safe`, `partial`, or `not safe`
3. `Required follow-ups`: the exact files, workflows, docs, or release assets that must change before rollout

If you conclude the update is safe, cite the concrete evidence that supports that conclusion. If you conclude it is not safe, name the blocking mismatch instead of offering a vague warning.
