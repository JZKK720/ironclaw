---
applyTo: "src/**/*.rs,tests/**"
description: "Testing rules for IronClaw. Apply when writing or modifying Rust source or test files — covers test tiers, the caller-not-helper rule, and mock hygiene."
---

# Testing Rules

Full rules: [.claude/rules/testing.md](../../.claude/rules/testing.md)

## Test Tiers

| Tier | Command | External deps |
|------|---------|---------------|
| Unit | `cargo test` | None |
| Integration | `cargo test --features integration` | Running PostgreSQL |
| Live | `cargo test --features integration -- --ignored` | PostgreSQL + LLM API keys |

Run `bash scripts/check-boundaries.sh` to verify test tier gating.

## Key Patterns

- Unit tests in `mod tests {}` at the bottom of each file; async tests with `#[tokio::test]`
- Use `tempfile` crate for test directories — never hardcode `/tmp/`
- No mocks by default; prefer real implementations or lightweight stubs
- Every bug fix **must** include a regression test

## Test Through the Caller, Not Just the Helper

When a helper **predicate/classifier/transform** gates a side effect (HTTP, DB write, tool execution, OAuth), and there is at least one wrapper between the helper and the side effect, a unit test on the helper alone is **not sufficient**.

You must also add a test driving the actual call site (`*_handler`, `factory::create_*`, `manager::*`) at the integration tier.

**Real examples of bugs this rule would have caught:**

| Bug | What was missed |
|-----|----------------|
| `McpServerConfig::has_custom_auth_header()` existed but `requires_auth()` never called it → OAuth triggered even with a user-set header | Test driving `mcp::factory::create_client_from_config()` |
| `derive_activation_status` wrapper hardcoded `has_paired=false`, ignoring real DB state | Test driving `extensions_list_handler` against a DB with a `channel_identities` row |

The rule applies when **all three** are true:
1. Helper is a predicate/classifier/transform gating a side effect
2. There is at least one wrapper between helper and side effect
3. The helper has more than one input, or the caller computes any input from context

## Mock Hygiene

Mock signatures must match the production call site. A `(url) => {}` stub for a `window.open(url, target, features)` call site silently swallows `target` and `features`. Assert every argument.
