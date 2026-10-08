#!/usr/bin/env python3
"""Check the published package contents and import it as a dependency."""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONSUMER = ROOT / "tests" / "consumer"
PACKAGE_ENTRIES = {
    "build.zig",
    "build.zig.zon",
    "src",
    "LICENSE",
    "LICENSE-MIT",
    "LICENSE-APACHE",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", default="zig")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="zymbol-package-layout-") as temp:
        root = pathlib.Path(temp)
        cache = root / "cache"
        fetched = subprocess.run(
            [args.zig, "fetch", "--global-cache-dir", str(cache), str(ROOT)],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        package = cache / "p" / fetched.stdout.strip()
        if not package.is_dir():
            raise SystemExit("zig fetch did not produce a cached package")

        actual = {entry.name for entry in package.iterdir()}
        if actual != PACKAGE_ENTRIES:
            raise SystemExit(
                f"unexpected package contents: missing={sorted(PACKAGE_ENTRIES - actual)}, "
                f"extra={sorted(actual - PACKAGE_ENTRIES)}"
            )

        consumer = root / "consumer"
        consumer.mkdir()
        shutil.copy2(CONSUMER / "build.zig", consumer / "build.zig")
        shutil.copytree(CONSUMER / "src", consumer / "src")

        manifest = (CONSUMER / "build.zig.zon").read_text(encoding="utf-8")
        old_path = '.path = "../.."'
        if manifest.count(old_path) != 1:
            raise SystemExit("consumer dependency path changed")
        manifest = manifest.replace(old_path, f'.path = "../cache/p/{package.name}"')
        (consumer / "build.zig.zon").write_text(manifest, encoding="utf-8")

        env = os.environ.copy()
        env["ZIG_GLOBAL_CACHE_DIR"] = str(cache)
        subprocess.run([args.zig, "build", "test"], cwd=consumer, env=env, check=True)

    print("package layout and consumer smoke passed")


if __name__ == "__main__":
    main()
