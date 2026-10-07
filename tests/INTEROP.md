# ZXing-cpp interoperability

Zymbol uses ZXing-cpp 3.1.1 as an independent implementation for a
bidirectional differential gate.

The test environment is reproducible:

- `uv.toml` pins the Astral uv release;
- `tests/interop_zxing.py` pins its managed Python runtime and
  `zxing-cpp==3.1.1` through PEP 723 metadata;
- the interoperability dependency is test-only and is not part of the Zymbol
  runtime package.

## Run the gate

Install the repository-required uv release if it is not already available:

```sh
curl -LsSf https://astral.sh/uv/0.12.23/install.sh | sh
uv --version
```

Then run:

```sh
zig build interop
```

If uv is installed at a non-standard path:

```sh
zig build interop -Duv=/path/to/uv
```

The campaign exercises both directions:

- Zymbol encoder to ZXing-cpp decoder;
- ZXing-cpp encoder to Zymbol decoder.

This gate is intentionally separate from the dependency-free `test` and
`qualify` steps. It provides independent interoperability evidence without
making ZXing-cpp or Python runtime dependencies of the library.
