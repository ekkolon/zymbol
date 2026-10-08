#!/usr/bin/env python3
from __future__ import annotations

import os
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
        (self.root / "git-template").mkdir()
        self.env = os.environ.copy()
        self.env.update(
            {
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_TEMPLATE_DIR": str(self.root / "git-template"),
                "GIT_TERMINAL_PROMPT": "0",
            }
        )
        (self.root / "docs" / "maintaining").mkdir(parents=True)

        for name in (
            "prepare_release.py",
            "prepare_release_candidate.py",
            "release.py",
            "check_pr_title.py",
        ):
            shutil.copy2(ROOT / "tools" / name, self.root / "tools" / name)

        (self.root / "build.zig.zon").write_text(
            '.{\n    .version = "0.1.0",\n}\n',
            encoding="utf-8",
        )
        (self.root / "README.md").write_text(
            """# zymbol

Zymbol is a QR code library for Zig.

## Installation

```sh
zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v0.1.0.tar.gz
```

""",
            encoding="utf-8",
        )
        (self.root / "docs" / "getting-started.md").write_text(
            "zig fetch --save https://github.com/ekkolon/zymbol/archive/refs/tags/v0.1.0.tar.gz\n",
            encoding="utf-8",
        )
        (self.root / "docs" / "maintaining" / "distribution.md").write_text(
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
        try:
            result = subprocess.run(
                args,
                cwd=self.root,
                env=self.env,
                capture_output=True,
                text=True,
                errors="replace",
                timeout=30,
            )
        except subprocess.TimeoutExpired as exc:
            raise AssertionError(f"command timed out: {args!r}") from exc
        if check and result.returncode:
            raise AssertionError(
                f"command failed ({result.returncode}): {args!r}\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
        return result

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
        readme = (self.root / "README.md").read_text()
        self.assertIn("refs/tags/v1.0.0.tar.gz", readme)
        self.assertNotIn("refs/tags/v0.1.0.tar.gz", readme)
        self.assertIn("Zymbol is a QR code library for Zig.", readme)
        self.assertNotIn("**Release:**", readme)
        self.assertNotIn("## Highlights", readme)
        self.assertIn(
            "| Version | `1.0.0` |",
            (self.root / "docs" / "maintaining" / "distribution.md").read_text(),
        )
        self.assertIn(
            "refs/tags/v1.0.0.tar.gz",
            (self.root / "docs" / "getting-started.md").read_text(),
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

        readme = (self.root / "README.md").read_text()
        self.assertIn("refs/tags/v1.1.0.tar.gz", readme)
        self.assertNotIn("refs/tags/v1.0.0.tar.gz", readme)

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

    def test_js_only_commits_do_not_prepare_native_release(self) -> None:
        self.commit_stable_v1()

        subjects = (
            ("feat(js): add WebAssembly encoding", None),
            ("fix(js): validate byte buffers", None),
            ("feat(js)!: redesign JavaScript decode results", None),
            ("chore(js): update bridge ABI", "BREAKING CHANGE: JavaScript-only ABI update"),
        )
        for index, (subject, body) in enumerate(subjects):
            filename = f"js-change-{index}.txt"
            (self.root / filename).write_text(subject + "\n", encoding="utf-8")
            self.git("add", filename)
            args = ["commit", "-m", subject]
            if body is not None:
                args.extend(("-m", body))
            self.git(*args)

        output = self.root / "github-output"
        result = self.prepare("--date", "2026-10-08", "--github-output", str(output))
        self.assertIn("no releasable changes since v1.0.0", result.stdout)
        self.assertEqual("changed=false\n", output.read_text(encoding="utf-8"))
        self.assertIn('.version = "1.0.0"', (self.root / "build.zig.zon").read_text())

    def test_js_breaking_change_does_not_override_native_patch(self) -> None:
        self.commit_stable_v1()

        path = self.root / "payload.txt"
        path.write_text("fixed\n", encoding="utf-8")
        self.git("add", "payload.txt")
        self.git("commit", "-m", "fix(encoder): correct capacity check (#201)")

        path.write_text("fixed\njs\n", encoding="utf-8")
        self.git("add", "payload.txt")
        self.git(
            "commit",
            "-m",
            "feat(js)!: replace JavaScript public interface (#202)",
            "-m",
            "BREAKING CHANGE: JavaScript package API only",
        )

        self.prepare("--date", "2026-10-08")
        changelog = (self.root / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn("## [1.0.1] - 2026-10-08", changelog)
        self.assertIn("Correct capacity check (#201).", changelog)
        self.assertNotIn("JavaScript public interface", changelog)
        self.assertIn('.version = "1.0.1"', (self.root / "build.zig.zon").read_text())

        result = self.run_cmd(
            sys.executable,
            "-c",
            "import sys; sys.path.insert(0, 'tools'); "
            "import prepare_release_candidate as release; "
            "print(release.target_version(None))",
        )
        self.assertEqual("1.0.1", result.stdout.strip())

    def test_native_ci_excludes_package_only_changes(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(
            encoding="utf-8"
        )
        triggers = workflow.split("\npermissions:", 1)[0]
        self.assertNotIn('      - "**"', triggers)
        self.assertNotIn('      - "packages/qr/**"', triggers)
        for source_path in (
            "build.zig",
            "build.zig.zon",
            "src/**",
            "tests/**",
            "tools/**",
            ".github/workflows/ci.yml",
            "docs/reference/api.md",
        ):
            self.assertEqual(triggers.count(f'      - "{source_path}"'), 2)

    def test_release_validation_rejects_readme_version_drift(self) -> None:
        self.prepare("--version", "1.0.0", "--date", "2026-10-07")

        readme = (self.root / "README.md").read_text(encoding="utf-8")
        (self.root / "README.md").write_text(
            readme.replace(
                "refs/tags/v1.0.0.tar.gz",
                "refs/tags/v0.9.9.tar.gz",
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
        self.assertIn("README.md installation URL does not match", result.stderr)

    def test_release_validation_rejects_stale_getting_started_url(self) -> None:
        self.prepare("--version", "1.0.0", "--date", "2026-10-07")

        guide = self.root / "docs" / "getting-started.md"
        guide.write_text(
            guide.read_text().replace("v1.0.0.tar.gz", "v0.9.9.tar.gz"),
            encoding="utf-8",
        )
        result = self.run_cmd(
            sys.executable, "tools/release.py", "v1.0.0", check=False
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("getting-started.md installation URL does not match", result.stderr)

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
