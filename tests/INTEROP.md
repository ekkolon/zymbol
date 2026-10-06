# Independent interoperability gate

The bidirectional interoperability gate uses the Python bindings for
ZXing-cpp 3.1.1 as an external implementation.

Install the pinned test dependency:

```sh
python3 -m pip install -r tests/interop-requirements.txt
```

Run the differential campaign:

```sh
zig build interop
```

If the Python executable is named differently:

```sh
zig build interop -Dpython=python
```

The gate currently checks a representative QR Code Model 2 and Micro QR
corpus in both directions:

- QRz encoder -> ZXing-cpp decoder
- ZXing-cpp encoder -> QRz decoder

The dependency is intentionally test-only and the gate is not part of the
default `test` or `qualify` steps. Release qualification records the
external decoder version used for the final campaign.
