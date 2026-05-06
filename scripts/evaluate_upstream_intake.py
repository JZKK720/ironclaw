#!/usr/bin/env python3
"""Summarize upstream intake candidates and GHCR rebuild impact.

This script compares a base ref (default: HEAD) against upstream main and
upstream staging, then prints a small intake report that answers two practical
questions:

1. Which upstream commits are still missing from this branch?
2. If a commit is adopted, does it require rebuilding the runtime image,
   the worker image, both, or neither?

Usage:

    python scripts/evaluate_upstream_intake.py --fetch

The report is heuristic. It highlights likely cherry-pick candidates, commits
that probably deserve a full-sync review, and docs-only changes that can
usually be skipped for deployment purposes.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
from dataclasses import asdict, dataclass


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent

RUNTIME_IMAGE_INPUT_PREFIXES = (
    "src/",
    "crates/",
    "migrations/",
    "registry/",
    "channels-src/",
    "tools-src/",
    "wit/",
    "profiles/",
)

RUNTIME_IMAGE_INPUT_FILES = {
    "Dockerfile",
    "Cargo.toml",
    "Cargo.lock",
    "build.rs",
    "providers.json",
}

WORKER_IMAGE_INPUT_PREFIXES = (
    "src/",
    "crates/",
    "migrations/",
)

WORKER_IMAGE_INPUT_FILES = {
    "Dockerfile.worker",
    "Cargo.toml",
    "Cargo.lock",
    "build.rs",
    "providers.json",
}

FULL_SYNC_REVIEW_PREFIXES = (
    "migrations/",
    "src/db/",
    "src/history/",
)

FULL_SYNC_REVIEW_FILES = {
    "Cargo.toml",
    "Cargo.lock",
    "Dockerfile",
    "Dockerfile.worker",
}

SECURITY_SENSITIVE_PREFIXES = (
    "src/bridge/",
    "src/agent/",
    "src/secrets/",
    "src/sandbox/",
    "src/tools/wasm/",
    "src/channels/web/",
)

FORK_HOTSPOTS = {
    "src/extensions/manager.rs",
    "src/channels/wasm/setup.rs",
}


class GitError(RuntimeError):
    pass


@dataclass
class RangeSummary:
    label: str
    revspec: str
    count: int


@dataclass
class CommitAssessment:
    sha: str
    subject: str
    files: list[str]
    recommendation: str
    reasons: list[str]
    runtime_image_rebuild: bool
    worker_image_rebuild: bool
    docs_only: bool
    security_sensitive: bool
    full_sync_review: bool
    fork_hotspot: bool


def run_git(*args: str, check: bool = True) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if check and completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or f"git {' '.join(args)} failed"
        raise GitError(detail)
    return completed.stdout.strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref", default="HEAD", help="Base ref to evaluate from.")
    parser.add_argument(
        "--upstream-main",
        default="upstream/main",
        help="Stable upstream branch to compare against.",
    )
    parser.add_argument(
        "--upstream-staging",
        default="upstream/staging",
        help="Candidate upstream branch to compare against.",
    )
    parser.add_argument(
        "--max-commits",
        type=int,
        default=20,
        help="Maximum commits to print per report section.",
    )
    parser.add_argument(
        "--fetch",
        action="store_true",
        help="Fetch origin and upstream before evaluating refs.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of text.",
    )
    parser.add_argument(
        "--write",
        help="Optional path to write the report to in addition to stdout.",
    )
    return parser.parse_args()


def maybe_fetch() -> None:
    run_git("fetch", "origin", "--prune")
    run_git("fetch", "upstream", "main", "staging", "--prune")


def resolve_ref(ref: str) -> str:
    return run_git("rev-parse", ref)


def ahead_behind(left: str, right: str) -> tuple[int, int]:
    output = run_git("rev-list", "--left-right", "--count", f"{left}...{right}")
    left_count, right_count = output.split()
    return int(left_count), int(right_count)


def range_count(revspec: str) -> int:
    return int(run_git("rev-list", "--count", revspec))


def list_commits(revspec: str, max_commits: int) -> list[tuple[str, str]]:
    output = run_git(
        "log",
        "--reverse",
        f"--max-count={max_commits}",
        "--format=%H%x1f%s",
        revspec,
    )
    commits: list[tuple[str, str]] = []
    for line in output.splitlines():
        if not line.strip():
            continue
        sha, subject = line.split("\x1f", 1)
        commits.append((sha, subject))
    return commits


def list_files(commit: str) -> list[str]:
    output = run_git("show", "--pretty=format:", "--name-only", commit)
    return [line.strip() for line in output.splitlines() if line.strip()]


def has_prefix(paths: list[str], prefixes: tuple[str, ...]) -> bool:
    return any(path.startswith(prefix) for path in paths for prefix in prefixes)


def has_file(paths: list[str], files: set[str]) -> bool:
    return any(path in files for path in paths)


def is_runtime_rebuild(paths: list[str]) -> bool:
    return has_prefix(paths, RUNTIME_IMAGE_INPUT_PREFIXES) or has_file(
        paths, RUNTIME_IMAGE_INPUT_FILES
    )


def is_worker_rebuild(paths: list[str]) -> bool:
    return has_prefix(paths, WORKER_IMAGE_INPUT_PREFIXES) or has_file(
        paths, WORKER_IMAGE_INPUT_FILES
    )


def is_docs_only(paths: list[str]) -> bool:
    if not paths:
        return False
    for path in paths:
        if path.startswith("docs/"):
            continue
        if path.endswith(".md"):
            continue
        return False
    return True


def is_full_sync_review(paths: list[str]) -> bool:
    return has_prefix(paths, FULL_SYNC_REVIEW_PREFIXES) or has_file(
        paths, FULL_SYNC_REVIEW_FILES
    )


def is_security_sensitive(paths: list[str]) -> bool:
    return has_prefix(paths, SECURITY_SENSITIVE_PREFIXES)


def touches_fork_hotspot(paths: list[str]) -> bool:
    return any(path in FORK_HOTSPOTS for path in paths)


def assess_commit(sha: str, subject: str) -> CommitAssessment:
    files = list_files(sha)
    docs_only = is_docs_only(files)
    runtime_rebuild = is_runtime_rebuild(files)
    worker_rebuild = is_worker_rebuild(files)
    full_sync_review = is_full_sync_review(files)
    security_sensitive = is_security_sensitive(files)
    fork_hotspot = touches_fork_hotspot(files)

    reasons: list[str] = []
    if docs_only:
        recommendation = "skip"
        reasons.append("docs-only change")
    else:
        recommendation = "cherry-pick-candidate"
        if full_sync_review:
            recommendation = "review-full-sync"
            reasons.append("touches migrations, lockfiles, or Docker build surfaces")
        if security_sensitive:
            recommendation = "review-carefully"
            reasons.append("touches security-sensitive runtime paths")
        if fork_hotspot:
            recommendation = "review-carefully"
            reasons.append("touches known fork hotspot files")
        if not reasons:
            reasons.append("isolated change with no obvious lockstep surface")

    if runtime_rebuild:
        reasons.append("runtime GHCR image would need a rebuild")
    if worker_rebuild:
        reasons.append("worker GHCR image would need a rebuild")

    return CommitAssessment(
        sha=sha,
        subject=subject,
        files=files,
        recommendation=recommendation,
        reasons=reasons,
        runtime_image_rebuild=runtime_rebuild,
        worker_image_rebuild=worker_rebuild,
        docs_only=docs_only,
        security_sensitive=security_sensitive,
        full_sync_review=full_sync_review,
        fork_hotspot=fork_hotspot,
    )


def render_text(
    *,
    base_ref: str,
    base_sha: str,
    upstream_main: str,
    upstream_main_sha: str,
    upstream_staging: str,
    upstream_staging_sha: str,
    main_divergence: tuple[int, int],
    staging_divergence: tuple[int, int],
    ranges: list[RangeSummary],
    assessments: dict[str, list[CommitAssessment]],
    max_commits: int,
) -> str:
    lines = [
        "Upstream Intake Report",
        "=====================",
        "",
        f"Base ref:          {base_ref} ({base_sha[:12]})",
        f"Upstream main:     {upstream_main} ({upstream_main_sha[:12]})",
        f"Upstream staging:  {upstream_staging} ({upstream_staging_sha[:12]})",
        "",
        "Divergence:",
        f"  {base_ref} vs {upstream_main}: ahead {main_divergence[0]}, behind {main_divergence[1]}",
        f"  {base_ref} vs {upstream_staging}: ahead {staging_divergence[0]}, behind {staging_divergence[1]}",
        "",
    ]

    for summary in ranges:
        lines.append(f"{summary.label}: {summary.count} commit(s)")
        items = assessments[summary.label]
        if not items:
            lines.append("  none")
            lines.append("")
            continue
        for item in items:
            lines.append(
                f"  - {item.sha[:12]} {item.subject} [{item.recommendation}]"
            )
            lines.append(
                f"    rebuilds: runtime={'yes' if item.runtime_image_rebuild else 'no'}, worker={'yes' if item.worker_image_rebuild else 'no'}"
            )
            if item.files:
                shown = ", ".join(item.files[:6])
                if len(item.files) > 6:
                    shown += ", ..."
                lines.append(f"    files: {shown}")
            lines.append(f"    why: {'; '.join(item.reasons)}")
        if summary.count > max_commits:
            lines.append(
                f"  ... output truncated to first {max_commits} commit(s); rerun with --max-commits {summary.count} to see all"
            )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    args = parse_args()
    try:
        if args.fetch:
            maybe_fetch()

        base_sha = resolve_ref(args.base_ref)
        upstream_main_sha = resolve_ref(args.upstream_main)
        upstream_staging_sha = resolve_ref(args.upstream_staging)

        main_divergence = ahead_behind(args.base_ref, args.upstream_main)
        staging_divergence = ahead_behind(args.base_ref, args.upstream_staging)

        ranges = [
            RangeSummary(
                label="Incoming from upstream/main",
                revspec=f"{args.base_ref}..{args.upstream_main}",
                count=range_count(f"{args.base_ref}..{args.upstream_main}"),
            ),
            RangeSummary(
                label="Incoming from upstream/staging",
                revspec=f"{args.base_ref}..{args.upstream_staging}",
                count=range_count(f"{args.base_ref}..{args.upstream_staging}"),
            ),
            RangeSummary(
                label="Staging-only upstream delta",
                revspec=f"{args.upstream_main}..{args.upstream_staging}",
                count=range_count(f"{args.upstream_main}..{args.upstream_staging}"),
            ),
        ]

        assessments: dict[str, list[CommitAssessment]] = {}
        for summary in ranges:
            commits = list_commits(summary.revspec, args.max_commits)
            assessments[summary.label] = [
                assess_commit(sha, subject) for sha, subject in commits
            ]

        payload = {
            "base_ref": args.base_ref,
            "base_sha": base_sha,
            "upstream_main": args.upstream_main,
            "upstream_main_sha": upstream_main_sha,
            "upstream_staging": args.upstream_staging,
            "upstream_staging_sha": upstream_staging_sha,
            "divergence": {
                "base_vs_upstream_main": {
                    "ahead": main_divergence[0],
                    "behind": main_divergence[1],
                },
                "base_vs_upstream_staging": {
                    "ahead": staging_divergence[0],
                    "behind": staging_divergence[1],
                },
            },
            "ranges": [asdict(summary) for summary in ranges],
            "assessments": {
                label: [asdict(item) for item in items]
                for label, items in assessments.items()
            },
        }

        if args.json:
            rendered = json.dumps(payload, indent=2) + "\n"
        else:
            rendered = render_text(
                base_ref=args.base_ref,
                base_sha=base_sha,
                upstream_main=args.upstream_main,
                upstream_main_sha=upstream_main_sha,
                upstream_staging=args.upstream_staging,
                upstream_staging_sha=upstream_staging_sha,
                main_divergence=main_divergence,
                staging_divergence=staging_divergence,
                ranges=ranges,
                assessments=assessments,
                max_commits=args.max_commits,
            )

        sys.stdout.write(rendered)

        if args.write:
            output_path = pathlib.Path(args.write)
            if not output_path.is_absolute():
                output_path = REPO_ROOT / output_path
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(rendered, encoding="utf-8")

        return 0
    except GitError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())