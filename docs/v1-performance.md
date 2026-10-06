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


## Recorded v1 result

Release-environment measurements were recorded on WSL/Linux with Zig 0.17 in
ReleaseFast on 2026-10-06.

Baseline before optimization:

- QR v20 automatic-mask encode: 3.121 ms/op
- QR v20 fixed-mask encode: 0.343 ms/op
- QR v20 clean decode: 0.184 ms/op
- PNG v20 scale 4 render: 9.624 ms/op
- SVG v20 render: 0.150 ms/op
- Reed-Solomon 15-of-30 correction: 0.055 ms/op
- scale-4 reference PNG IDAT: 535 bytes versus 311 bytes for zlib level 9

The automatic-mask/fixed-mask ratio is expected to be large because automatic
selection must evaluate all eight ISO mask candidates. No conformance-sensitive
mask rewrite was accepted without evidence of an algorithmic improvement.

PNG profiling exposed two avoidable costs:

1. direct rendering compressed the same IDAT stream three times: once during
   public exact sizing, once internally for the IDAT length, and once for the
   actual output;
2. Adler-32 used two integer modulo operations per raw byte.

The accepted implementation streams IDAT compression once, backpatches the
length field, computes CRC over the completed chunk, and replaces the per-byte
Adler modulo operations with equivalent bounded subtraction.

After that change:

- PNG v20 scale 4 render: 3.390 ms/op
- combined automatic encode + PNG: 9.226 ms/op
- independent six-case PNG validation remained green
- scale-4 reference IDAT remained 535 bytes

This is a roughly 64.8% reduction in measured PNG render latency without
changing the compressed representation.

A standard PNG Up-filter experiment was also measured. It regressed the same
PNG render to 6.420 ms/op and enlarged the scale-4 IDAT from 535 to 742 bytes,
so it was rejected and reverted.

## Compression-size trade-off

QRz's deterministic allocation-free fixed-Huffman/LZ77 encoder is intentionally
smaller in implementation scope than a general-purpose dynamic-Huffman zlib
compressor. On the representative validation corpus QRz IDAT streams measured
between 110.5% and 172.0% of Python zlib level 9 before the rejected filter
experiment. The largest observed absolute difference in that corpus was
224 bytes for the scale-4 reference image (535 versus 311 bytes).

Implementing a full dynamic-Huffman compressor solely to recover those bytes
would add substantial code size, state, test surface, and maintenance burden to
a renderer whose current output is already valid, deterministic, dependency
free, allocation free, and small in absolute terms. That trade-off is
consciously rejected for v1.

Performance closure is therefore complete for v1: material measured hotspots
were investigated, the clear implementation inefficiency was fixed, a plausible
filtering alternative was measured and rejected, and no unsupported universal
performance claim is made.
