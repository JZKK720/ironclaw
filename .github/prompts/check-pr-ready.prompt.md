---
description: "Pre-commit discipline checklist for IronClaw. Run before opening a PR or pushing to main — verifies clippy, tests, no-panic policy, security-sensitive paths, and documentation parity."
---

# Pre-commit Readiness Check

Run these checks in order before pushing. Stop at the first failure and fix it.

## 1. Format

```bash
cargo fmt --check
```

Fix with: `cargo fmt`

## 2. Clippy (zero warnings)

```bash
cargo clippy --all --benches --tests --examples --all-features 2>&1 | grep -E "^error|warning\["
```

Every warning is a blocker. Fix all of them — including pre-existing ones in files you changed.

## 3. No panics in production code

```bash
grep -rn '\.unwrap()\|\.expect(' src/ | grep -v '//.*unwrap\|#\[cfg(test)\]' | head -20
```

`unwrap()`/`expect()` are allowed only in:
- `mod tests {}` blocks
- Truly infallible invariants with a safety comment explaining why they can't fail (e.g., compiled regex literals)

## 4. Import hygiene

```bash
grep -rn 'use crate::safety\|use crate::skills::Skill' src/ | grep -v 'mod\.rs' | head -10
```

`ironclaw_safety` and `ironclaw_skills` types must be imported from their crates directly, not via `crate::safety::`.

## 5. Dual-backend compilation (if touching db/ or migrations/)

```bash
cargo check --no-default-features --features libsql
cargo check --all-features
```

## 6. Unit tests pass

```bash
cargo test 2>&1 | tail -10
```

## 7. Regression test present (if fixing a bug)

Every bug fix must include a test that would have caught it. Verify:
```bash
git diff --name-only HEAD~1 | grep -E 'tests/|_test\.rs|mod tests'
```

If no test files changed and this is a bug fix, add a regression test before committing.

## 8. FEATURE_PARITY.md (if behavior changed)

Does this change add, remove, or alter a user-visible feature?

```bash
grep -i "<feature keyword>" FEATURE_PARITY.md
```

If the feature is tracked (`❌`, `🚧`, `✅`), update its status in the same commit.

## 9. Security-sensitive paths

If any of these were touched, review with a security mindset:
- `src/channels/web/auth.rs` — bearer token middleware
- `src/secrets/` — secret storage / encryption
- `src/sandbox/proxy/` — credential injection, network allowlist
- `src/tools/wasm/allowlist.rs` — WASM network allowlist
- Any route handler in `src/channels/web/handlers/`

Verify: auth not weakened, body limits/rate limits preserved, containers still untrusted.

## 10. Pre-commit safety script

```bash
bash scripts/pre-commit-safety.sh
```

This catches: UTF-8 byte slicing, hardcoded `/tmp/`, logging of sensitive data, and direct state mutations in handlers that bypass `ToolDispatcher::dispatch()`.

---

If all 10 checks pass: you're ready to push.
