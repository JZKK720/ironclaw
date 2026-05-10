# Fork Workflow & Container Management

Quick reference for maintaining and updating the JZKK720 fork of IronClaw.

## Current Status

- **Local Version**: 0.28.0 (from `Cargo.toml`)
- **Fork**: `github.com/JZKK720/ironclaw` (origin)
- **Upstream**: `github.com/nearai/ironclaw` (upstream, fetch-only)
- **Container Registry**: `ghcr.io/jzkk720/ironclaw` (no local builds)
- **Database Volume**: `pgdata_v025` (PostgreSQL)

## Common Tasks

### 1. Check Fork Status

```bash
# Sync git metadata
git fetch origin && git fetch upstream

# See what's unique in fork vs upstream
git log --oneline upstream/main..origin/main

# See what's behind
git log --oneline origin/main..upstream/main
```

### 2. Pull Latest Container Images

```bash
# Get the latest from GHCR (no local build needed)
docker compose pull

# Restart with new images
docker compose up -d

# Verify the version
docker exec ironclaw ironclaw --version
```

### 3. Update to Specific Version

```bash
# Pin to v0.28.0 (for example)
export IRONCLAW_TAG=0.28.0
docker compose pull
docker compose up -d
```

### 4. Merge Upstream Changes

```bash
# Fetch upstream to see latest
git fetch upstream

# Compare main branches
git log --oneline upstream/main..origin/main  # commits in fork not in upstream
git log --oneline origin/main..upstream/main  # commits in upstream not in fork

# Cherry-pick specific commits from upstream
git cherry-pick <commit-hash>

# Or do a full merge (if appropriate)
git merge upstream/main

# Push to fork
git push origin main
```

### 5. Release a New Version

```bash
# Update version in Cargo.toml
sed -i 's/version = "0.28.0"/version = "0.29.0"/' Cargo.toml

# Commit
git add Cargo.toml
git commit -m "chore(fork): bump to v0.29.0"

# Push to origin/main
git push origin main

# CI will automatically:
# - Build the image
# - Tag as :0.29.0 (version tag)
# - Tag as :latest
# - Tag as :sha-<7chars> (commit hash)
# - Publish to ghcr.io/jzkk720/ironclaw
```

### 6. Test Changes on Staging Branch

```bash
# Create/update feature on staging branch
git checkout staging
git add .
git commit -m "test: new feature"
git push origin staging

# CI will automatically:
# - Build every hour (cron job)
# - Tag as :staging
# - Publish to ghcr.io/jzkk720/ironclaw:staging

# Pull and test locally
docker pull ghcr.io/jzkk720/ironclaw:staging
docker run -it ghcr.io/jzkk720/ironclaw:staging ironclaw --help

# When ready, merge to main
git checkout main
git merge staging
git push origin main
```

## Container Image Tags

| Tag | When | Source | Usage |
|-----|------|--------|-------|
| `:latest` | Release only | `main` branch | Production, default pull |
| `:staging` | Hourly | `staging` branch | Testing, nightly builds |
| `:0.28.0` | Release only | Version in Cargo.toml | Pinned releases |
| `:sha-abc1234` | Every build | Git commit hash | Specific commit debugging |

## Local Environment

Your local runtime preserves:

- ✅ `.env` — Database credentials, LLM config, API keys
- ✅ `pgdata_v025/` — PostgreSQL database volume (persists across restarts)
- ✅ `extensions/ironclaw-home/` — Custom extensions and skills
- ✅ `~/.ironclaw/` — Settings, workspace, persistent memory

These are **never** deleted or reset when running `docker compose up/down` or pulling new images.

## Troubleshooting

### Container doesn't have latest code

```bash
# Check what's running
docker inspect ironclaw | grep -i image

# Force pull latest
docker compose pull --no-parallel
docker compose down && docker compose up -d
```

### Database issues after update

```bash
# Check PostgreSQL health
docker exec ironclaw pg_isready

# View logs
docker compose logs postgres

# If needed, the volume pgdata_v025 persists between runs
# Only delete if you want to reset the database
docker volume rm pgdata_v025
```

### Git divergence

```bash
# See exactly what's different
git log --graph --oneline --decorate --all

# Resync to a known good state
git fetch origin
git reset --hard origin/main  # Local changes will be lost!
```

## References

- **Main docs**: See [AGENTS.md](../AGENTS.md) for detailed architecture
- **Workflows**: `.github/workflows/docker.yml` — Container build & publish
- **Release process**: `.github/workflows/release.yml` — Version bumping
- **Compose file**: `docker-compose.yml` — Local runtime configuration
