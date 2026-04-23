---
applyTo: "src/db/**,src/history/**,migrations/**"
description: "Database rules for IronClaw dual-backend persistence (PostgreSQL + libSQL). Apply when editing db/, history/, or migration files."
---

# Database Rules

Full rules: [.claude/rules/database.md](../../.claude/rules/database.md)

**All new persistence features must support both PostgreSQL and libSQL.** See [src/db/CLAUDE.md](../../src/db/CLAUDE.md).

## Adding a New Operation

1. Add the async method to the relevant sub-trait in `src/db/mod.rs`
2. Implement in `src/db/postgres.rs`
3. Implement in `src/db/libsql/<module>.rs` (use `self.connect().await?` per operation)
4. Add migration if needed:
   - PostgreSQL: new `migrations/VN__description.sql`
   - libSQL: entry in `INCREMENTAL_MIGRATIONS` in `libsql_migrations.rs`
   - **Version numbering**: always number after the highest version on `staging`/`main` — check with `git ls-tree origin/staging migrations/`
5. Verify dual compilation:
   ```bash
   cargo check                                          # postgres (default)
   cargo check --no-default-features --features libsql  # libsql only
   cargo check --all-features                           # both
   ```

## SQL Dialect Quick Reference

| PostgreSQL | libSQL |
|-----------|--------|
| `UUID` | `TEXT` |
| `TIMESTAMPTZ` | `TEXT` (ISO-8601, use `fmt_ts()` / `get_ts()`) |
| `JSONB` | `TEXT` (JSON string) |
| `BOOLEAN` | `INTEGER` (0/1, read with `get_i64(row, idx) != 0`) |
| `NUMERIC` | `TEXT` (rust_decimal) |
| `TEXT[]` | `TEXT` (JSON array) |
| `VECTOR` | `BLOB` (brute-force search fallback) |
| `jsonb_set(col, '{key}', val)` | `json_patch(col, '{"key": val}')` |
| `DEFAULT NOW()` | `DEFAULT (datetime('now'))` |

## Key Rules

- Multi-step operations (INSERT+INSERT, UPDATE+DELETE, read-modify-write) **MUST** be wrapped in a transaction
- `LibSqlBackend::connect()` creates a fresh connection per operation — never hold across `await` points
- Schema translation is more than DDL: check indexes, seed data (`INSERT INTO`), and triggers
