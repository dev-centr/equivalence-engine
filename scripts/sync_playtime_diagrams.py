#!/usr/bin/env python3
"""Synchronize the canonical PlayTime SVG deliverables from general-knowledge."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPOSITORY_ROOT / "docs/modules/ROOT/images/playtime-diagrams.provenance.json"


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def git(source_repo: Path, *arguments: str) -> bytes:
    result = subprocess.run(
        ["git", "-C", str(source_repo), *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(message or f"git {' '.join(arguments)} failed")
    return result.stdout


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def source_bytes(source_repo: Path, commit: str, path: str) -> bytes:
    return git(source_repo, "show", f"{commit}:{path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="report drift without writing files",
    )
    parser.add_argument(
        "--source-repo",
        type=Path,
        help="general-knowledge checkout (required for synchronization)",
    )
    args = parser.parse_args()

    manifest = load_manifest()
    commit = manifest["source"]["commit"]
    failures: list[str] = []

    if not args.check and args.source_repo is None:
        parser.error("--source-repo is required unless --check is used")

    if args.source_repo is not None:
        source_repo = args.source_repo.resolve()
        resolved_commit = (
            git(source_repo, "rev-parse", f"{commit}^{{commit}}")
            .decode("ascii")
            .strip()
        )
        if resolved_commit != commit:
            failures.append(
                f"source commit resolved to {resolved_commit}, expected {commit}"
            )

    for artifact in manifest["artifacts"]:
        relative_path = artifact["path"]
        expected_hash = artifact["sha256"]
        destination = REPOSITORY_ROOT / relative_path
        canonical: bytes | None = None

        if args.source_repo is not None:
            canonical = source_bytes(source_repo, commit, relative_path)
            canonical_hash = digest(canonical)
            if canonical_hash != expected_hash:
                failures.append(
                    f"{relative_path}: source hash {canonical_hash}, "
                    f"manifest says {expected_hash}"
                )
                continue

        if args.check:
            if not destination.is_file():
                failures.append(f"{relative_path}: missing")
                continue
            actual_hash = digest(destination.read_bytes())
            if actual_hash != expected_hash:
                failures.append(
                    f"{relative_path}: hash {actual_hash}, expected {expected_hash}"
                )
            if canonical is not None and destination.read_bytes() != canonical:
                failures.append(f"{relative_path}: differs from canonical source bytes")
        else:
            assert canonical is not None
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(canonical)
            print(f"synchronized {relative_path}")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    action = "verified" if args.check else "synchronized"
    print(
        f"{action} {len(manifest['artifacts'])} artifacts from "
        f"{manifest['source']['repository']}@{commit}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
