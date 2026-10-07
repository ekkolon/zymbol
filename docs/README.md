# Documentation

Zymbol keeps the README short enough to answer the first questions a user has,
then moves detailed contracts and qualification evidence into focused
documents.

## Using Zymbol

| Document | Read this when you need |
| --- | --- |
| [API reference](api.md) | Exact public functions, options, return types, and buffer requirements |
| [v1 compatibility contract](v1-contract.md) | The supported v1 surface, boundaries, and stability rules |
| [Distribution](distribution.md) | Package installation, source provenance, and release mechanics |
| [Changelog](../CHANGELOG.md) | User-visible changes between releases |

## Correctness and assurance

| Document | Purpose |
| --- | --- |
| [ISO/IEC 18004:2024 conformance](iso-18004-2024-conformance.md) | Normative claim boundary and clause-level evidence |
| [Performance qualification](v1-performance.md) | Benchmark method, measurements, and accepted trade-offs |
| [Fuzz qualification](v1-fuzz.md) | Durable regression corpus and sustained-fuzz policy |
| [ZXing interoperability](../tests/INTEROP.md) | Reproducible bidirectional differential testing |
| [Fixture provenance](../tests/reference/README.md) | Origins and role of external conformance data |

## Maintaining Zymbol

| Document | Purpose |
| --- | --- |
| [Release checklist](v1-release-checklist.md) | Exact qualification and publication sequence |
| [Contributing](../CONTRIBUTING.md) | Change requirements and local validation |
| [Security](../SECURITY.md) | Supported versions and private vulnerability reporting |

The repository README remains the canonical entry point for new users. These
documents provide the detail needed to evaluate, integrate, maintain, or audit
the library without turning the front page into an API manual.
