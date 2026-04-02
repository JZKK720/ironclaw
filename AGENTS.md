# Agent Rules

## Purpose and Precedence

- `AGENTS.md` is the quick-start contract for coding agents. It is not the full architecture spec.
- Read the relevant subsystem spec before changing a complex area. When a repo spec exists, treat it as authoritative.
Start with these deeper docs as needed:
- `CLAUDE.md`
- `src/agent/CLAUDE.md`
- `src/channels/web/CLAUDE.md`
- `src/db/CLAUDE.md`
- `src/llm/CLAUDE.md`
- `src/setup/README.md`
- `src/tools/README.md`
- `src/workspace/README.md`
- `src/NETWORK_SECURITY.md`
- `tests/e2e/CLAUDE.md`

## Release Alignment Workflow

- `origin/main` is the promoted runtime baseline and the only push target. `upstream` points at `nearai/ironclaw` and is fetch-only; never plan or execute pushes to `upstream`.
- If local git config exposes a push URL for `upstream`, treat it as accidental capability and do not use it. Keep all publishing on `origin/main`.
- Historical validation branches `v0.23-fresh-install`, `v0.23-fresh-install-local`, and `v0.23-fresh-install-refresh` are retired. Do not use them for new update work unless you are doing forensic comparison.
- Before proposing update work, compare `origin/main` with `upstream/main` and `upstream/staging`, then selectively pull in missing upstream commits.
- For fresh-install or rebuild work, treat `upstream/staging` as the clean baseline candidate. Carry forward fork-local commits only after verifying that current upstream `v0.24` behavior still needs them.
- Assume historical Docker/setup/polling/cutover patches are disposable until proven necessary on the fresh baseline. Prefer replaying the smallest verified subset over preserving legacy compatibility changes.
- Prefer updating the fork baseline directly instead of creating new long-lived release-alignment branches.
- When the running container and local git history disagree, verify which checkout and commit the container actually mounts before changing code. Use container labels, mounts, `docker-compose.yml`, `docker-compose.build.yml`, `docker-compose.override.yml`, `scripts/bootstrap.sh`, and `scripts/Bootstrap.ps1` as the runtime source-of-truth references.
- Keep `README.v0.23-fresh-install.md` as a historical cutover/setup reference, not as the active branch authority.
- Record which upstream commits were cherry-picked, skipped, or deferred when staging diverges from main, and which fork-local commits were intentionally kept or dropped during rebuild work.

## Architecture Mental Model

- Channels normalize external input into `IncomingMessage`; `ChannelManager` merges all active channel streams.
- `Agent` owns session/thread/turn handling, submission parsing, the LLM/tool loop, approvals, routines, and background runtime behavior.
- `AppBuilder` is the composition root that wires database, secrets, LLMs, tools, workspace, extensions, skills, hooks, and cost controls before the agent starts.
- The web gateway is a browser-facing API/UI layered on top of the same agent/session/tool systems, not a separate product path.

## Where to Work

- Agent/runtime behavior: `src/agent/`
- Web gateway/API/SSE/WebSocket: `src/channels/web/`
- Persistence and DB abstractions: `src/db/`
- Setup/onboarding/configuration flow: `src/setup/`
- LLM providers and routing: `src/llm/`
- Workspace, memory, embeddings, search: `src/workspace/`
- Extensions, tools, channels, MCP, WASM: `src/extensions/`, `src/tools/`, `src/channels/`

## Ownership and Composition Rules

- Keep `src/main.rs` and `src/app.rs` orchestration-focused. Do not move module-owned logic into entrypoints.
- Module-specific initialization should live in the owning module behind a public factory/helper, not be reimplemented ad hoc.
- Keep feature-flag branching inside the module that owns the abstraction whenever possible.
- Prefer extending existing traits and registries over hardcoding one-off integration paths.

## Repo-Wide Coding Rules

- Avoid `.unwrap()` and `.expect()` in production; prefer proper error handling. They are fine in tests, and in production only for truly infallible invariants (e.g., literals/regexes) with a safety comment.
- Keep clippy clean with zero warnings.
- Prefer `crate::` imports for cross-module references.
- Use strong types and enums over stringly-typed control flow when the shape is known.

## Database, Setup, and Config Rules

- New persistence behavior must support both PostgreSQL and libSQL.
- Add new DB operations to the shared DB trait first, then implement both backends.
- Treat bootstrap config, DB-backed settings, and encrypted secrets as distinct layers; do not collapse them casually.
- If onboarding or setup behavior changes, update `src/setup/README.md` in the same branch.
- Do not break config precedence, bootstrap env loading, DB-backed config reload, or post-secrets LLM re-resolution.

## Security and Runtime Invariants

- Review any change touching listeners, routes, auth, secrets, sandboxing, approvals, or outbound HTTP with a security mindset.
- Do not weaken bearer-token auth, webhook auth, CORS/origin checks, body limits, rate limits, allowlists, or secret-handling guarantees.
- Treat Docker containers and external services as untrusted.
- Session/thread/turn state matters. Submission parsing happens before normal chat handling.
- Skills are selected deterministically. Tool approval and auth flows are special paths and must not be mixed into normal chat history carelessly.
- Persistent memory is the workspace system, not just transcript storage; preserve file-like semantics, chunking/search behavior, and identity/system-prompt loading.

## Tools, Channels, and Extensions

- Use a built-in Rust tool for core internal capabilities tightly coupled to the runtime.
- Use WASM tools or WASM channels for sandboxed extensions and plugin-style integrations.
- Use MCP for external server integrations when the capability belongs outside the main binary.
- Preserve extension lifecycle expectations: install, authenticate/configure, activate, remove.

## Docs, Parity, and Testing

- If behavior changes, update the relevant docs/specs in the same branch.
- If you change implementation status for any feature tracked in `FEATURE_PARITY.md`, update that file in the same branch.
- Do not open a PR that changes feature behavior without checking `FEATURE_PARITY.md` for needed status updates (`❌`, `🚧`, `✅`, notes, and priorities).
- Add the narrowest tests that validate the change: unit tests for local logic, integration tests for runtime/DB/routing behavior, and E2E or trace coverage for gateway, approvals, extensions, or other user-visible flows.
- **Test through the caller, not just the helper.** When a predicate/classifier/transform helper gates a side effect (HTTP, DB write, OAuth flow, UI mutation, tool execution) and has any wrapper or computed input between it and that side effect, a unit test on the helper alone is not sufficient regression coverage. Add a test that drives the actual call site (`*_handler`, `factory::create_*`, `manager::*`) at the integration tier or higher. Mocks of multi-arg runtime APIs must capture every argument the production caller passes. See `.claude/rules/testing.md` for the full rule and bug examples.

## Risk and Change Discipline

- Keep changes scoped; avoid broad refactors unless the task truly requires them.
- Security, database schema, runtime, worker, CI, and secrets changes are high-risk. Call out rollback risks, compatibility concerns, and hidden side effects.
- Preserve existing defaults unless the task explicitly changes them.
- Avoid unrelated file churn and generated-file edits unless required.
- Respect a dirty worktree and never revert user changes you did not make.

## Before Finishing

- Confirm whether behavior changes require updates to `FEATURE_PARITY.md`, specs, API docs, or `CHANGELOG.md`.
- Run the most targeted tests/checks that cover the change.
- Re-check security-sensitive paths when touching auth, secrets, network listeners, sandboxing, or approvals.
- Keep the final diff scoped to the task.
