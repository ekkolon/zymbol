# Fuzz qualification

Zymbol requires Zig 0.17.0. The same compiler baseline is used for ordinary
builds, tests, portability checks, release qualification, and sustained fuzzing.

## Targets

The v1 surface contains 14 fuzz targets covering:

- arbitrary QR module grids
- QR binary encode/decode round trips
- PNG option and payload rendering
- FNC1, Structured Append, and related control-mode round trips
- arbitrary Micro QR module grids
- Micro QR byte round trips
- explicit M1-M4 legal mode/EC combinations
- hostile decodeAny dimensions and caller buffers
- format/version BCH recovery within the advertised radius
- SVG serialization
- undersized renderer boundaries
- malformed/truncated raw QR data-stream parsing
- Reed-Solomon correction within the guaranteed radius
- arbitrary Reed-Solomon blocks

## Durable replay corpus

Each fuzz executable has a checked-in seed corpus containing binary extremes,
ASCII input, alternating bits, and a structured byte sequence.

Run:

```sh
zig build fuzz
```

Outside fuzz mode Zig executes the supplied corpus deterministically. This
command is therefore the permanent replay gate and is also part of normal test
and release qualification.

Zig's coverage fuzzer additionally persists discovered inputs and the current
crashing input in its build cache. Preserve `.zig-cache` during a campaign so
coverage and discovered inputs accumulate across runs. Cache state is useful
campaign evidence, but it is not the durable regression mechanism: every input
that exposes a Zymbol bug must be reduced as practical and promoted into the
checked-in corpus or a dedicated regression test.

## Sustained campaign

The sustained campaign is finite and reproducible:

```sh
zig build fuzz --fuzz=100M --summary all
```

Zig applies the limit to each fuzz test independently. With 14 Zymbol targets,
this requests 100 million executions per target, approximately 1.4 billion
fuzz executions across the suite.

The unlimited form remains useful for exploratory or overnight work:

```sh
zig build fuzz --fuzz
```

It is not used as a finite campaign record because its duration is undefined.

## Policy

The deterministic corpus replay is a release gate:

1. `zig build fuzz` must pass the complete checked-in corpus on every release
   candidate.
2. Any fuzz-discovered failure is reduced as practical and promoted into the
   checked-in corpus or a dedicated regression test.
3. The deterministic corpus is rerun after every accepted fix.

The 100M-per-target sustained campaign runs in parallel with publication. Its
completion is recorded as additional evidence rather than a prerequisite for
the initial tag. A defect found after publication is handled as a release
defect and fixed in the appropriate patch release.

Coverage percentage is evidence, not a proof of correctness or a fixed pass
threshold. Sustained fuzzing complements the ISO review, interoperability,
portability and boundary-test gates.
