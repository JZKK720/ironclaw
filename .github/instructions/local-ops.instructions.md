---
applyTo: "docker-compose.yml,.env,README.md,deploy/**,docs/drafts/install/**,docs/drafts/platforms/**"
description: "Local Docker rollout and state-safety rules for IronClaw. Apply when working on docker compose pull/recreate flows, local container updates, backup or rollback docs, runtime image pins, or operator-owned state such as .env, IRONCLAW_HOME_DIR, and the external Postgres volume."
---

# Local Ops Rules

## Protected State

- Treat `.env`, `IRONCLAW_HOME_DIR`, the repo-local `extensions/ironclaw-home` fallback, and the external `ironclaw-pgdata` volume as operator-owned state.
- Never overwrite, delete, or rotate secrets in `.env` as part of a normal upgrade.
- Never use `docker compose down -v` or remove named volumes during a routine local update unless the user explicitly asks for destructive cleanup.

## Preferred Rollout Modes

- For local upgrades to already-published images, prefer pull mode: `docker compose pull` followed by `docker compose up -d --no-build postgres ironclaw`.
- Pull the worker image as well when runtime and sandbox versions must stay aligned, even though the `ironclaw-worker` compose service is build-only.
- Use `docker compose up -d --build ironclaw` only when validating unpublished source changes instead of a GHCR rollout.
- Respect `IRONCLAW_APP_IMAGE` and `SANDBOX_IMAGE` pins in `.env`. Do not silently switch users from a pinned tag or digest back to `:latest`.

## Preflight Checks

- Capture the current runtime before changing anything: `docker compose ps`, `docker compose images`, and `docker compose config`.
- Verify the running gateway before and after rollout with `http://127.0.0.1:3231/api/health`.
- When upstream code changed, validate GHCR and release-channel safety before instructing operators to pull new images.

## Backup and Rollback Discipline

- Back up `.env` before any pull or recreate step, but never print secret values in logs or chat.
- Dump PostgreSQL with `pg_dump` before recreating containers when data recovery matters.
- Back up the directory referenced by `IRONCLAW_HOME_DIR`; if that variable is unset, back up `extensions/ironclaw-home` instead.
- Record the current image tags or digests before pulling replacements so rollback can repin the previous known-good runtime.
- Restore the database only when a migration or data regression requires it; routine app rollbacks should start by repinning images and restoring bind-mounted state.

## Windows

- On Windows, do not recommend host `cargo` commands for rollout validation. Use Docker-based checks instead.

## Related Guidance

- Use `/validate-ghcr-upgrade` when the question is whether a new fork image is safe to publish or consume.
- Use `/update-local-docker-runtime` for the full backup-first local rollout checklist.