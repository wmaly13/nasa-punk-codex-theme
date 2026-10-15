#!/usr/bin/env python3
"""Isolated regression checks for reusing a healthy NASA runtime session."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent
PS = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


BOUNDARIES = r"""
$script:scenario='healthy'
$script:browser='fixture-browser'
$script:port=9222
$script:injector=Join-Path $env:NASA_TEST_FILES '.support\upstream\Codex-Dream-Skin-1.5.20\windows\scripts\lone-star-runtime-api.mjs'
$script:adapter=Join-Path $env:NASA_TEST_FILES '.support\lone-star-adapter.mjs'
$script:nodePath=Join-Path (Join-Path $env:NASA_TEST_LOCAL 'CodexDreamSkin\engine') 'runtime\node\node.exe'
$script:injectorPid=4242
$script:expectedStart=[datetime]'2026-10-15T02:00:00.0000000Z'
$script:state=[pscustomobject]@{
  browserId=$script:browser;port=$script:port;injectorPath=$script:injector
  injectorPid=$script:injectorPid;injectorStartedAt=$script:expectedStart.ToUniversalTime().ToString('o')
  nodePath=$script:nodePath
}
$script:watcher=[pscustomobject]@{
  ProcessId=$script:injectorPid;ExecutablePath=$script:nodePath
  CommandLine=('"'+$script:nodePath+'" "'+$script:injector+'" --watch --port 9222 --browser-id fixture-browser')
}
$script:session=[pscustomobject]@{Port=$script:port;BrowserId=$script:browser;OwnerPid=3131;Codex=[pscustomobject]@{Executable='C:\fixture\ChatGPT.exe'}}
function Get-PackageLocations {
  return [pscustomobject]@{
    Program=$env:NASA_TEST_PROGRAM;State=$env:NASA_TEST_STATE
    Record=(Join-Path $env:NASA_TEST_STATE 'installation.json')
    Runtime=(Join-Path $env:NASA_TEST_LOCAL 'CodexDreamSkin')
    Engine=(Join-Path $env:NASA_TEST_LOCAL 'CodexDreamSkin\engine')
  }
}
function Read-DreamSkinState { param([string]$Path) return $script:state }
function Test-DreamSkinPathEqual { param([string]$Left,[string]$Right) return ([IO.Path]::GetFullPath($Left) -ieq [IO.Path]::GetFullPath($Right)) }
function Get-DreamSkinValidatedNodeRuntime { param([string]$Path) return [pscustomobject]@{Path=$script:nodePath} }
function Get-Process { [CmdletBinding()] param([int]$Id)
  $start=$script:expectedStart
  if ($script:scenario -eq 'foreign-starttime') { $start=$script:expectedStart.AddSeconds(-10) }
  return [pscustomobject]@{Id=$Id;HasExited=$false;StartTime=$start;Path=$script:nodePath}
}
function Get-DreamSkinProcessExecutablePath { param([object]$ProcessInfo) return $ProcessInfo.ExecutablePath }
function Test-DreamSkinCommandLineToken { param([string]$CommandLine,[string]$Token)
  if ($script:scenario -eq 'foreign-script' -and $Token -ceq $script:injector) { return $false }
  $pattern='(?:^|\s)"?'+[regex]::Escape($Token)+'"?(?:\s|$)'
  return ($CommandLine -match $pattern)
}
function Test-DreamSkinPaused { param([string]$StateRoot) return ($script:scenario -eq 'paused') }
function Get-CimInstance { [CmdletBinding()]
  param([string]$ClassName,[string]$Filter)
  if ($Filter -like 'ProcessId = *') {
    if ($script:scenario -eq 'foreign-pid') {
      $bad=$script:watcher.PSObject.Copy();$bad.ProcessId=$script:injectorPid+1;return $bad
    }
    if ($script:scenario -eq 'foreign-node') {
      $bad=$script:watcher.PSObject.Copy();$bad.ExecutablePath='D:\foreign\node.exe';return $bad
    }
    if ($script:scenario -eq 'foreign-script') {
      $bad=$script:watcher.PSObject.Copy();$bad.CommandLine=$bad.CommandLine.Replace($script:injector,'D:\foreign\runtime-api.mjs');return $bad
    }
    return $script:watcher
  }
  if ($script:scenario -eq 'legacy-doublewatcher') {
    return @($script:watcher,[pscustomobject]@{ProcessId=8787;CommandLine=('"C:\node.exe" "'+$script:adapter+'" watch')})
  }
  if ($script:scenario -eq 'duplicate-unified-watchers') {
    $second=$script:watcher.PSObject.Copy();$second.ProcessId=4343
    return @($script:watcher,$second)
  }
  return @($script:watcher)
}
function Invoke-DreamSkinNative {
  param([string]$FilePath,[string[]]$ArgumentList,[switch]$DiscardStderr)
  if ($script:scenario -eq 'health-failed') { return [pscustomobject]@{ExitCode=1;Output=@('{"pass":true,"browserId":"fixture-browser"}')} }
  if ($script:scenario -eq 'health-malformed') { return [pscustomobject]@{ExitCode=0;Output=@('not-json')} }
  if ($script:scenario -eq 'health-browser-mismatch') { return [pscustomobject]@{ExitCode=0;Output=@('{"pass":true,"browserId":"other-browser"}')} }
  return [pscustomobject]@{ExitCode=0;Output=@('{"pass":true,"browserId":"fixture-browser"}')}
}
"""


class StartupReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not PS.is_file():
            raise unittest.SkipTest("Windows PowerShell 5.1 is required")

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nasa-start-reuse-")
        self.root = Path(self.temp.name)
        self.files = self.root / "package" / "files"
        self.files.mkdir(parents=True)
        (self.files / ".support/upstream/Codex-Dream-Skin-1.5.20/windows/scripts").mkdir(parents=True)
        (self.files / ".support/upstream/Codex-Dream-Skin-1.5.20/windows/scripts/lone-star-runtime-api.mjs").write_text("// fixture\n", encoding="utf-8")
        (self.files / ".support/lone-star-adapter.mjs").write_text("// fixture\n", encoding="utf-8")
        self.local = self.root / "profile/AppData/Local"
        self.state_root = self.local / "NASA-PunkTheme"
        self.state_root.mkdir(parents=True, exist_ok=True)
        self.temp_env = self.root / "profile/temp"
        self.temp_env.mkdir(parents=True)
        self.env = os.environ.copy()
        self.env.update({
            "NASA_TEST_FILES": str(self.files),
            "NASA_TEST_PROGRAM": str(self.root / "package"),
            "NASA_TEST_STATE": str(self.state_root),
            "NASA_TEST_LOCAL": str(self.local),
            "LOCALAPPDATA": str(self.local),
            "USERPROFILE": str(self.root / "profile"),
            "TEMP": str(self.temp_env), "TMP": str(self.temp_env),
        })
        (self.local / "CodexDreamSkin").mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_ps(self, script: Path, expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [str(PS), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-File", str(script)],
            cwd=str(self.root), env=self.env, text=True, encoding="utf-8", errors="replace", timeout=45, capture_output=True,
        )
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_unified_runtime_helper_rejects_stale_or_foreign_identity_and_unhealthy_payload(self) -> None:
        common = ROOT / "package-common.ps1"
        harness = self.root / "helper-check.ps1"
        code = f"""$ErrorActionPreference='Stop'
. '{str(common).replace("'", "''")}'
{BOUNDARIES}
$session=$script:session
$cases=@(
  @{{name='healthy';expected=$true}},
  @{{name='stale-browser';expected=$false}},
  @{{name='foreign-pid';expected=$false}},
  @{{name='foreign-node';expected=$false}},
  @{{name='foreign-script';expected=$false}},
  @{{name='foreign-starttime';expected=$false}},
  @{{name='paused';expected=$false}},
  @{{name='legacy-doublewatcher';expected=$false}},
  @{{name='duplicate-unified-watchers';expected=$false}},
  @{{name='health-failed';expected=$false}},
  @{{name='health-malformed';expected=$false}},
  @{{name='health-browser-mismatch';expected=$false}}
)
foreach ($case in $cases) {{
  $script:scenario=$case.name
  $script:state.browserId=if ($case.name -eq 'stale-browser') {{ 'old-browser' }} else {{ $script:browser }}
  $script:state.nodePath=$script:nodePath
  $script:state.injectorStartedAt=if ($case.name -eq 'foreign-starttime') {{ $script:expectedStart.AddSeconds(-20).ToUniversalTime().ToString('o') }} else {{ $script:expectedStart.ToUniversalTime().ToString('o') }}
  $result=Get-PackageUnifiedRuntimeHealth -FilesRoot $env:NASA_TEST_FILES -Session $session
  if ([bool]$result -ne [bool]$case.expected) {{ throw "case $($case.name): expected $($case.expected), received $result" }}
}}
Write-Output 'helper cases passed'
"""
        harness.write_text(code, encoding="utf-8-sig")
        result = self.run_ps(harness)
        self.assertIn("helper cases passed", result.stdout)

    def test_healthy_actual_start_entry_reuses_session_without_manager_or_baseline_mutation(self) -> None:
        package_root = self.root / "package"
        start = self.files / "start-package.ps1"
        common = self.files / "package-common.ps1"
        shutil.copy2(ROOT / "start-package.ps1", start)
        common.write_text((ROOT / "package-common.ps1").read_text(encoding="utf-8") + "\n" + BOUNDARIES + r"""
function Import-PackageEngineHelpers { param([string]$FilesRoot) }
function Assert-PackageWorkerIdle { param([string]$FilesRoot) }
function Get-PackageLaunchSession { return $script:session }
function Show-PackageVerifiedWindow { param([object]$Session)
  [IO.File]::WriteAllText((Join-Path $env:NASA_TEST_ROOT 'focused.txt'),'yes')
  return $true
}
function Invoke-PackageManager { param([string]$FilesRoot,[string]$LogRoot,[string]$Action)
  [IO.File]::AppendAllText((Join-Path $env:NASA_TEST_ROOT 'manager-called.txt'),$Action)
}
""", encoding="utf-8")
        # Refresh environment values that the appended fixture functions read.
        self.env["NASA_TEST_ROOT"] = str(self.root)
        self.env["NASA_TEST_FILES"] = str(self.files)
        self.env["NASA_TEST_PROGRAM"] = str(package_root)
        self.env["NASA_TEST_STATE"] = str(self.state_root)
        self.env["NASA_TEST_LOCAL"] = str(self.local)
        record = {
            "packageId": "NASA-PunkTheme", "programPath": str(package_root), "instanceId": "a" * 32,
            "installed": True, "cleanupPending": False, "phase": "installed", "ownsAppearance": False,
            "ownedImage": "base.png", "ownedImageHash": "baseline-image-hash",
            "ownedActiveFingerprint": "baseline-fingerprint", "ownedActiveThemeId": "nasa-punk-device-light",
            "lastLaunch": None,
        }
        self.state_root.mkdir(parents=True, exist_ok=True)
        (self.state_root / "installation.json").write_text(json.dumps(record), encoding="utf-8")
        self.state_root.joinpath("logs").mkdir(exist_ok=True)
        manifest = {
            "schemaVersion": 1, "packageId": "NASA-PunkTheme", "files": [
                {"path": "files/start-package.ps1", "bytes": start.stat().st_size, "sha256": sha(start)},
                {"path": "files/package-common.ps1", "bytes": common.stat().st_size, "sha256": sha(common)},
            ],
        }
        (self.files / "package-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        result = self.run_ps(start)
        self.assertIn("NASA 主题窗口", result.stdout)
        self.assertTrue((self.root / "focused.txt").is_file(), "healthy session should only focus its verified window")
        self.assertFalse((self.root / "manager-called.txt").exists(), "healthy session must skip manager repair/restart")
        after = json.loads((self.state_root / "installation.json").read_text(encoding="utf-8"))
        for name in ("ownsAppearance", "ownedImage", "ownedImageHash", "ownedActiveFingerprint", "ownedActiveThemeId"):
            self.assertEqual(after[name], record[name], f"healthy reuse changed ownership baseline field {name}")
        timing = json.loads((self.state_root / "last-start-timings.json").read_text(encoding="utf-8"))
        self.assertEqual(timing["route"], "reuse-healthy")
        self.assertFalse(timing["clientLaunched"])
        self.assertFalse(timing["watcherRestarted"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
