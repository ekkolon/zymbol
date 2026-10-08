#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import shutil
import subprocess
import sys

import prepare_release

ROOT = pathlib.Path(__file__).resolve().parents[1]
RELEASE_FILES = (
    "CHANGELOG.md",
    "README.md",
    "docs/getting-started.md",
    "build.zig.zon",
    "docs/maintaining/distribution.md",
)


def run(
    *args: str,
    check: bool = True,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        check=check,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        text=True,
    )


def output(*args: str) -> str:
    return run(*args, capture=True).stdout.strip()


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"required command is not available: {name}")


def target_version(explicit: str | None) -> str:
    tag = prepare_release.latest_stable_tag()
    if tag is None:
        if explicit is None:
            raise SystemExit(
                "initial stable release requires --version, for example --version 1.0.0"
            )
        return prepare_release.format_version(
            prepare_release.parse_version(explicit)
        )

    base = prepare_release.parse_version(tag.removeprefix("v"))
    commits = prepare_release.commits_since(tag)
    entries = [
        entry
        for commit in commits
        if (entry := prepare_release.parse_entry(commit)) is not None
    ]

    if explicit is not None:
        target = prepare_release.parse_version(explicit)
    else:
        if not entries:
            raise SystemExit(f"no releasable changes since {tag}")
        target = prepare_release.bump_version(base, entries)

    if target <= base:
        raise SystemExit(
            f"release version {prepare_release.format_version(target)} "
            f"must be newer than {tag}"
        )

    return prepare_release.format_version(target)


def ensure_release_branch_absent(branch: str) -> None:
    local = run(
        "git",
        "show-ref",
        "--verify",
        "--quiet",
        f"refs/heads/{branch}",
        check=False,
    )
    if local.returncode == 0:
        raise SystemExit(f"local release branch already exists: {branch}")

    remote = run(
        "git",
        "ls-remote",
        "--exit-code",
        "--heads",
        "origin",
        branch,
        check=False,
        capture=True,
    )
    if remote.returncode == 0:
        raise SystemExit(f"remote release branch already exists: {branch}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="explicit semantic version")
    parser.add_argument(
        "--date",
        default=dt.date.today().isoformat(),
        help="release date in YYYY-MM-DD form",
    )
    args = parser.parse_args()

    for tool in ("git", "gpg", "gh"):
        require_tool(tool)

    if output("git", "branch", "--show-current") != "main":
        raise SystemExit("release preparation must start on main")

    if output("git", "status", "--porcelain"):
        raise SystemExit("working tree must be clean")

    run("git", "fetch", "--tags", "origin", "main:refs/remotes/origin/main")

    head = output("git", "rev-parse", "HEAD")
    origin_main = output("git", "rev-parse", "origin/main")
    if head != origin_main:
        raise SystemExit(
            "local main is not identical to origin/main; update it before releasing"
        )

    version = target_version(args.version)
    branch = f"release/v{version}"
    ensure_release_branch_absent(branch)

    run("git", "switch", "-c", branch)

    try:
        command = [
            sys.executable,
            "tools/prepare_release.py",
            "--version",
            version,
            "--date",
            args.date,
        ]
        run(*command)

        changed = set(
            filter(
                None,
                output("git", "diff", "--name-only").splitlines(),
            )
        )
        unexpected = changed.difference(RELEASE_FILES)
        if unexpected:
            raise SystemExit(
                "release preparation changed unexpected files: "
                + ", ".join(sorted(unexpected))
            )
        if not changed:
            raise SystemExit("release preparation produced no changes")

        run("git", "diff", "--check")
        run("git", "add", *RELEASE_FILES)
        run("git", "diff", "--cached", "--check")
        run(
            "git",
            "commit",
            "-S",
            "-m",
            f"release: prepare Zymbol v{version}",
        )
        run("git", "verify-commit", "HEAD")

        commit = output("git", "rev-parse", "HEAD")
        run("git", "push", "--set-upstream", "origin", branch)

        repository = output(
            "gh",
            "repo",
            "view",
            "--json",
            "nameWithOwner",
            "--jq",
            ".nameWithOwner",
        )
        verified = output(
            "gh",
            "api",
            f"repos/{repository}/commits/{commit}",
            "--jq",
            ".commit.verification.verified",
        )
        reason = output(
            "gh",
            "api",
            f"repos/{repository}/commits/{commit}",
            "--jq",
            ".commit.verification.reason",
        )
        if verified != "true" or reason != "valid":
            run("git", "push", "origin", "--delete", branch, check=False)
            raise SystemExit(
                "GitHub did not verify the signed release commit; "
                "the remote candidate branch was removed"
            )

        body = (
            f"Release candidate for Zymbol v{version}, prepared by "
            "Nelson Dominguez.\n\n"
            f"Source: `{head[:12]}`. Changelog and version metadata are "
            "part of the signed candidate commit."
        )
        result = run(
            "gh",
            "pr",
            "create",
            "--draft",
            "--head",
            branch,
            "--base",
            "main",
            "--title",
            f"release: Zymbol v{version}",
            "--body",
            body,
            capture=True,
        )

        print(result.stdout.strip())
        print(f"signed release commit: {commit}")
    except BaseException:
        print(
            f"release preparation stopped on {branch}; inspect or delete the "
            "local branch before retrying",
            file=sys.stderr,
        )
        raise


if __name__ == "__main__":
    main()
