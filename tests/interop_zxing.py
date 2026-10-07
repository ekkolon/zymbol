#!/usr/bin/env python3
import os
import subprocess
import sys

try:
    import zxingcpp
except ImportError as exc:
    raise SystemExit(
        "missing zxing-cpp 3.1.1; install tests/interop-requirements.txt"
    ) from exc


def run_driver(driver, mode, **values):
    env = os.environ.copy()
    env["ZYMBOL_INTEROP_MODE"] = mode
    for key, value in values.items():
        env[f"ZYMBOL_INTEROP_{key.upper()}"] = str(value)
    return subprocess.run(
        [driver],
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def render_modules(modules, side, quiet_zone, scale=4):
    width = (side + quiet_zone * 2) * scale
    pixels = bytearray([255]) * (width * width)

    for y in range(side):
        for x in range(side):
            if modules[y * side + x] != "1":
                continue
            left = (x + quiet_zone) * scale
            top = (y + quiet_zone) * scale
            for dy in range(scale):
                row = (top + dy) * width + left
                pixels[row : row + scale] = b"\x00" * scale

    view = zxingcpp.ImageView(
        memoryview(pixels),
        width,
        width,
        zxingcpp.ImageFormat.Lum,
    )
    return pixels, view


def check_zymbol_to_zxing(driver):
    emitted = run_driver(driver, "emit").stdout.splitlines()
    checked = 0

    for line in emitted:
        family, payload, side_text, modules = line.split("\t")
        side = int(side_text)
        expected_format = (
            zxingcpp.BarcodeFormat.QRCode
            if family == "Q"
            else zxingcpp.BarcodeFormat.MicroQRCode
        )
        quiet_zone = 4 if family == "Q" else 2
        pixels, view = render_modules(modules, side, quiet_zone)
        result = zxingcpp.read_barcode(
            view,
            formats=[expected_format],
            try_rotate=False,
            try_downscale=False,
            try_invert=False,
            binarizer=zxingcpp.Binarizer.FixedThreshold,
            is_pure=True,
            return_errors=True,
        )
        if result is None:
            raise AssertionError(f"ZXing-cpp found no Zymbol vector for {payload!r}")
        if not result.valid:
            raise AssertionError(
                f"ZXing-cpp rejected Zymbol vector {payload!r}: "
                f"format={result.format!r}, error={result.error!r}, "
                f"text={result.text!r}"
            )
        if result.format != expected_format:
            raise AssertionError(
                f"wrong ZXing-cpp format for {payload!r}: {result.format}"
            )
        if bytes(result.bytes) != payload.encode("ascii"):
            raise AssertionError(
                f"ZXing-cpp payload mismatch for {payload!r}: {bytes(result.bytes)!r}"
            )
        checked += 1

    return checked


def external_cases():
    q = zxingcpp.BarcodeFormat.QRCode
    m = zxingcpp.BarcodeFormat.MicroQRCode
    return [
        ("Q", "HELLO WORLD", q, {"version": 1, "ec_level": "Q"}),
        ("Q", "QR Code Symbol", q, {"version": 1, "ec_level": "M"}),
        ("Q", "12345678901234567890", q, {"version": 1, "ec_level": "M"}),
        ("Q", "https://example.com/zymbol", q, {"version": 2, "ec_level": "M"}),
        ("Q", "QRZ VERSION 7 CONFORMANCE", q, {"version": 7, "ec_level": "Q"}),
        ("M", "12345", m, {"version": 1, "ec_level": "L"}),
        ("M", "01234567", m, {"version": 2, "ec_level": "L"}),
        ("M", "12345678901234567890123", m, {"version": 3, "ec_level": "L"}),
        ("M", "HELLO", m, {"version": 4, "ec_level": "L"}),
        ("M", "abc", m, {"version": 4, "ec_level": "L"}),
    ]


def check_zxing_to_qrz(driver):
    checked = 0

    for family, payload, barcode_format, options in external_cases():
        barcode = zxingcpp.create_barcode(payload, barcode_format, **options)
        image = barcode.to_image(scale=1, add_quiet_zones=False)
        height, width = image.shape
        if height != width:
            raise AssertionError(f"non-square QR-family image for {payload!r}")
        raw = bytes(memoryview(image))
        modules = "".join("1" if value < 128 else "0" for value in raw)
        run_driver(
            driver,
            "decode",
            family=family,
            payload=payload,
            side=width,
            modules=modules,
        )
        checked += 1

    return checked


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: interop_zxing.py <zymbol-interop-driver>")

    driver = sys.argv[1]
    forward = check_zymbol_to_zxing(driver)
    reverse = check_zxing_to_qrz(driver)
    print(
        f"interop success: {forward} Zymbol->ZXing-cpp, "
        f"{reverse} ZXing-cpp->Zymbol"
    )


if __name__ == "__main__":
    main()
