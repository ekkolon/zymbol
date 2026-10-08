#!/usr/bin/env python3
from __future__ import annotations

from collections import Counter
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "public_api.zig"
DOCS = ROOT / "docs" / "reference" / "api.md"


def snapshot_names(source: str, const_name: str) -> list[str]:
    pattern = re.compile(
        rf"const\s+{re.escape(const_name)}\s*=\s*\[_\]\[\]const u8\s*\{{(.*?)\n\}};",
        re.DOTALL,
    )
    match = pattern.search(source)
    if not match:
        raise SystemExit(f"cannot find {const_name} in tests/public_api.zig")
    return re.findall(r'"([^"]+)"', match.group(1))


def documented_exports(source: str, marker: str) -> list[tuple[str, str, str]]:
    match = re.search(
        rf"<!-- {re.escape(marker)}:start -->(.*?)<!-- {re.escape(marker)}:end -->",
        source,
        re.DOTALL,
    )
    if not match:
        raise SystemExit(f"cannot find {marker} tables in docs/reference/api.md")
    return re.findall(
        r"^\|\s+\[`(\w+)`\]\(([^)]+)\)\s+\|[^\n]*\|\s+\[[^\]]+\]\(([^)]+)\)\s+\|$",
        match.group(1),
        re.MULTILINE,
    )


def check(label: str, expected: list[str], actual: list[str]) -> None:
    counts = Counter(actual)
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    duplicate = sorted(name for name, count in counts.items() if count > 1)
    if not (missing or extra or duplicate):
        return

    details = [f"{label} API documentation is out of sync"]
    for title, names in (("missing", missing), ("extra", extra), ("duplicate", duplicate)):
        if names:
            details.append(title + ": " + ", ".join(names))
    raise SystemExit("; ".join(details))


def source_line(link: str) -> tuple[pathlib.Path, str]:
    match = re.fullmatch(r"(.+\.zig)#L([1-9]\d*)", link)
    if not match:
        raise SystemExit(f"invalid API source link: {link}")
    path = (DOCS.parent / match[1]).resolve()
    if not path.is_relative_to(ROOT / "src") or not path.is_file():
        raise SystemExit(f"missing API source file: {link}")
    lines = path.read_text(encoding="utf-8").splitlines()
    number = int(match[2])
    if number > len(lines):
        raise SystemExit(f"API source line does not exist: {link}")
    return path, lines[number - 1]


def check_sources(exports: list[tuple[str, str, str]], facade: pathlib.Path) -> None:
    for name, public_link, definition_link in exports:
        path, line = source_line(public_link)
        if path != facade or not re.match(rf"pub (?:const|fn) {re.escape(name)}\b", line):
            raise SystemExit(f"{name} link does not point to its public declaration")
        path, line = source_line(definition_link)
        if name == "render" and path == ROOT / "src" / "render" / "root.zig":
            continue
        if not re.match(r"pub (?:const|fn) ", line):
            raise SystemExit(f"{name} source link does not point to a definition")


def main() -> None:
    snapshot = SNAPSHOT.read_text(encoding="utf-8")
    docs = DOCS.read_text(encoding="utf-8")
    total = 0
    for label, const_name, marker, facade in (
        ("zymbol", "expected_core_api", "zymbol-api", ROOT / "src" / "zymbol.zig"),
        ("zymbol.render", "expected_render_api", "zymbol-render-api", ROOT / "src" / "render" / "root.zig"),
    ):
        exports = documented_exports(docs, marker)
        check(label, snapshot_names(snapshot, const_name), [name for name, _, _ in exports])
        check_sources(exports, facade)
        total += len(exports)
    print(f"API documentation covers all {total} exports and their source links")


if __name__ == "__main__":
    main()
