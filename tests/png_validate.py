#!/usr/bin/env python3
import binascii
import os
import struct
import subprocess
import sys
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

CASES = {
    "qr-default": {
        "width": 29,
        "height": 29,
        "quiet": 4,
        "scale": 1,
        "transparent": False,
        "reversed": False,
        "palette": bytes((0, 0, 0, 255, 255, 255)),
    },
    "qr-scale4": {
        "width": 164,
        "height": 164,
        "quiet": 4,
        "scale": 4,
        "transparent": False,
        "reversed": False,
        "palette": bytes((0, 0, 0, 255, 255, 255)),
    },
    "qr-transparent": {
        "width": 66,
        "height": 66,
        "quiet": 4,
        "scale": 2,
        "transparent": True,
        "reversed": False,
        "palette": bytes((0, 0, 0, 255, 255, 255)),
    },
    "qr-reversed": {
        "width": 66,
        "height": 66,
        "quiet": 4,
        "scale": 2,
        "transparent": False,
        "reversed": True,
        "palette": bytes((0, 0, 0, 255, 255, 255)),
    },
    "micro-default": {
        "width": 17,
        "height": 17,
        "quiet": 2,
        "scale": 1,
        "transparent": False,
        "reversed": False,
        "palette": bytes((0, 0, 0, 255, 255, 255)),
    },
    "micro-custom": {
        "width": 63,
        "height": 63,
        "quiet": 2,
        "scale": 3,
        "transparent": False,
        "reversed": False,
        "palette": bytes((12, 34, 56, 240, 230, 220)),
    },
}


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


def parse_png(data):
    if not data.startswith(PNG_SIGNATURE):
        raise AssertionError("invalid PNG signature")

    chunks = []
    offset = len(PNG_SIGNATURE)
    while offset < len(data):
        if offset + 12 > len(data):
            raise AssertionError("truncated PNG chunk")

        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        start = offset + 8
        end = start + length
        crc_end = end + 4
        if crc_end > len(data):
            raise AssertionError(f"truncated {chunk_type!r} chunk")

        payload = data[start:end]
        expected_crc = struct.unpack(">I", data[end:crc_end])[0]
        actual_crc = binascii.crc32(chunk_type + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise AssertionError(
                f"CRC mismatch for {chunk_type!r}: "
                f"{actual_crc:08x} != {expected_crc:08x}"
            )

        chunks.append((chunk_type, payload))
        offset = crc_end
        if chunk_type == b"IEND":
            break

    if offset != len(data):
        raise AssertionError("trailing bytes after IEND")
    return chunks


def defilter(raw, width, height):
    row_bytes = (width + 7) // 8
    stride = row_bytes + 1
    rows = []
    previous = bytes(row_bytes)

    for y in range(height):
        offset = y * stride
        filter_type = raw[offset]
        encoded = raw[offset + 1 : offset + stride]

        if filter_type == 0:
            row = bytes(encoded)
        elif filter_type == 2:
            row = bytes(
                (encoded[i] + previous[i]) & 0xFF
                for i in range(row_bytes)
            )
        else:
            raise AssertionError(
                f"unsupported PNG filter type {filter_type} at row {y}"
            )

        rows.append(row)
        previous = row

    return rows


def indexed_pixel(rows, x, y):
    byte = rows[y][x // 8]
    return (byte >> (7 - (x % 8))) & 1

def validate_case(driver, case_name, expected):
    png = run_case(driver, case_name)
    chunks = parse_png(png)

    by_type = {}
    idat_parts = []
    for chunk_type, payload in chunks:
        if chunk_type == b"IDAT":
            idat_parts.append(payload)
        else:
            by_type.setdefault(chunk_type, []).append(payload)

    if [kind for kind, _ in chunks][0] != b"IHDR":
        raise AssertionError("IHDR is not first")
    if [kind for kind, _ in chunks][-1] != b"IEND":
        raise AssertionError("IEND is not last")

    ihdr = by_type[b"IHDR"][0]
    width, height, depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", ihdr
    )
    if (width, height) != (expected["width"], expected["height"]):
        raise AssertionError(
            f"{case_name}: dimensions {(width, height)} != "
            f"{(expected['width'], expected['height'])}"
        )
    if (depth, color_type, compression, filtering, interlace) != (1, 3, 0, 0, 0):
        raise AssertionError(f"{case_name}: unexpected IHDR encoding fields")

    palette = by_type[b"PLTE"][0]
    if palette != expected["palette"]:
        raise AssertionError(f"{case_name}: palette mismatch")

    transparency = by_type.get(b"tRNS")
    if expected["transparent"]:
        if transparency != [bytes((255, 0))]:
            raise AssertionError(f"{case_name}: invalid tRNS")
    elif transparency is not None:
        raise AssertionError(f"{case_name}: unexpected tRNS")

    zstream = b"".join(idat_parts)
    if len(zstream) < 6:
        raise AssertionError(f"{case_name}: truncated zlib stream")
    if zstream[0] & 0x0F != 8 or ((zstream[0] << 8) | zstream[1]) % 31 != 0:
        raise AssertionError(f"{case_name}: invalid zlib header")
    if zstream[2] & 0x07 != 0x03:
        raise AssertionError(f"{case_name}: first DEFLATE block is not final/fixed-Huffman")

    raw = zlib.decompress(zstream)
    expected_adler = struct.unpack(">I", zstream[-4:])[0]
    actual_adler = zlib.adler32(raw) & 0xFFFFFFFF
    if actual_adler != expected_adler:
        raise AssertionError(
            f"{case_name}: Adler mismatch "
            f"{actual_adler:08x} != {expected_adler:08x}"
        )

    row_bytes = (width + 7) // 8
    expected_raw_len = height * (row_bytes + 1)
    if len(raw) != expected_raw_len:
        raise AssertionError(
            f"{case_name}: raw length {len(raw)} != {expected_raw_len}"
        )
    expected_scaled = expected["scale"] > 1
    for y in range(height):
        filter_type = raw[y * (row_bytes + 1)]
        expected_filter = 0 if (y == 0 or not expected_scaled) else 2
        if filter_type != expected_filter:
            raise AssertionError(
                f"{case_name}: filter {filter_type} at row {y}, "
                f"expected {expected_filter}"
            )

    rows = defilter(raw, width, height)
    quiet_index = indexed_pixel(rows, 0, 0)
    q = expected["quiet"] * expected["scale"]
    finder_index = indexed_pixel(rows, q, q)
    if expected["reversed"]:
        if (quiet_index, finder_index) != (0, 1):
            raise AssertionError(
                f"{case_name}: reversed polarity mismatch "
                f"{(quiet_index, finder_index)}"
            )
    else:
        if (quiet_index, finder_index) != (1, 0):
            raise AssertionError(
                f"{case_name}: normal polarity mismatch "
                f"{(quiet_index, finder_index)}"
            )

    stored_len = 2 + ((len(raw) + 65534) // 65535) * 5 + len(raw) + 4
    return len(png), len(zstream), stored_len


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: png_validate.py <qrz-png-driver>")

    driver = sys.argv[1]
    results = {}
    for case_name, expected in CASES.items():
        results[case_name] = validate_case(driver, case_name, expected)

    compressed = results["qr-scale4"][1]
    stored = results["qr-scale4"][2]
    if compressed >= stored * 3 // 4:
        raise AssertionError(
            f"production compression regression: {compressed} bytes vs "
            f"{stored} stored-DEFLATE bytes"
        )

    ratio = compressed / stored
    print(
        f"png validation success: {len(results)} cases; "
        f"scale4 zlib {compressed}/{stored} bytes ({ratio:.1%})"
    )


if __name__ == "__main__":
    main()
