#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleaseToolsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="zymbol-release-tools-")
        self.root = pathlib.Path(self.tempdir.name)
        (self.root / "tools").mkdir()
        (self.root / "docs").mkdir()

        for name in ("prepare_release.py", "release.py", "check_pr_title.py"):
            shutil.copy2(ROOT / "tools" / name, self.root / "tools" / name)

        (self.root / "build.zig.zon").write_text(
            '.{\n    .version = "0.1.0",\n}\n',
            encoding="utf-8",
        )
        (self.root / "README.md").write_text(
            """# zymbol

> **Status:** `0.1.0`, v1 release candidate. The public surface is frozen for
> the first stable release. Semantic-versioning guarantees begin with
> `v1.0.0`.

## Highlights

Test fixture.

[version-badge]: https://img.shields.io/badge/version-0.1.0-555.svg
""",
            encoding="utf-8",
        )
        (self.root / "docs" / "distribution.md").write_text(
            "| Version | `0.1.0` release candidate |\n",
            encoding="utf-8",
        )
        (self.root / "CHANGELOG.md").write_text(
            """# Changelog

All notable changes to Zymbol are documented here.

## [Unreleased]

### Added

- Initial stable feature set.

### Fixed

- Initial release fixes.

## [0.1.0]

Initial project baseline.
""",
            encoding="utf-8",
        )

        self.git("init")
        self.git("config", "user.name", "Zymbol Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "chore: baseline")

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_cmd(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            args,
            cwd=self.root,
            check=check,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return self.run_cmd("git", *args)

    def prepare(self, *args: str) -> subprocess.CompletedProcess[str]:
        return self.run_cmd(
            sys.executable,
            "tools/prepare_release.py",
            *args,
        )

    def commit_stable_v1(self) -> None:
        self.prepare("--version", "1.0.0", "--date", "2026-10-07")
        self.git("add", ".")
        self.git("commit", "-m", "release: Zymbol v1.0.0")
        self.git("tag", "v1.0.0")

    def test_initial_stable_release_uses_curated_unreleased_section(self) -> None:
        result = self.prepare(
            "--version",
            "1.0.0",
            "--date",
            "2026-10-07",
        )
        self.assertIn("prepared Zymbol v1.0.0", result.stdout)
        self.assertIn('.version = "1.0.0"', (self.root / "build.zig.zon").read_text())
        self.assertIn(
            "> **Release:** `v1.0.0`.",
            (self.root / "README.md").read_text(),
        )
        self.assertIn(
            "| Version | `1.0.0` |",
            (self.root / "docs" / "distribution.md").read_text(),
        )

        changelog = (self.root / "CHANGELOG.md").read_text()
        self.assertIn("## [Unreleased]", changelog)
        self.assertIn("## [1.0.0] - 2026-10-07", changelog)
        self.assertIn("### Added", changelog)
        self.assertIn("Initial stable feature set.", changelog)

    def test_feature_and_fix_generate_minor_release_notes(self) -> None:
        self.commit_stable_v1()

        path = self.root / "payload.txt"
        path.write_text("feature\n", encoding="utf-8")
        self.git("add", "payload.txt")
        self.git("commit", "-m", "feat: add structured payload helper (#101)")

        path.write_text("feature\nfix\n", encoding="utf-8")
        self.git("add", "payload.txt")
        self.git("commit", "-m", "fix: reject malformed payload earlier (#102)")

        (self.root / "docs.txt").write_text("docs\n", encoding="utf-8")
        self.git("add", "docs.txt")
        self.git("commit", "-m", "docs: clarify usage (#103)")

        output = self.root / "github-output"
        self.prepare(
            "--date",
            "2026-10-08",
            "--github-output",
            str(output),
        )

        self.assertEqual(
            output.read_text(encoding="utf-8"),
            "changed=true\nversion=1.1.0\n",
        )
        changelog = (self.root / "CHANGELOG.md").read_text()
        self.assertIn("## [1.1.0] - 2026-10-08", changelog)
        self.assertIn("### Added\n\n- Add structured payload helper (#101).", changelog)
        self.assertIn("### Fixed\n\n- Reject malformed payload earlier (#102).", changelog)
        self.assertNotIn("Clarify usage", changelog)

        notes = self.root / "notes.md"
        result = self.run_cmd(
            sys.executable,
            "tools/release.py",
            "v1.1.0",
            "--notes-out",
            str(notes),
        )
        self.assertIn("release metadata valid: Zymbol v1.1.0", result.stdout)
        self.assertNotIn("## [1.1.0]", notes.read_text())
        self.assertIn("### Added", notes.read_text())

    def test_docs_only_change_does_not_create_release(self) -> None:
        self.commit_stable_v1()

        (self.root / "docs.txt").write_text("docs\n", encoding="utf-8")
        self.git("add", "docs.txt")
        self.git("commit", "-m", "docs: clarify usage (#104)")

        output = self.root / "github-output"
        result = self.prepare(
            "--date",
            "2026-10-08",
            "--github-output",
            str(output),
        )

        self.assertIn("no releasable changes since v1.0.0", result.stdout)
        self.assertEqual(output.read_text(encoding="utf-8"), "changed=false\n")
        self.assertIn('.version = "1.0.0"', (self.root / "build.zig.zon").read_text())

    def test_fix_only_selects_patch_release(self) -> None:
        self.commit_stable_v1()

        (self.root / "fix.txt").write_text("fix\n", encoding="utf-8")
        self.git("add", "fix.txt")
        self.git("commit", "-m", "fix: harden malformed input handling (#106)")

        self.prepare("--date", "2026-10-08")
        self.assertIn('.version = "1.0.1"', (self.root / "build.zig.zon").read_text())
        self.assertIn(
            "## [1.0.1] - 2026-10-08",
            (self.root / "CHANGELOG.md").read_text(),
        )

    def test_breaking_change_selects_next_major(self) -> None:
        self.commit_stable_v1()

        (self.root / "api.txt").write_text("breaking\n", encoding="utf-8")
        self.git("add", "api.txt")
        self.git("commit", "-m", "feat!: replace public decoder contract (#105)")

        self.prepare("--date", "2026-10-08")
        self.assertIn('.version = "2.0.0"', (self.root / "build.zig.zon").read_text())
        self.assertIn(
            "**Breaking:** Replace public decoder contract (#105).",
            (self.root / "CHANGELOG.md").read_text(),
        )

    def test_release_validation_rejects_metadata_drift(self) -> None:
        self.prepare("--version", "1.0.0", "--date", "2026-10-07")

        readme = (self.root / "README.md").read_text(encoding="utf-8")
        (self.root / "README.md").write_text(
            readme.replace(
                "version-1.0.0-555.svg",
                "version-0.9.9-555.svg",
            ),
            encoding="utf-8",
        )

        result = self.run_cmd(
            sys.executable,
            "tools/release.py",
            "v1.0.0",
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("version badge does not match", result.stderr)

    def test_release_workflow_stages_tag_before_draft_publication(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(
            encoding="utf-8"
        )

        create_tag = workflow.index("- name: Create release tag")
        validate_archive = workflow.index("- name: Validate canonical tag archive")
        create_draft = workflow.index("- name: Create draft GitHub Release")
        cleanup = workflow.index("- name: Clean up failed release preparation")
        publish = workflow.index("- name: Publish immutable GitHub Release")
        verify_immutable = workflow.index("- name: Verify immutable release state")
        verify_attestation = workflow.index("- name: Verify GitHub release attestation")

        self.assertLess(create_tag, validate_archive)
        self.assertLess(validate_archive, create_draft)
        self.assertLess(create_draft, cleanup)
        self.assertLess(cleanup, publish)
        self.assertLess(publish, verify_immutable)
        self.assertLess(verify_immutable, verify_attestation)

        self.assertIn('ref="refs/tags/$RELEASE_TAG"', workflow)
        self.assertIn("--verify-tag", workflow)
        self.assertIn('RELEASE_TAG_CLEANUP=true', workflow)
        self.assertIn('RELEASE_DRAFT_CLEANUP=true', workflow)

        cleanup_block = workflow[cleanup:publish]
        self.assertIn('gh release delete "$RELEASE_TAG"', cleanup_block)
        self.assertIn(
            '"repos/$GITHUB_REPOSITORY/git/refs/tags/$RELEASE_TAG"',
            cleanup_block,
        )

    def test_pull_request_title_policy(self) -> None:
        valid = self.run_cmd(
            sys.executable,
            "tools/check_pr_title.py",
            "fix(decoder): reject malformed format data",
        )
        self.assertIn("pull request title valid", valid.stdout)

        invalid = self.run_cmd(
            sys.executable,
            "tools/check_pr_title.py",
            "Improve decoder",
            check=False,
        )
        self.assertNotEqual(invalid.returncode, 0)


if __name__ == "__main__":
    unittest.main()
