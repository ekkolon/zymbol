#!/usr/bin/env python3
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

NS = "{http://www.w3.org/2000/svg}"

CASES = {
    "qr-default": {
        "side": 29,
        "quiet": 4,
        "background": "#FFFFFF",
        "modules": "#000000",
        "explicit": None,
    },
    "qr-transparent": {
        "side": 33,
        "quiet": 4,
        "background": None,
        "modules": "#000000",
        "explicit": None,
    },
    "qr-reversed": {
        "side": 33,
        "quiet": 4,
        "background": "#000000",
        "modules": "#FFFFFF",
        "explicit": None,
    },
    "qr-explicit": {
        "side": 45,
        "quiet": 6,
        "background": "#FFFFFF",
        "modules": "#000000",
        "explicit": 512,
    },
    "micro-default": {
        "side": 17,
        "quiet": 2,
        "background": "#FFFFFF",
        "modules": "#000000",
        "explicit": None,
    },
    "micro-custom": {
        "side": 23,
        "quiet": 3,
        "background": "#F0E6DC",
        "modules": "#0C2238",
        "explicit": 420,
    },
}

RUN_RE = re.compile(r"M(\d+) (\d+)H(\d+)V(\d+)H(\d+)Z")


def run_case(driver, name):
    env = os.environ.copy()
    env["QRZ_SVG_CASE"] = name
    return subprocess.run(
        [driver],
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout


def parse_runs(path_data):
    position = 0
    runs = []
    for match in RUN_RE.finditer(path_data):
        if match.start() != position:
            raise AssertionError(
                f"unexpected SVG path syntax near {path_data[position:match.start()]!r}"
            )
        left, top, right, bottom, close_left = map(int, match.groups())
        if close_left != left:
            raise AssertionError("path run does not close at its left edge")
        if right <= left or bottom != top + 1:
            raise AssertionError("path run is not a one-row module run")
        runs.append((left, top, right, bottom))
        position = match.end()
    if position != len(path_data):
        raise AssertionError(f"unexpected trailing path syntax {path_data[position:]!r}")
    return runs


def validate(driver, name, expected):
    text = run_case(driver, name)
    if not text.startswith("<svg "):
        raise AssertionError(f"{name}: missing SVG root prefix")
    if not text.endswith("</svg>"):
        raise AssertionError(f"{name}: missing SVG terminator")

    root = ET.fromstring(text)
    if root.tag != NS + "svg":
        raise AssertionError(f"{name}: wrong SVG namespace")

    if root.attrib.get("viewBox") != f"0 0 {expected['side']} {expected['side']}":
        raise AssertionError(f"{name}: incorrect viewBox")
    if root.attrib.get("preserveAspectRatio") != "xMidYMid meet":
        raise AssertionError(f"{name}: incorrect preserveAspectRatio")
    if root.attrib.get("shape-rendering") != "crispEdges":
        raise AssertionError(f"{name}: missing crispEdges")

    explicit = expected["explicit"]
    if explicit is None:
        if "width" in root.attrib or "height" in root.attrib:
            raise AssertionError(f"{name}: responsive SVG unexpectedly has intrinsic size")
    else:
        if root.attrib.get("width") != str(explicit):
            raise AssertionError(f"{name}: width mismatch")
        if root.attrib.get("height") != str(explicit):
            raise AssertionError(f"{name}: height mismatch")

    paths = list(root)
    if any(node.tag != NS + "path" for node in paths):
        raise AssertionError(f"{name}: unexpected non-path child")

    background = expected["background"]
    expected_count = 1 if background is None else 2
    if len(paths) != expected_count:
        raise AssertionError(f"{name}: expected {expected_count} paths, got {len(paths)}")

    module_path = paths[-1]
    if module_path.attrib.get("fill") != expected["modules"]:
        raise AssertionError(f"{name}: module color mismatch")

    if background is not None:
        bg = paths[0]
        if bg.attrib.get("fill") != background:
            raise AssertionError(f"{name}: background color mismatch")
        side = expected["side"]
        if bg.attrib.get("d") != f"M0 0H{side}V{side}H0Z":
            raise AssertionError(f"{name}: background does not cover the full viewBox")

    runs = parse_runs(module_path.attrib.get("d", ""))
    if not runs:
        raise AssertionError(f"{name}: empty module path")

    side = expected["side"]
    quiet = expected["quiet"]
    for left, top, right, bottom in runs:
        if not (quiet <= left < right <= side - quiet):
            raise AssertionError(f"{name}: module run crosses horizontal quiet zone")
        if not (quiet <= top < bottom <= side - quiet):
            raise AssertionError(f"{name}: module run crosses vertical quiet zone")

    first = runs[0]
    if first[0] != quiet or first[1] != quiet:
        raise AssertionError(
            f"{name}: top-left finder does not start at quiet-zone offset"
        )

    return len(text), len(runs)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: svg_validate.py <qrz-svg-driver>")

    driver = sys.argv[1]
    results = {}
    for name, expected in CASES.items():
        results[name] = validate(driver, name, expected)

    total_runs = sum(runs for _, runs in results.values())
    print(
        f"svg validation success: {len(results)} cases; "
        f"{total_runs} module runs parsed"
    )


if __name__ == "__main__":
    main()
