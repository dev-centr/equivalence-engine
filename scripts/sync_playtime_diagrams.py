#!/usr/bin/env python3
"""Synchronize and verify pinned PlayTime SVG deliverables from Scriptbook."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPOSITORY_ROOT / "docs/modules/ROOT/images/playtime-diagrams.provenance.json"
SOURCE_REPOSITORY = "https://github.com/dev-centr/scriptbook"
SOURCE_COMMIT = "97534371f0da8d81e495cb4cc069704902dbdd69"
DIAGRAM_NAMES = (
    "playtime-argv",
    "playtime-attic-basement",
    "playtime-bind-flow",
    "playtime-bootstrap",
    "playtime-facets-not-lattice",
    "playtime-growth-ratchet",
    "playtime-layers",
    "playtime-overlays",
    "playtime-sibling-home",
    "playtime-two-doors",
    "playtime-venn",
    "playtime-wrong-translator",
)


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


def refresh_manifest(source_repo: Path) -> None:
    artifacts = []
    for name in DIAGRAM_NAMES:
        for suffix, source_path in (
            (".svg", f"spec/images/{name}.svg"),
            (".host.svg", f"spec/images/{name}.host.svg"),
            (".fixed.svg", f"spec/images/fixed/{name}.svg"),
        ):
            content = source_bytes(source_repo, SOURCE_COMMIT, source_path)
            artifacts.append(
                {
                    "path": f"docs/modules/ROOT/images/{name}{suffix}",
                    "sourcePath": source_path,
                    "sha256": digest(content),
                }
            )
    manifest = {
        "schema": 1,
        "source": {
            "repository": f"{SOURCE_REPOSITORY}.git",
            "commit": SOURCE_COMMIT,
            "authority": "spec/diagrams and spec/images",
        },
        "notes": [
            "Unsuffixed files are standalone-adaptive SVGs.",
            ".host.svg files are runtime-inline host SVGs.",
            ".fixed.svg files preserve Scriptbook's original fixed artwork.",
        ],
        "artifacts": artifacts,
    }
    MANIFEST_PATH.write_text(
        f"{json.dumps(manifest, indent=2)}\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="report drift without writing files",
    )
    parser.add_argument("--source-repo", type=Path, help="Scriptbook checkout (required for synchronization)")
    args = parser.parse_args()

    failures: list[str] = []

    if not args.check and args.source_repo is None:
        parser.error("--source-repo is required unless --check is used")

    if args.source_repo is not None:
        source_repo = args.source_repo.resolve()
        if not args.check:
            refresh_manifest(source_repo)

    manifest = load_manifest()
    commit = manifest["source"]["commit"]

    if args.source_repo is not None:
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
        source_path = artifact.get("sourcePath")
        expected_hash = artifact["sha256"]
        destination = REPOSITORY_ROOT / relative_path
        canonical: bytes | None = None

        if args.source_repo is not None and source_path:
            canonical = source_bytes(source_repo, commit, source_path)
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
        elif source_path:
            assert canonical is not None
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(canonical)
            print(f"synchronized {relative_path}")
        elif not destination.is_file() or digest(destination.read_bytes()) != expected_hash:
            failures.append(f"{relative_path}: preserved fixed asset is missing or modified")

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
