#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import re
import subprocess
from dataclasses import dataclass

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "build.zig.zon"
CHANGELOG = ROOT / "CHANGELOG.md"
README = ROOT / "README.md"
DISTRIBUTION = ROOT / "docs" / "distribution.md"

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
CONVENTIONAL_RE = re.compile(
    r"^(?P<type>[a-z]+)(?:\([^)]+\))?(?P<breaking>!)?:\s+(?P<description>.+)$"
)
PR_SUFFIX_RE = re.compile(r"\s+\(#(?P<pr>\d+)\)$")

TYPE_CATEGORY = {
    "feat": "Added",
    "fix": "Fixed",
    "perf": "Changed",
    "refactor": "Changed",
    "revert": "Changed",
    "security": "Security",
}
CATEGORY_ORDER = ("Added", "Changed", "Fixed", "Security")


@dataclass(frozen=True)
class Commit:
    subject: str
    body: str


@dataclass(frozen=True)
class Entry:
    category: str
    text: str
    breaking: bool


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def parse_version(value: str) -> tuple[int, int, int]:
    match = SEMVER_RE.fullmatch(value)
    if not match:
        raise SystemExit(f"invalid semantic version: {value!r}")
    return tuple(int(part) for part in match.groups())


def format_version(value: tuple[int, int, int]) -> str:
    return ".".join(str(part) for part in value)


def manifest_version() -> str:
    text = MANIFEST.read_text(encoding="utf-8")
    match = re.search(r'\.version\s*=\s*"([^"]+)"', text)
    if not match:
        raise SystemExit("build.zig.zon has no .version field")
    return match.group(1)


def latest_stable_tag() -> str | None:
    output = git("tag", "--list", "v[0-9]*", "--sort=-version:refname")
    for tag in output.splitlines():
        if SEMVER_RE.fullmatch(tag.removeprefix("v")):
            return tag
    return None


def commits_since(tag: str) -> list[Commit]:
    raw = git(
        "log",
        "--first-parent",
        "--reverse",
        "--format=%s%x1f%b%x1e",
        f"{tag}..HEAD",
    )
    commits: list[Commit] = []
    for record in raw.split("\x1e"):
        record = record.strip()
        if not record:
            continue
        subject, _, body = record.partition("\x1f")
        commits.append(Commit(subject=subject.strip(), body=body.strip()))
    return commits


def parse_entry(commit: Commit) -> Entry | None:
    subject = commit.subject
    pr: str | None = None
    pr_match = PR_SUFFIX_RE.search(subject)
    if pr_match:
        pr = pr_match.group("pr")
        subject = subject[: pr_match.start()]

    match = CONVENTIONAL_RE.fullmatch(subject)
    if not match:
        return None

    kind = match.group("type")
    category = TYPE_CATEGORY.get(kind)
    breaking = bool(match.group("breaking")) or "BREAKING CHANGE:" in commit.body
    if category is None and not breaking:
        return None
    if category is None:
        category = "Changed"

    description = match.group("description").strip().rstrip(".")
    if description:
        description = description[0].upper() + description[1:]
    if breaking:
        description = f"**Breaking:** {description}"
    if pr:
        description = f"{description} (#{pr})"

    return Entry(category=category, text=f"{description}.", breaking=breaking)


def bump_version(base: tuple[int, int, int], entries: list[Entry]) -> tuple[int, int, int]:
    if any(entry.breaking for entry in entries):
        return (base[0] + 1, 0, 0)
    if any(entry.category == "Added" for entry in entries):
        return (base[0], base[1] + 1, 0)
    if entries:
        return (base[0], base[1], base[2] + 1)
    raise SystemExit("no releasable feat/fix/perf/refactor/security commits since the latest tag")


def generated_notes(entries: list[Entry]) -> str:
    sections: list[str] = []
    for category in CATEGORY_ORDER:
        items = [entry.text for entry in entries if entry.category == category]
        if not items:
            continue
        body = "\n".join(f"- {item}" for item in items)
        sections.append(f"### {category}\n\n{body}")

    if not sections:
        raise SystemExit("release has no user-facing changelog entries")
    return "\n\n".join(sections)


def split_unreleased(text: str) -> tuple[str, str, str]:
    match = re.search(r"^##\s+\[?Unreleased\]?\s*$", text, re.MULTILINE)
    if not match:
        raise SystemExit("CHANGELOG.md has no Unreleased section")

    content_start = match.end()
    next_heading = re.search(r"^##\s+", text[content_start:], re.MULTILINE)
    content_end = content_start + next_heading.start() if next_heading else len(text)

    prefix = text[: match.start()].rstrip()
    body = text[content_start:content_end].strip()
    suffix = text[content_end:].lstrip()
    return prefix, body, suffix


def release_section_exists(text: str, version: str) -> bool:
    return bool(
        re.search(
            rf"^##\s+\[?{re.escape(version)}\]?\s+-\s+\d{{4}}-\d{{2}}-\d{{2}}\s*$",
            text,
            re.MULTILINE,
        )
    )


def update_changelog(version: str, date: str, notes: str) -> None:
    text = CHANGELOG.read_text(encoding="utf-8")
    prefix, _unreleased, suffix = split_unreleased(text)
    section = f"## [{version}] - {date}\n\n{notes.strip()}"

    rebuilt = f"{prefix}\n\n## [Unreleased]\n\n{section}"
    if suffix:
        rebuilt += f"\n\n{suffix.rstrip()}"

    CHANGELOG.write_text(rebuilt.rstrip() + "\n", encoding="utf-8")


def replace_once(
    path: pathlib.Path,
    pattern: str,
    replacement: str,
    flags: int = 0,
) -> None:
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(
            f"could not update expected release metadata in {path.relative_to(ROOT)}"
        )
    path.write_text(updated, encoding="utf-8")


def update_metadata(version: str) -> None:
    replace_once(
        MANIFEST,
        r'(\.version\s*=\s*")[^"]+(")',
        rf"\g<1>{version}\g<2>",
    )

    readme = README.read_text(encoding="utf-8")
    status_pattern = re.compile(
        r"> \*\*(?:Status|Release):\*\*.*?(?=\n\n## Highlights)",
        re.DOTALL,
    )
    tick = chr(96)
    status = (
        f"> **Release:** {tick}v{version}{tick}. Semantic versioning applies "
        "to the documented public API."
    )
    readme, count = status_pattern.subn(status, readme, count=1)
    if count != 1:
        raise SystemExit("could not update README release status")

    readme, count = re.subn(
        r"\[version-badge\]:\s+https://img\.shields\.io/badge/version-[^-\s]+-555\.svg",
        f"[version-badge]: https://img.shields.io/badge/version-{version}-555.svg",
        readme,
        count=1,
    )
    if count != 1:
        raise SystemExit("could not update README version badge")
    README.write_text(readme, encoding="utf-8")

    replace_once(
        DISTRIBUTION,
        r"\| Version \| \x60[^\x60]+\x60(?: release candidate)? \|",
        f"| Version | {tick}{version}{tick} |",
    )


def write_outputs(
    path: pathlib.Path | None,
    *,
    changed: bool,
    version: str = "",
) -> None:
    if path is None:
        return

    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"changed={'true' if changed else 'false'}\n")
        if version:
            handle.write(f"version={version}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--version",
        help="explicit release version; required for the first stable release",
    )
    parser.add_argument(
        "--date",
        default=dt.date.today().isoformat(),
        help="release date in YYYY-MM-DD form",
    )
    parser.add_argument("--github-output", type=pathlib.Path)
    args = parser.parse_args()

    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date):
        raise SystemExit(f"invalid release date: {args.date!r}")

    tag = latest_stable_tag()
    current = parse_version(manifest_version())
    changelog = CHANGELOG.read_text(encoding="utf-8")

    if tag is None and args.version is None:
        print("initial stable release requires an explicit --version")
        write_outputs(args.github_output, changed=False)
        return

    if tag is not None:
        base = parse_version(tag.removeprefix("v"))

        if current > base and release_section_exists(
            changelog,
            format_version(current),
        ):
            print(
                f"release metadata for v{format_version(current)} "
                "is already prepared"
            )
            write_outputs(
                args.github_output,
                changed=False,
                version=format_version(current),
            )
            return

        commits = commits_since(tag)
        entries = [
            entry
            for commit in commits
            if (entry := parse_entry(commit)) is not None
        ]
        if not entries and args.version is None:
            print(f"no releasable changes since {tag}")
            write_outputs(args.github_output, changed=False)
            return

        target = (
            parse_version(args.version)
            if args.version
            else bump_version(base, entries)
        )
        notes = generated_notes(entries)
    else:
        target = parse_version(args.version)
        _prefix, unreleased, _suffix = split_unreleased(changelog)
        if not unreleased:
            raise SystemExit(
                "initial stable release requires curated Unreleased notes"
            )
        notes = unreleased

    version = format_version(target)
    if tag is not None and target <= parse_version(tag.removeprefix("v")):
        raise SystemExit(f"release version {version} must be newer than {tag}")

    update_changelog(version, args.date, notes)
    update_metadata(version)

    print(f"prepared Zymbol v{version}")
    write_outputs(args.github_output, changed=True, version=version)


if __name__ == "__main__":
    main()
