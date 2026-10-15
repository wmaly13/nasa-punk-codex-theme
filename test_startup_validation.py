#!/usr/bin/env python3
"""Isolated tests for the package's daily-launch integrity profile."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent
PS = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class StartupValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not PS.is_file():
            raise unittest.SkipTest("Windows PowerShell 5.1 is required")

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nasa-start-validation-")
        self.root = Path(self.temp.name) / "fixture"
        self.files = self.root / "files"
        entries = {
            "files/start-package.ps1": b"launch entry 01\n",
            "files/package-common.ps1": (ROOT / "package-common.ps1").read_bytes(),
            "files/manage-lone-star.ps1": (ROOT / "manage-lone-star.ps1").read_bytes(),
            "files/lone-star-adapter.mjs": b"adapter source\n",
            "files/.support/selected-runtime-hashes.json": b"runtime manifest\n",
            "files/.support/upstream/scripts/start-dream-skin.ps1": b"runtime code 01\n",
            "files/.support/CodexDreamSkin-Setup-v1.5.20.exe": b"setup bytes 01\n",
            "files/ChatGPT-NASA.exe": b"launcher bytes 01\n",
            "files/NASA-Punk-Theme.zip": b"theme zip bytes 01\n",
            "files/lone-star-theme/theme.json": b"theme json bytes 01\n",
            "files/lone-star-theme/theme.css": b"theme css bytes 01\n",
        }
        self.files.mkdir(parents=True)
        manifest_entries = []
        for relative, payload in entries.items():
            path = self.root / Path(relative)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
            manifest_entries.append({"path": relative, "bytes": len(payload), "sha256": digest(path)})
        manifest = {"schemaVersion": 1, "packageId": "NASA-PunkTheme", "files": manifest_entries}
        (self.files / "package-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        self.trace = Path(self.temp.name) / "hashed-paths.txt"
        start = self.files / "start-package.ps1"
        start.write_text(self._powershell_body("DailyLaunch"), encoding="utf-8-sig")
        # The manifest pins the real fixture entry point after writing it.
        manifest_entries[0]["bytes"] = start.stat().st_size
        manifest_entries[0]["sha256"] = digest(start)
        (self.files / "package-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        self.valid_manifest = json.loads(json.dumps(manifest))

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _powershell_body(self, profile: str) -> str:
        common = str(self.files / "package-common.ps1").replace("'", "''")
        root = str(self.root).replace("'", "''")
        trace = str(self.trace).replace("'", "''")
        return f"""$ErrorActionPreference='Stop'
. '{common}'
$script:RealGetFileHash=Get-Command Microsoft.PowerShell.Utility\Get-FileHash
function Get-FileHash {{
  param([string]$LiteralPath,[string]$Algorithm)
  [IO.File]::AppendAllText('{trace}', $LiteralPath + [Environment]::NewLine)
  & $script:RealGetFileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
}}
$null=Read-PackageManifest -PackageRoot '{root}' -Profile {profile}
Write-Output 'OK'
"""

    def run_script(self, script: Path, expected: int) -> subprocess.CompletedProcess[str]:
        returncode = subprocess.run(
            [str(PS), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-File", str(script)],
            text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=30,
        )
        self.assertEqual(returncode.returncode, expected, returncode.stdout + returncode.stderr)
        return returncode

    def test_daily_launch_hashes_code_and_theme_but_skips_payload_hashes(self) -> None:
        self.run_script(self.files / "start-package.ps1", 0)
        hashed = {Path(line).name for line in self.trace.read_text().splitlines()}
        self.assertIn("start-package.ps1", hashed)
        self.assertIn("manage-lone-star.ps1", hashed)
        self.assertIn("lone-star-adapter.mjs", hashed)
        self.assertIn("theme.css", hashed)
        self.assertNotIn("CodexDreamSkin-Setup-v1.5.20.exe", hashed)
        self.assertNotIn("NASA-Punk-Theme.zip", hashed)
        self.assertIn("start-dream-skin.ps1", hashed)

    def test_daily_launch_catches_changed_scripts_launcher_and_theme(self) -> None:
        cases = (
            "files/manage-lone-star.ps1",
            "files/ChatGPT-NASA.exe",
            "files/lone-star-theme/theme.css",
            "files/lone-star-adapter.mjs",
            "files/.support/upstream/scripts/start-dream-skin.ps1",
        )
        for relative in cases:
            with self.subTest(relative=relative):
                target = self.root / Path(relative)
                original = target.read_bytes()
                data = bytearray(original)
                data[0] ^= 1
                target.write_bytes(data)
                self.run_script(self.files / "start-package.ps1", 1)
                target.write_bytes(original)

    def test_full_profile_detects_changed_installer_but_daily_checks_metadata(self) -> None:
        installer = self.files / ".support/CodexDreamSkin-Setup-v1.5.20.exe"
        data = bytearray(installer.read_bytes())
        data[0] ^= 1
        installer.write_bytes(data)
        self.run_script(self.files / "start-package.ps1", 0)
        full = Path(self.temp.name) / "full-check.ps1"
        full.write_text(self._powershell_body("FullIntegrity"), encoding="utf-8-sig")
        self.run_script(full, 1)
        installer.write_bytes(data + b"x")
        self.run_script(self.files / "start-package.ps1", 1)

    def test_daily_profile_rejects_path_escape_missing_and_reparse_entries(self) -> None:
        manifest_path = self.files / "package-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["files"][0]["path"] = "files/../outside.txt"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.run_script(self.files / "start-package.ps1", 1)

        manifest_path.write_text(json.dumps(self.valid_manifest), encoding="utf-8")
        installer = self.files / ".support/CodexDreamSkin-Setup-v1.5.20.exe"
        installer_bytes = installer.read_bytes()
        installer.unlink()
        self.run_script(self.files / "start-package.ps1", 1)

        installer.write_bytes(installer_bytes)
        manifest_path.write_text(json.dumps(self.valid_manifest), encoding="utf-8")
        # A directory junction does not require symbolic-link privileges. Move
        # the fixture-owned runtime directory to a sibling, then link it back;
        # cleanup removes only this disposable fixture tree.
        upstream = self.files / ".support/upstream"
        external = self.root / "outside-runtime"
        upstream.rename(external)
        create_junction = Path(self.temp.name) / "junction.ps1"
        create_junction.write_text(
            "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '" +
            str(upstream).replace("'", "''") + "' -Target '" +
            str(external).replace("'", "''") + "' | Out-Null\n",
            encoding="utf-8-sig",
        )
        self.run_script(create_junction, 0)
        self.run_script(self.files / "start-package.ps1", 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
