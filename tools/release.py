#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "build.zig.zon"
CHANGELOG = ROOT / "CHANGELOG.md"
README = ROOT / "README.md"
DISTRIBUTION = ROOT / "docs" / "maintaining" / "distribution.md"
GETTING_STARTED = ROOT / "docs" / "getting-started.md"


def manifest_version() -> str:
    text = MANIFEST.read_text(encoding="utf-8")
    match = re.search(r'\.version\s*=\s*"([^"]+)"', text)
    if not match:
        raise SystemExit("build.zig.zon has no .version field")
    return match.group(1)


def release_section(version: str) -> str:
    text = CHANGELOG.read_text(encoding="utf-8")
    heading = re.compile(
        rf"^##\s+\[?{re.escape(version)}\]?\s+-\s+\d{{4}}-\d{{2}}-\d{{2}}\s*$",
        re.MULTILINE,
    )
    match = heading.search(text)
    if not match:
        raise SystemExit(
            f"CHANGELOG.md has no '## [{version}] - YYYY-MM-DD' release heading"
        )

    start = match.end()
    next_heading = re.search(r"^##\s+", text[start:], re.MULTILINE)
    end = start + next_heading.start() if next_heading else len(text)
    body = text[start:end].strip()
    if not body:
        raise SystemExit(f"CHANGELOG.md release section {version} is empty")
    return body + "\n"


def validate_project_metadata(version: str) -> None:
    readme = README.read_text(encoding="utf-8")
    expected_badge = (
        "[version-badge]: "
        f"https://img.shields.io/badge/version-{version}-555.svg"
    )
    if expected_badge not in readme:
        raise SystemExit(
            f"README.md version badge does not match {version}"
        )

    expected_archive = f"https://github.com/ekkolon/zymbol/archive/refs/tags/v{version}.tar.gz"
    for path in (README, GETTING_STARTED):
        if expected_archive not in path.read_text(encoding="utf-8"):
            raise SystemExit(
                f"{path.relative_to(ROOT)} installation URL does not match {version}"
            )

    distribution = DISTRIBUTION.read_text(encoding="utf-8")
    expected_row = f"| Version | `{version}` |"
    if expected_row not in distribution:
        raise SystemExit(
            f"docs/maintaining/distribution.md version does not match {version}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("tag", nargs="?", help="release tag, for example v1.0.0")
    parser.add_argument("--notes-out", type=pathlib.Path)
    parser.add_argument("--print-manifest-tag", action="store_true")
    args = parser.parse_args()

    if args.print_manifest_tag:
        print(f"v{manifest_version()}")
        return

    if args.tag is None:
        parser.error("tag is required unless --print-manifest-tag is used")

    match = re.fullmatch(r"v(\d+\.\d+\.\d+)", args.tag)
    if not match:
        raise SystemExit(f"invalid release tag: {args.tag!r}")

    version = match.group(1)
    manifest = manifest_version()
    if manifest != version:
        raise SystemExit(
            f"release tag {args.tag} does not match build.zig.zon version {manifest}"
        )

    validate_project_metadata(version)
    notes = release_section(version)
    if args.notes_out:
        args.notes_out.write_text(notes, encoding="utf-8")

    print(f"release metadata valid: Zymbol {args.tag}")


if __name__ == "__main__":
    main()
