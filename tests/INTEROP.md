# Independent interoperability gate

The bidirectional interoperability gate uses ZXing-cpp 3.1.1 through Astral
uv. The uv version is pinned in `uv.toml`; the script pins its managed Python
runtime and ZXing dependency in PEP 723 metadata.

Install the repository-required uv release if it is not already available:

```sh
curl -LsSf https://astral.sh/uv/0.12.23/install.sh | sh
uv --version
```

Run the differential campaign:

```sh
zig build interop
```

If uv is at a non-standard path:

```sh
zig build interop -Duv=/path/to/uv
```

The gate checks representative QR Code and Micro QR cases in both directions:

- Zymbol encoder -> ZXing-cpp decoder
- ZXing-cpp encoder -> Zymbol decoder

The dependency is test-only and the gate is not part of the default `test`
or `qualify` steps.
