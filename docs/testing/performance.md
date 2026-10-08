# Performance

This page explains the benchmarks and records the measurements used for the
first stable release. Results describe the tested workloads and environment.

## Run the benchmarks

From the repository root:

```sh
zig build benchmark
```

The benchmark programs always use `ReleaseFast`. Python 3 is needed only for
the PNG compression comparison.

| Benchmark | What it measures |
| --- | --- |
| QR v20, automatic mask | Encoding including selection among eight masks |
| QR v20, fixed mask | Encoding without automatic mask selection |
| QR v20 decode | Decoding an undamaged symbol |
| Segmentation | Planning numeric, alphanumeric and byte-only inputs at different lengths |
| Reed-Solomon | Correcting 15 errors in a block with 30 correction codewords |
| PNG | Rendering at scale 4 |
| SVG | Rendering a symbol as SVG |
| Encode + PNG | Automatic encoding, exact PNG sizing and rendering |
| PNG compression | IDAT sizes against Python zlib levels 6 and 9 on the same scanlines |

To run only the segmentation benchmark:

```sh
zig build benchmark-segments
```

Each timed Zig benchmark takes five samples and reports the median in
nanoseconds per operation, plus operations per second. Inputs and buffers are
prepared before timing unless the benchmark includes that work explicitly.

Byte-only inputs and nonnumeric alphanumeric inputs use linear planning paths
when they fit one character-count field. Mixed inputs still search segment
endpoints. Numeric runs inside alphanumeric text retain the optimal planner.

The reported working memory is the space required by caller-owned buffers.
It is not total process memory or peak stack use.

## Recorded measurements

The following baseline was recorded on WSL/Linux, with Zig 0.17 and
`ReleaseFast`, on 2026-10-06. It predates the PNG optimization below and later
planner and mask-scoring changes.

| Operation | Baseline |
| --- | ---: |
| QR v20 automatic-mask encode | 3.121 ms/op |
| QR v20 fixed-mask encode | 0.343 ms/op |
| QR v20 clean decode | 0.184 ms/op |
| PNG v20 scale 4 render | 9.624 ms/op |
| SVG v20 render | 0.150 ms/op |
| Reed-Solomon, 15 errors with 30 correction codewords | 0.055 ms/op |

Automatic encoding evaluates all eight masks. Its cost therefore includes
work absent from fixed-mask encoding. Changes to that work must preserve the
standard's selection rules.

### PNG changes

Profiling found repeated compression during PNG sizing and output, plus two
integer modulo operations per byte in Adler-32.

The direct renderer now compresses IDAT once, fills in the length afterward
and computes CRC over the finished chunk. Adler-32 uses equivalent bounded
subtraction. An explicit `requiredPngBytes` call still computes the exact size
separately from rendering.

| Operation after the change | Result |
| --- | ---: |
| PNG v20 scale 4 render | 3.390 ms/op |
| Automatic encode + PNG | 9.226 ms/op |

The measured PNG render time fell by about 64.8%. The six-case independent
PNG validator passed, and the reference IDAT remained 535 bytes.

An Up-filter experiment increased render time to 6.420 ms/op and enlarged the
same IDAT from 535 to 742 bytes. It was reverted.

### Compression size

On the representative validation corpus, Zymbol's IDAT size was 110.5%–172.0%
of Python zlib level 9. The largest absolute difference was 224 bytes for the
scale-4 reference image: 535 bytes from Zymbol versus 311 bytes from zlib.

Zymbol uses a fixed-Huffman/LZ77 compressor. A full dynamic-Huffman compressor
would add code and state to reduce these small images further. The v1 renderer
keeps the smaller implementation.

## Evaluate an optimization

1. Record a complete benchmark run on the same machine and compiler.
2. Compare automatic and fixed-mask encoding, then look for the dominant cost
   in encoding, decoding, correction and rendering.
3. Compare PNG sizes against zlib on identical scanlines.
4. Repeat measurements before accepting the change.
5. Check correctness, memory use, output size and portability alongside speed.
6. Rerun conformance, interoperability, portability, PNG/SVG validation and
   benchmarks for the affected code.

A repeated change of roughly 5% or more in median time is large enough to
investigate. Smaller changes can still be useful when they reduce memory or
output size, but timing noise alone does not justify extra complexity.

Published comparisons must name the workload, compiler, optimization mode and
machine. These historical results do not establish current timings on other
hardware. See [`benchmarks/`](../../benchmarks/) for the measured operations.
