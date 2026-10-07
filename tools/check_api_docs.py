#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tests" / "public_api.zig"
DOCS = ROOT / "docs" / "api.md"


def snapshot_names(source: str, const_name: str) -> list[str]:
    pattern = re.compile(
        rf"const\s+{re.escape(const_name)}\s*=\s*\[_\]\[\]const u8\s*\{{(.*?)\n\}};",
        re.DOTALL,
    )
    match = pattern.search(source)
    if not match:
        raise SystemExit(f"cannot find {const_name} in tests/public_api.zig")
    return re.findall(r'"([^"]+)"', match.group(1))


def documented_names(source: str, marker: str) -> list[str]:
    fence = "\x60\x60\x60"
    pattern = re.compile(
        rf"<!-- {re.escape(marker)}:start -->\s*{fence}text\n(.*?)\n{fence}\s*<!-- {re.escape(marker)}:end -->",
        re.DOTALL,
    )
    match = pattern.search(source)
    if not match:
        raise SystemExit(f"cannot find {marker} export block in docs/api.md")
    return [line.strip() for line in match.group(1).splitlines() if line.strip()]


def check(label: str, expected: list[str], actual: list[str]) -> None:
    if expected == actual:
        return

    missing = [name for name in expected if name not in actual]
    extra = [name for name in actual if name not in expected]
    details = [f"{label} API documentation is out of sync"]
    if missing:
        details.append("missing: " + ", ".join(missing))
    if extra:
        details.append("extra: " + ", ".join(extra))
    if not missing and not extra:
        details.append("same names, different order")
    raise SystemExit("; ".join(details))


def main() -> None:
    snapshot = SNAPSHOT.read_text(encoding="utf-8")
    docs = DOCS.read_text(encoding="utf-8")

    check(
        "zymbol",
        snapshot_names(snapshot, "expected_core_api"),
        documented_names(docs, "zymbol-api"),
    )
    check(
        "zymbol.render",
        snapshot_names(snapshot, "expected_render_api"),
        documented_names(docs, "zymbol-render-api"),
    )

    print("API documentation matches the v1 export snapshot")


if __name__ == "__main__":
    main()
