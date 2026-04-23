---
applyTo: ".github/workflows/**,docker-compose.yml,Dockerfile,Dockerfile.worker,Dockerfile.test"
description: "CI/CD, Docker, and build rules for IronClaw. Apply when editing GitHub Actions workflows, docker-compose.yml, or Dockerfiles."
---

# CI/CD & Build Rules

## Windows — Smart App Control

**On Windows, Smart App Control blocks freshly compiled Rust binaries.** Docker is the only viable build and test path on Windows:

```powershell
docker compose up -d --build ironclaw   # build + run
docker compose exec ironclaw cargo test  # run tests inside container
```

Never attempt `cargo run` or `cargo test` directly on Windows hosts in this repo.

## GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `docker-publish.yml` | Push to `main` | Build + push `ironclaw` and `ironclaw-worker` to GHCR |
| `sync-upstream.yml` | Weekly Mon 02:00 UTC + manual | Auto-merge `upstream/staging` → `fork/main`; builds GHCR images inline |
| `test.yml` | Push, PR | Cargo unit tests |
| `staging-ci.yml` | Push to `staging` | Full integration test suite |
| `claude-review.yml` | PR | Automated code review |

## GHCR Image Names

```
ghcr.io/jzkk720/ironclaw:latest          # main runtime (target: runtime-staging)
ghcr.io/jzkk720/ironclaw-worker:latest   # sandbox worker
```

Both tagged with `:latest` and `:<git-sha>` on every build.

## Dockerfile Build Targets

| Target stage | Used for |
|-------------|---------|
| `runtime-staging` | Production image (used by `docker-publish.yml`) |
| `runtime` | Base runtime without staging extras |
| `builder` | Intermediate — do not use as final image |

## sync-upstream Mechanics

**GITHUB_TOKEN pushes do not re-trigger other workflows.** This is why `sync-upstream.yml` builds and pushes Docker images inline rather than relying on `docker-publish.yml` triggering after its push. If you add build steps to one workflow, check whether the other needs to be updated too.

## Watchtower

Watchtower is defined in `docker-compose.yml` and polls GHCR hourly. It only updates containers with label `com.centurylinklabs.watchtower.enable: "true"`. The `ironclaw` service has this label; `postgres` and others do not.

**One-time host prerequisite** (already documented in docker-compose.yml):
```bash
docker login ghcr.io -u jzkk720 -p <PAT with read:packages>
```

## Concurrency

Both `docker-publish.yml` and `sync-upstream.yml` use concurrency groups to prevent parallel builds of the same branch. `docker-publish.yml` cancels in-progress builds; `sync-upstream.yml` does not (to avoid skipping a sync).
