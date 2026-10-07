#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONSUMER = ROOT / "tests" / "consumer"

MANIFEST = """.{
    .name = .zymbol_remote_smoke,
    .version = "0.0.0",
    .fingerprint = 0x627f658731415927,
    .minimum_zig_version = "0.17.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
"""


def run(command: list[str], cwd: pathlib.Path) -> None:
    subprocess.run(command, cwd=cwd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("url", help="versioned Zymbol source archive URL")
    parser.add_argument("--zig", default="zig")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="zymbol-package-smoke-") as temp:
        root = pathlib.Path(temp)
        (root / "src").mkdir()
        shutil.copy2(CONSUMER / "build.zig", root / "build.zig")
        shutil.copy2(CONSUMER / "src" / "main.zig", root / "src" / "main.zig")
        (root / "build.zig.zon").write_text(MANIFEST, encoding="utf-8")

        run([args.zig, "fetch", "--save", args.url], root)
        run([args.zig, "build", "test"], root)

    print("remote package smoke passed")


if __name__ == "__main__":
    main()
