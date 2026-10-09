#!/usr/bin/env python3
"""Release-name regressions; no FPGA rebuild or game ROMs required."""
# OpenAI Codex and kandowontu; SPDX-License-Identifier: GPL-3.0-or-later
import pathlib
import tempfile
import unittest

from verify_release import CORE, release_rbf_name


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


if __name__ == "__main__":
    unittest.main()
