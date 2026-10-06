# v1 performance qualification

QRz v1 performance is qualified by measurement, not by a claim that every
possible optimization has been exhausted.

## Reproducible suite

Run from a clean checkout on the release machine:

```sh
zig build benchmark
```

The benchmark executables are always compiled with `ReleaseFast` regardless
of the surrounding build mode. Python 3 is used only for the PNG compression
comparison and is not part of the QRz runtime.

The suite reports CSV-like output for:

- QR v20 mixed-text encoding with automatic mask selection
- the same encode with a fixed mask, isolating automatic mask-selection cost
- clean QR v20 decoding
- Reed-Solomon correction at 15 errors with 30 EC codewords
- PNG rendering at scale 4
- SVG rendering
- end-to-end automatic QR encoding plus PNG sizing/rendering
- QRz PNG IDAT size versus Python zlib levels 6 and 9 on identical scanlines

Each timed Zig benchmark records five samples and reports the median
nanoseconds per operation and derived operations per second. Inputs and
caller-owned buffers are prepared outside the timed region unless the
benchmark name explicitly includes that work.

## Working memory

QRz core and low-level renderers do not allocate. The benchmark therefore
reports caller-owned working-set bytes for the buffers required by each
operation. This is not presented as total process RSS or stack high-water
usage.

## Closure rule

Performance closure requires all of the following:

1. Record a complete `zig build benchmark` run from the release environment.
2. Inspect the automatic-mask versus fixed-mask encode ratio.
3. Inspect encode, decode, RS correction, PNG, SVG, and combined encode+PNG
   costs for a material dominant stage.
4. Compare PNG IDAT sizes with zlib level 6 and level 9 on the same raw
   scanlines.
5. Investigate every material hotspot found by the suite.
6. Retain an optimization only when repeated measurements show a meaningful
   improvement without weakening correctness, portability, API clarity, or
   deterministic output.
7. Re-run conformance, interoperability, portability, PNG/SVG validation, and
   the benchmark suite after accepted performance changes.

A change of roughly 5% or more in repeated median timing is treated as
material for optimization decisions. Smaller changes are not used to justify
additional complexity unless they also reduce working memory or output size.

The v1 release makes no hardware-independent claim such as "fastest QR
library." Published performance statements must identify the tested workload,
compiler, optimization mode, and machine.
