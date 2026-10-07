# v1 fuzz qualification

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

## Sustained v1 campaign

The release campaign is finite and reproducible:

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

It is not the release-completion criterion because its duration is undefined.

## Acceptance rule

Fuzz qualification is complete only when all of the following hold on the
release candidate:

1. `zig build fuzz` passes the complete checked-in corpus.
2. `zig build fuzz --fuzz=100M --summary all` completes without crash,
   panic, invariant failure, memory-safety failure, or unexpected error.
3. The final fuzzing report contains every Zymbol fuzz target.
4. Any failure found during the campaign is fixed and its reproducer is made
   durable in the corpus or a dedicated regression test.
5. The deterministic corpus replay is rerun after every accepted fix.
6. If production code exercised by a fuzz target changes after the successful
   campaign, that affected sustained campaign is rerun before v1 is tagged.

Coverage percentage is recorded as evidence but is not treated as a proof of
correctness or as a fixed pass threshold. A fuzz campaign complements, rather
than replaces, the ISO conformance, interoperability, portability, and
boundary-test gates.
