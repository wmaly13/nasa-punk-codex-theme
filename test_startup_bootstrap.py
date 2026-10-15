#!/usr/bin/env python3
"""Regression test for the generated NASA startup theme-store bootstrap.

This runs only the real Initialize-DreamSkinThemeStore bootstrap expression
from the generated lifecycle script. All profile data lives in a temporary
fixture; no Codex process or Windows app package is queried or launched.
"""
from __future__ import annotations

import importlib.util
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent
UPSTREAM = BASE / ".support" / "upstream" / "Codex-Dream-Skin-1.5.20"
VERIFIED_NODE = BASE / ".support" / "verified-node.exe"
THEME_IMAGE = ROOT / "background.png"
POWERSHELL = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"

OLD_BOOTSTRAP = (
    "$themePaths = Initialize-DreamSkinThemeStore -SkillRoot "
    "(Split-Path -Parent $PSScriptRoot) -StateRoot $StateRoot"
)


def generated_start_script() -> str:
    spec = importlib.util.spec_from_file_location("nasa_build_module", ROOT / "build.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load the package builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.nasa_session_script(UPSTREAM, "start-dream-skin.ps1")


def bootstrap_from_generated_script() -> str:
    text = generated_start_script()
    matches = re.findall(r"(?m)^\s*\$themePaths\s*=\s*Initialize-DreamSkinThemeStore\b.*$", text)
    if len(matches) != 1:
        raise AssertionError(f"Expected one generated theme-store bootstrap, found {len(matches)}")
    return matches[0].strip()


class StartupBootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not POWERSHELL.is_file():
            raise unittest.SkipTest("Windows PowerShell 5.1 is required")
        if not UPSTREAM.is_dir():
            raise unittest.SkipTest(f"Pinned upstream runtime is missing: {UPSTREAM}")
        if not VERIFIED_NODE.is_file():
            raise unittest.SkipTest(f"Verified Node runtime is missing: {VERIFIED_NODE}")
        if not THEME_IMAGE.is_file():
            raise unittest.SkipTest(f"NASA fixture image is missing: {THEME_IMAGE}")

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nasa-startup-bootstrap-")
        self.root = Path(self.temp.name)
        self.local = self.root / "local"
        self.codex_home = self.root / "codex-home"
        self.local.mkdir()
        self.codex_home.mkdir()
        self.engine = self.local / "CodexDreamSkin" / "engine"
        self.private_windows = self.root / "package" / "files" / ".support" / "upstream" / "Codex-Dream-Skin-1.5.20" / "windows"
        self.private_scripts = self.private_windows / "scripts"
        self.private_scripts.mkdir(parents=True)
        self.engine.mkdir(parents=True)

        # Keep the real source helpers in both trees. The generated startup
        # script is housed beside the private helpers, matching the package.
        shutil.copytree(UPSTREAM / "windows" / "scripts", self.private_scripts, dirs_exist_ok=True)

        self.private_assets = self.private_windows / "assets"
        self.engine_assets = self.engine / "assets"
        self.private_assets.mkdir()
        self.engine_assets.mkdir()
        self._write_seed(self.private_assets, "missing-private-image.png")
        self._write_seed(self.engine_assets, "background.png")
        shutil.copy2(THEME_IMAGE, self.engine_assets / "background.png")

        self.bootstrap = bootstrap_from_generated_script()
        self.marker = self.root / "native-launch-marker.txt"
        self.harness = self.private_scripts / "bootstrap-fixture.ps1"

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _write_seed(directory: Path, image_name: str) -> None:
        theme = {
            "schemaVersion": 1,
            "id": "preset-fixture-seed",
            "name": "Fixture seed",
            "image": image_name,
            "appearance": "light",
            "art": {"focusX": 0.5, "focusY": 0.5, "safeArea": "auto", "taskMode": "ambient"},
        }
        (directory / "theme.json").write_text(json.dumps(theme), encoding="utf-8")

    def env(self) -> dict[str, str]:
        env = os.environ.copy()
        env.update({
            "LOCALAPPDATA": str(self.local),
            "CODEX_HOME": str(self.codex_home),
            "NASA_TEST_NODE": str(VERIFIED_NODE),
            "NASA_NATIVE_LAUNCH_MARKER": str(self.marker),
        })
        return env

    def run_bootstrap(self, expression: str, expected: int) -> subprocess.CompletedProcess[str]:
        self.marker.unlink(missing_ok=True)
        body = f"""$ErrorActionPreference = 'Stop'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
function Get-DreamSkinNodeRuntime {{
  param([int]$MinimumMajor = 22)
  return Get-DreamSkinValidatedNodeRuntime -Path $env:NASA_TEST_NODE -MinimumMajor $MinimumMajor
}}
$null = Get-DreamSkinNodeRuntime
{expression}
[IO.File]::WriteAllText($env:NASA_NATIVE_LAUNCH_MARKER, 'native launch would follow')
"""
        self.harness.write_text(body, encoding="utf-8-sig")
        result = subprocess.run(
            [str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-File", str(self.harness)],
            cwd=str(self.private_scripts), env=self.env(), text=True,
            encoding="utf-8", errors="replace", capture_output=True, timeout=90,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_old_private_tree_bootstrap_reproduces_image_error_and_fixed_bootstrap_uses_engine_seed(self) -> None:
        generated = generated_start_script()
        self.assertNotIn(OLD_BOOTSTRAP, generated)
        self.assertIn("Initialize-DreamSkinThemeStore -SkillRoot (Join-Path $StateRoot 'engine') -StateRoot $StateRoot", self.bootstrap)
        old = self.run_bootstrap(OLD_BOOTSTRAP, expected=1)
        self.assertIn("Theme image must remain inside its theme directory and exist.", old.stderr + old.stdout)
        self.assertFalse(self.marker.exists(), "failed initialization must stop before the native-launch boundary")

        fixed = self.run_bootstrap(self.bootstrap, expected=0)
        self.assertTrue(self.marker.exists(), "successful initialization should reach the native-launch boundary")
        active = self.local / "CodexDreamSkin" / "active-theme"
        self.assertTrue((active / "theme.json").is_file(), fixed.stdout + fixed.stderr)
        active_doc = json.loads((active / "theme.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(active_doc["id"], "preset-fixture-seed")
        self.assertTrue((active / "background.png").is_file())

    def test_active_edited_nasa_theme_is_preserved_by_generated_bootstrap(self) -> None:
        self.run_bootstrap(self.bootstrap, expected=0)
        active = self.local / "CodexDreamSkin" / "active-theme"
        (active / "theme.json").write_text(json.dumps({
            "schemaVersion": 1,
            "id": "nasa-punk-device-light",
            "name": "NASA edited fixture",
            "image": "nasa-active.png",
            "appearance": "light",
            "art": {"focusX": 0.6, "focusY": 0.4, "safeArea": "left", "taskMode": "ambient"},
        }), encoding="utf-8")
        shutil.copy2(THEME_IMAGE, active / "nasa-active.png")
        before = {item.name: item.read_bytes() for item in active.iterdir() if item.is_file()}

        self.run_bootstrap(self.bootstrap, expected=0)

        after = {item.name: item.read_bytes() for item in active.iterdir() if item.is_file()}
        self.assertEqual(after, before, "startup initialization must preserve an edited active NASA theme")

    def test_missing_installed_seed_art_fails_before_native_launch_marker(self) -> None:
        (self.engine_assets / "background.png").unlink()
        result = self.run_bootstrap(self.bootstrap, expected=1)
        self.assertIn("Theme image must remain inside its theme directory and exist.", result.stderr + result.stdout)
        self.assertFalse(self.marker.exists(), "missing engine art must fail before any native client launch")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--upstream", type=Path, default=UPSTREAM)
    parser.add_argument("--node", type=Path, default=VERIFIED_NODE)
    arguments, remaining = parser.parse_known_args()
    sys.argv = [sys.argv[0], *remaining]
    try:
        UPSTREAM = arguments.upstream.expanduser().resolve(strict=True)
        VERIFIED_NODE = arguments.node.expanduser().resolve(strict=True)
    except OSError as exc:
        raise SystemExit(f"Invalid --upstream or --node path: {exc}") from exc
    if not (UPSTREAM / "windows" / "scripts" / "start-dream-skin.ps1").is_file():
        raise SystemExit(f"--upstream must contain windows/scripts/start-dream-skin.ps1: {UPSTREAM}")
    version_path = UPSTREAM / "windows" / "VERSION"
    if not version_path.is_file() or version_path.read_text(encoding="utf-8-sig").strip() != "1.5.20":
        raise SystemExit(f"--upstream must be the pinned Codex Dream Skin 1.5.20 source: {UPSTREAM}")
    if not VERIFIED_NODE.is_file():
        raise SystemExit(f"--node must name a signed Node.js executable: {VERIFIED_NODE}")
    unittest.main(verbosity=2)
