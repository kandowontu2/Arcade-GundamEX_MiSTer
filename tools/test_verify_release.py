#!/usr/bin/env python3
"""Release-name regressions; no FPGA rebuild or game ROMs required."""
# OpenAI Codex and kandowontu; SPDX-License-Identifier: GPL-3.0-or-later
import pathlib
import os
import subprocess
import tempfile
import unittest

from verify_release import CORE, MRA, MRA_TARGET, ROOT, deploy_rbf_name, release_rbf_name, verify_mra_metadata


class ReleaseNamingTests(unittest.TestCase):
    def check_names(self, *names: str) -> str:
        with tempfile.TemporaryDirectory() as folder:
            releases = pathlib.Path(folder)
            for name in names:
                (releases / name).touch()
            return release_rbf_name(releases)

    def test_dated_name_retains_core_prefix(self):
        name = self.check_names("Arcade-GundamEX_20261005.rbf")
        self.assertEqual(name, "Arcade-GundamEX_20261005.rbf")
        self.assertEqual(pathlib.Path(name).stem[:-9], CORE)

    def test_undated_name_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "YYYYMMDD"):
            self.check_names("Arcade-GundamEX.rbf")

    def test_install_name_matches_distribution(self):
        self.assertEqual(deploy_rbf_name("Arcade-GundamEX_20261030.rbf"), "GundamEX_20261030.rbf")

    def test_invalid_calendar_date_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check_names("Arcade-GundamEX_20260230.rbf")

    def test_short_date_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "YYYYMMDD"):
            self.check_names("Arcade-GundamEX_261005.rbf")

    def test_wrong_core_name_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "YYYYMMDD"):
            self.check_names("GundamEX_20261005.rbf")

    def test_stale_duplicate_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "exactly one"):
            self.check_names("Arcade-GundamEX_20261005.rbf", "Arcade-GundamEX.rbf")

    def test_missing_rbf_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "exactly one"):
            self.check_names("Mobile Suit Gundam EX Revue.mra")


class MraMetadataTests(unittest.TestCase):
    def test_both_mras_match_and_validate(self):
        source = (ROOT / "mra" / MRA).read_bytes()
        self.assertEqual(source, (ROOT / "releases" / MRA).read_bytes())
        verify_mra_metadata(source)

    def test_prefixed_and_distributed_binary_lookup(self):
        name = release_rbf_name(ROOT / "releases")
        # Main accepts both Arcade-<rbf> and <rbf>. Distribution strips Arcade-.
        for prefix, binary in (("Arcade-", name), ("", name.removeprefix("Arcade-"))):
            self.assertTrue(binary.startswith(prefix + MRA_TARGET + "_"))
        self.assertEqual(CORE, "Arcade-" + MRA_TARGET)

    def test_prefixed_mra_target_is_rejected(self):
        data = (ROOT / "mra" / MRA).read_bytes().replace(
            b"<rbf>GundamEX</rbf>", b"<rbf>Arcade-GundamEX</rbf>")
        with self.assertRaisesRegex(AssertionError, "omit Arcade-"):
            verify_mra_metadata(data)

    def test_missing_rotation_is_rejected(self):
        data = (ROOT / "mra" / MRA).read_bytes().replace(b"<rotation>horizontal</rotation>", b"")
        with self.assertRaisesRegex(AssertionError, "rotation"):
            verify_mra_metadata(data)

    def test_generic_attack_labels_are_rejected(self):
        data = (ROOT / "mra" / MRA).read_bytes().replace(
            b"Weak Attack,Medium Attack,Strong Attack,Throw", b"Attack 1,Attack 2,Attack 3,Attack 4")
        with self.assertRaisesRegex(AssertionError, "Control card"):
            verify_mra_metadata(data)

    def test_wrong_nvram_size_or_channel_is_rejected(self):
        data = (ROOT / "mra" / MRA).read_bytes()
        for replacement in (b'<nvram index="254" size="128" />', b'<nvram index="4" size="64" />', b''):
            with self.subTest(replacement=replacement), self.assertRaisesRegex(AssertionError, "NVRAM"):
                verify_mra_metadata(data.replace(b'<nvram index="4" size="128" />', replacement))


class CleanupTests(unittest.TestCase):
    def test_cleanup_is_anchored_to_project(self):
        script = (ROOT / "clean.bat").read_text()
        self.assertIn('pushd "%~dp0" || exit /b 1', script)
        self.assertIn("popd", script)
        for folder in ("db", "incremental_db", "output_files", "simulation", "greybox_tmp"):
            self.assertIn(f"rmdir /s /q {folder}", script)

    @unittest.skipUnless(os.name == "nt", "Windows batch execution test")
    def test_cleanup_keeps_source_release_and_callers_files(self):
        base = ROOT / "output_files"
        base.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="clean-fixture-", dir=base) as folder:
            fixture = pathlib.Path(folder).resolve()
            project, caller = fixture / "project", fixture / "caller"
            project.mkdir()
            caller.mkdir()
            # Only run destructive batch commands inside this newly created
            # isolated fixture, never against the real project or a broad path.
            self.assertTrue(project.resolve().is_relative_to(base.resolve()))
            (project / "clean.bat").write_bytes((ROOT / "clean.bat").read_bytes())
            for parent in (project / "db", project / "output_files", project / "rtl",
                           project / "releases", caller / "db"):
                parent.mkdir()
            for path in (project / "db" / "generated.tmp", project / "output_files" / "old.rbf",
                         project / "old.bak", project / "rtl" / "core.sv",
                         project / "releases" / "current.rbf", caller / "db" / "keep.txt"):
                path.write_text("fixture")
            result = subprocess.run(["cmd.exe", "/d", "/c", str(project / "clean.bat")],
                                    cwd=caller, input="\n", text=True, capture_output=True, timeout=15)
            self.assertFalse((project / "db").exists(), result.stdout + result.stderr)
            self.assertFalse((project / "output_files").exists())
            self.assertFalse((project / "old.bak").exists())
            self.assertTrue((project / "rtl" / "core.sv").exists())
            self.assertTrue((project / "releases" / "current.rbf").exists())
            self.assertTrue((caller / "db" / "keep.txt").exists())


if __name__ == "__main__":
    unittest.main()
