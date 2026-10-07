# Security

## Supported versions

| Version | Support |
| --- | --- |
| `main` / pre-1.0 | Security fixes target `main` |
| Current stable 1.x | Supported after `v1.0.0` |
| Older release lines | Evaluated based on severity and practical impact |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability.

Use GitHub's private [Report a vulnerability][report] flow. Include enough
information to reproduce and assess the issue:

- the affected Zymbol version or commit;
- a minimal reproducer when practical;
- expected and observed behavior;
- the security impact and any known preconditions.

Public disclosure should wait until a fix or mitigation is available.

For the project's documented trust and API boundaries, see the
[ISO/IEC 18004:2024 conformance ledger][conformance] and
[v1 compatibility contract][contract].

[conformance]: docs/iso-18004-2024-conformance.md
[contract]: docs/v1-contract.md
[report]: https://github.com/ekkolon/zymbol/security/advisories/new
