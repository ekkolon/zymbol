#!/usr/bin/env python3
import os
import struct
import subprocess
import sys
import zlib

CASES = (
    "qr-default",
    "qr-scale4",
    "qr-transparent",
    "qr-reversed",
    "micro-default",
    "micro-custom",
)


def run_case(driver, case_name):
    env = os.environ.copy()
    env["QRZ_PNG_CASE"] = case_name
    return subprocess.run(
        [driver],
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout


def idat_stream(png):
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise AssertionError("invalid PNG signature")

    offset = 8
    parts = []
    while offset < len(png):
        length = struct.unpack(">I", png[offset : offset + 4])[0]
        kind = png[offset + 4 : offset + 8]
        payload = png[offset + 8 : offset + 8 + length]
        if kind == b"IDAT":
            parts.append(payload)
        offset += 12 + length
        if kind == b"IEND":
            break
    return b"".join(parts)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: png_compare.py <qrz-png-driver>")

    driver = sys.argv[1]
    print("png_case,qrz_zlib_bytes,zlib6_bytes,zlib9_bytes,qrz_vs_zlib9_pct")

    for case_name in CASES:
        png = run_case(driver, case_name)
        qrz_stream = idat_stream(png)
        raw = zlib.decompress(qrz_stream)
        z6 = zlib.compress(raw, level=6)
        z9 = zlib.compress(raw, level=9)
        ratio = (len(qrz_stream) / len(z9)) * 100.0
        print(
            f"{case_name},{len(qrz_stream)},{len(z6)},{len(z9)},{ratio:.1f}"
        )


if __name__ == "__main__":
    main()
