#!/usr/bin/env python3
from __future__ import annotations

import re
import sys

ALLOWED = (
    "feat",
    "fix",
    "perf",
    "refactor",
    "revert",
    "security",
    "docs",
    "test",
    "build",
    "ci",
    "chore",
    "release",
)

PATTERN = re.compile(
    rf"^({'|'.join(ALLOWED)})(?:\([^)]+\))?!?:\s+\S.+$"
)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_pr_title.py <title>")

    title = sys.argv[1].strip()
    if not PATTERN.fullmatch(title):
        allowed = ", ".join(ALLOWED)
        raise SystemExit(
            "pull request title must use a conventional prefix "
            f"({allowed}); got: {title!r}"
        )

    print(f"pull request title valid: {title}")


if __name__ == "__main__":
    main()
