#!/usr/bin/env python3
from __future__ import annotations

import unittest

import check_api_docs as api


class ApiDocsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.docs = api.DOCS.read_text(encoding="utf-8")
        self.expected = api.snapshot_names(
            api.SNAPSHOT.read_text(encoding="utf-8"), "expected_core_api"
        )
        self.exports = api.documented_exports(self.docs, "zymbol-api")
        self.facade = api.ROOT / "src" / "zymbol.zig"

    def test_reference_covers_public_api_and_source_links(self) -> None:
        for marker, const_name, facade in (
            ("zymbol-api", "expected_core_api", self.facade),
            ("zymbol-render-api", "expected_render_api", api.ROOT / "src" / "render" / "root.zig"),
        ):
            exports = api.documented_exports(self.docs, marker)
            expected = api.snapshot_names(api.SNAPSHOT.read_text(), const_name)
            api.check(marker, expected, [name for name, _, _ in exports])
            api.check_sources(exports, facade)

    def test_missing_export_is_rejected(self) -> None:
        docs = self.docs.replace("| [`encodeText`]", "| encodeText", 1)
        names = [name for name, _, _ in api.documented_exports(docs, "zymbol-api")]
        with self.assertRaisesRegex(SystemExit, "missing: encodeText"):
            api.check("zymbol", self.expected, names)

    def test_duplicate_export_is_rejected(self) -> None:
        names = [name for name, _, _ in self.exports] + ["encodeText"]
        with self.assertRaisesRegex(SystemExit, "duplicate: encodeText"):
            api.check("zymbol", self.expected, names)

    def test_wrong_public_declaration_is_rejected(self) -> None:
        first, second = self.exports[:2]
        exports = [(first[0], second[1], first[2])]
        with self.assertRaisesRegex(SystemExit, "public declaration"):
            api.check_sources(exports, self.facade)

    def test_missing_definition_is_rejected(self) -> None:
        name, public_link, _ = self.exports[0]
        with self.assertRaisesRegex(SystemExit, "missing API source file"):
            api.check_sources([(name, public_link, "../../src/missing.zig#L1")], self.facade)


if __name__ == "__main__":
    unittest.main()
