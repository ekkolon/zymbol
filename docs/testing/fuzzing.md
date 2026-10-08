# Fuzzing

Use Zig 0.17.0, the same compiler used to build and test Zymbol.

## Replay the checked-in inputs

From the repository root, run:

```sh
zig build fuzz
```

Without `--fuzz`, Zig runs the checked-in inputs once in a repeatable order.
This replay is part of the normal test and release checks.

The seed files include binary extremes, ASCII, alternating bits and structured
byte sequences. Inputs that uncover bugs become part of this corpus or a
separate regression test.

## Run a longer test

For a finite run:

```sh
zig build fuzz --fuzz=100M --summary all
```

The limit applies to each fuzz test. There are 14 targets, so this requests
100 million executions per target, about 1.4 billion across the suite.

For an open-ended run:

```sh
zig build fuzz --fuzz
```

Keep `.zig-cache` between runs. Zig stores discovered inputs and the current
crashing input there, allowing a campaign to continue building on earlier
coverage. Copy any failing input out before clearing the cache.

## What is tested

| Area | Targets |
| --- | --- |
| QR decoding | Arbitrary grids and malformed or truncated raw data streams |
| QR encoding | Binary round trips; FNC1, Structured Append and other controls |
| Micro QR | Arbitrary grids, byte round trips and valid M1–M4 mode/error-correction combinations |
| Family dispatch | Invalid `decodeAny` dimensions and short caller buffers |
| BCH | Format and version recovery within the specified correction limits |
| Reed-Solomon | Correction within the guaranteed limit and arbitrary blocks |
| Rendering | PNG payloads and options, SVG output and short output buffers |

See the targets in [`tests/`](../../tests/) for the assertions and input formats.

## Handle a failure

1. Save the failing input and the command used to reproduce it.
2. Reduce the input when practical.
3. Add it to the checked-in corpus or a regression test.
4. Fix the bug, then rerun the corpus and tests for the affected behavior.

Every release must pass the checked-in corpus. Longer fuzz campaigns run
alongside release work; completing the 100M run is not required to publish.
A bug found after publication follows the same regression process and belongs
in the appropriate patch release.

Coverage helps identify untested paths. There is no fixed coverage percentage
that proves the implementation correct. Fuzzing works alongside the
[conformance tests](conformance.md) and
[interoperability tests](interoperability.md).
