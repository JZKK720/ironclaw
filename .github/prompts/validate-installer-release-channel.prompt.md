---
description: "Validate whether the fork-owned installer and release channel is actually wired up. Use when checking PowerShell or shell installer URLs, MSI or zip downloads, cargo-dist GitHub releases, release-plz gates, registry artifact URLs, or whether a GHCR rollout will also reach downstream binary/install surfaces."
---

# Validate Installer Release Channel

Use this when you need to answer: "If we publish or upgrade from this fork, will the installers, release assets, and embedded download URLs actually resolve to the fork-owned channel instead of upstream?"

## Inspect These Sources Together

- [README.md](../../README.md)
- [release-plz.toml](../../release-plz.toml)
- [.github/workflows/release.yml](../workflows/release.yml)
- [.github/workflows/release-plz.yml](../workflows/release-plz.yml)
- [.github/workflows/rebuild-release-image.yml](../workflows/rebuild-release-image.yml)
- [src/registry/installer.rs](../../src/registry/installer.rs)
- [Cargo.toml](../../Cargo.toml)
- [wix/main.wxs](../../wix/main.wxs)
- Relevant docs under [docs](../../docs)

## Workflow

1. Find every public install and update entrypoint.

- README install sections.
- Quickstart and infrastructure docs.
- PowerShell installer URLs.
- Shell installer URLs.
- Windows MSI or zip download links.
- Any `cargo install`, Homebrew, or binary-release guidance.

2. Verify the fork release pipeline is actually enabled.

- Check whether `release-plz.yml` is gated to a specific owner such as `nearai`.
- Check whether `release.yml` can still build GitHub Releases from fork-owned tags.
- Check whether any rebuild or historical-image workflows publish to the intended registry owner.

3. Verify embedded artifact URLs.

- Check `release.yml` manifest-patching steps for hardcoded `nearai/ironclaw` release URLs.
- Check `src/registry/installer.rs` and registry manifests for fallback logic or host allowlists that assume upstream release paths.
- Check whether the fork release assets, if produced, would still direct users or tools back to upstream.

4. Decide channel correctness explicitly.

- `Installer-safe` only if public docs and scripts point at the fork release owner.
- `Release-safe` only if the fork can create tags/releases without upstream-only guards.
- `Registry-safe` only if embedded artifact URLs and checksum logic point at fork-owned release assets.

## Required Output

Report findings first, then end with:

1. `Installer channel verdict`: `safe`, `partial`, or `not safe`
2. `Release automation verdict`: `safe`, `partial`, or `not safe`
3. `Registry artifact verdict`: `safe`, `partial`, or `not safe`
4. `Required follow-ups`: exact docs, workflows, scripts, or URLs that must change

Do not say the fork is release-ready if any installer entrypoint or embedded artifact URL still resolves to `nearai/ironclaw` unless that is explicitly the intended downstream channel.
