# Interoperability

These tests exchange QR and Micro QR symbols with ZXing-cpp 3.1.1 in both
directions:

- Zymbol encodes; ZXing-cpp decodes.
- ZXing-cpp encodes; Zymbol decodes.

This checks that another implementation can read Zymbol's output and that
Zymbol can read its output.

## Set up the test environment

Install the uv version pinned in [`uv.toml`](../../uv.toml):

```sh
curl -LsSf https://astral.sh/uv/0.12.23/install.sh | sh
uv --version
```

[`interop_zxing.py`](../../tests/interop_zxing.py) pins the managed Python
runtime, `zxing-cpp==3.1.1` and the dependency upload cutoff. uv handles that
environment; these packages are only used by the tests.

## Run the tests

From the repository root:

```sh
zig build interop
```

If uv is installed elsewhere:

```sh
zig build interop -Duv=/path/to/uv
```

The recorded conformance run contains ten cases in each direction across QR
and Micro QR. See [ISO conformance](conformance.md) for the wider set of checks.

`test` and `qualify` run without this Python environment. Run `interop`
separately when checking encoding, decoding or rendering changes.
