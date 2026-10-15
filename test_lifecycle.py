#!/usr/bin/env python3
"""Run isolated lifecycle regression cases against a built NASA Punk package.

The harness copies a package to a fresh fixture and replaces only external
service boundaries in that copy. Production lifecycle, manifest, record,
shortcut, semantic-fingerprint, and cleanup code remains under test. Each
PowerShell process receives an isolated profile and CODEX_HOME. The real
ChatGPT/Codex client is never started or stopped.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


class Suite:
    def __init__(self, package: Path, output: Path, node: Path):
        self.package = package.resolve(strict=True)
        self.output = output.resolve()
        if not self.package.is_dir():
            raise ValueError("--package must be a built package directory")
        if self.output.exists():
            raise ValueError("--output already exists; choose a new test directory")
        if self.output == self.package or self.package in self.output.parents or self.output in self.package.parents:
            raise ValueError("--output must be disjoint from --package")
        if not (self.package / "files" / "package-common.ps1").is_file():
            raise ValueError("package is missing files/package-common.ps1")
        self.output.mkdir(parents=True)
        self.fixture = self.output / "fixture-package"
        shutil.copytree(self.package, self.fixture, copy_function=shutil.copy2)
        self.common = self.fixture / "files" / "package-common.ps1"
        self.node = node.resolve(strict=True)
        self._add_test_overrides()
        self._rehash_manifest()
        self.ps = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        if not self.ps.is_file():
            raise RuntimeError("Windows PowerShell 5.1 was not found")

    def _add_test_overrides(self) -> None:
        addition = r"""
# Test-only boundaries appended in the copied package fixture.
$script:FixtureOriginalImportEngine=${function:Import-PackageEngineHelpers}
function Import-PackageEngineHelpers {
  param([string]$FilesRoot)
  & $script:FixtureOriginalImportEngine -FilesRoot $FilesRoot
  Set-Item -Path Function:global:Get-DreamSkinNodeRuntime -Value ([scriptblock]::Create("param([int]`$MinimumMajor=22); Get-DreamSkinValidatedNodeRuntime -Path '__NODE__' -MinimumMajor `$MinimumMajor"))
}
function Assert-PackageClientClosed { param([switch]$RequireInstall)
  if ($env:NASA_TEST_CLIENT_RUNNING -eq '1') { $e=[InvalidOperationException]::new('fixture: client running');$e.Data['UserActionRequired']=$true;throw $e }
}
function Assert-PackageWorkerIdle { param([string]$FilesRoot) }
function Stop-PackageAdapter { param([string]$ProgramRoot) }
function Get-PackageLaunchSession { Assert-PackageClientClosed -RequireInstall;return $null }
function Get-PackageChatGPTIcon {
  param([string]$ProgramRoot)
  Add-Type -AssemblyName System.Drawing
  $path=Join-Path $ProgramRoot 'files\.support\chatgpt.ico'
  $stream=[IO.File]::Create($path)
  try { [Drawing.SystemIcons]::Application.Save($stream) } finally { $stream.Dispose() }
  return $path
}
function Get-PackageShortcutPaths {
  $root=$env:NASA_TEST_ROOT;$desk=Join-Path $root 'profile\Desktop';$menu=Join-Path $root 'profile\Programs\NASA Punk Test'
  return @(
    [pscustomobject]@{Path=(Join-Path $desk 'ChatGPT NASA.lnk');Kind='start'},
    [pscustomobject]@{Path=(Join-Path $menu 'ChatGPT NASA.lnk');Kind='start'},
    [pscustomobject]@{Path=(Join-Path $menu 'Uninstall NASA.lnk');Kind='uninstall'}
  )
}
function Invoke-PackageManager {
  param([string]$FilesRoot,[string]$LogRoot,[ValidateSet('Stage','Launch')][string]$Action)
  $locations=Get-PackageLocations
  if ($Action -eq 'Stage') {
    [IO.File]::AppendAllText((Join-Path $env:NASA_TEST_ROOT 'manager-actions.txt'),'Stage'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $engine=Join-Path $FilesRoot '.support\upstream\Codex-Dream-Skin-1.5.20\windows'
    $node=Get-DreamSkinNodeRuntime
    if (-not $node -or -not (Test-Path -LiteralPath $node.Path -PathType Leaf)) { throw 'fixture requires the verified Node runtime' }
    $null=Import-DreamSkinThemeZip -ArchivePath (Join-Path $FilesRoot 'NASA-Punk-Theme.zip') -StateRoot $locations.Runtime
    if ($env:NASA_TEST_STAGE_FAIL_ONCE -eq '1' -and -not (Test-Path (Join-Path $env:NASA_TEST_ROOT 'stage-failure-used'))) {
      [IO.File]::WriteAllText((Join-Path $env:NASA_TEST_ROOT 'stage-failure-used'),'yes')
      throw 'fixture: injected post-import Stage failure'
    }
  } else {
    [IO.File]::AppendAllText((Join-Path $env:NASA_TEST_ROOT 'manager-actions.txt'),'Launch'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $paths=Get-DreamSkinThemePaths -StateRoot $locations.Runtime
    $config=Resolve-DreamSkinConfigPaths -StateRoot $locations.Runtime -AllowMissingConfig
    $null=Install-DreamSkinBaseTheme -ConfigPath $config.ConfigPath -BackupPath (Join-Path $locations.State 'before-nasa.toml') -AppearanceTheme light
    $null=Use-DreamSkinSavedTheme -ThemeDirectory (Join-Path $paths.Saved 'nasa-punk-device-light') -StateRoot $locations.Runtime
  }
}
function Start-PackageCleanup {
  param([string]$PowerShell,[string]$Arguments)
  $helper=[regex]::Match($Arguments,'-File\s+"([^"]+)"').Groups[1].Value
  if (-not $helper -or -not (Test-Path -LiteralPath $helper)) { throw 'fixture could not capture cleanup helper' }
  $m=[regex]::Match($Arguments,'-InstanceId\s+([0-9a-f]{32})').Groups[1].Value
  $r=[regex]::Match($Arguments,'-ResultName\s+(nasa-cleanup-[0-9a-f]{32}\.json)').Groups[1].Value
  [ordered]@{ScriptPath=$helper;InstanceId=$m;ResultName=$r}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $env:NASA_TEST_ROOT 'cleanup-invocation.json') -Encoding UTF8
}
"""
        with self.common.open("a", encoding="utf-8", newline="\n") as f:
            f.write("\n" + addition.replace('__NODE__', str(self.node).replace("'", "''")))

    def _rehash_manifest(self) -> None:
        path = self.fixture / "files" / "package-manifest.json"
        doc = json.loads(path.read_text(encoding="utf-8-sig"))
        target = self.common
        found = False
        for entry in doc["files"]:
            if entry["path"].replace("/", "\\").lower() == "files\\package-common.ps1":
                entry["bytes"] = target.stat().st_size
                entry["sha256"] = sha(target)
                found = True
        if not found:
            raise ValueError("manifest does not cover files/package-common.ps1")
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def env(self, name: str, client_running: bool = False, fail_stage: bool = False) -> dict[str, str]:
        root = self.output / name
        profile = root / "profile"
        for p in (profile / "Desktop", profile / "Documents", profile / "Programs",
                  profile / "AppData/Roaming", profile / "AppData/Local",
                  profile / "AppData/Roaming/Microsoft/Windows/Start Menu/Programs",
                  root / "temp", root / "codex-home"):
            p.mkdir(parents=True, exist_ok=True)
        e = os.environ.copy()
        e.update({"LOCALAPPDATA": str(profile / "AppData/Local"), "USERPROFILE": str(profile),
                  "APPDATA": str(profile / "AppData/Roaming"), "TEMP": str(root / "temp"),
                  "TMP": str(root / "temp"), "CODEX_HOME": str(root / "codex-home"),
                  "NASA_TEST_ROOT": str(root), "NASA_TEST_CLIENT_RUNNING": "1" if client_running else "0",
                  "NASA_TEST_STAGE_FAIL_ONCE": "1" if fail_stage else "0"})
        Path(e["LOCALAPPDATA"]).mkdir(parents=True, exist_ok=True)
        engine = Path(e['LOCALAPPDATA']) / 'CodexDreamSkin/engine'
        if not engine.exists():
            source = self.fixture / 'files/.support/upstream/Codex-Dream-Skin-1.5.20/windows'
            shutil.copytree(source, engine)
        return e

    def run_ps(self, script: Path, env: dict[str, str], expect: int, args: list[str] | None = None) -> subprocess.CompletedProcess[str]:
        cmd = [str(self.ps), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-File", str(script)] + (args or [])
        p = subprocess.run(cmd, cwd=str(script.parent), env=env, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=180)
        if p.returncode != expect:
            raise AssertionError(f"{script.name}: expected exit {expect}, got {p.returncode}\nstdout:\n{p.stdout}\nstderr:\n{p.stderr}")
        return p

    def paths(self, env: dict[str, str]) -> tuple[Path, Path, Path]:
        local = Path(env["LOCALAPPDATA"])
        return local / "Programs/NASA-PunkTheme", local / "NASA-PunkTheme", local / "CodexDreamSkin"

    def code(self, env: dict[str, str], body: str) -> None:
        script = Path(env['NASA_TEST_ROOT']) / 'fixture-action.ps1'
        files = str(self.fixture / 'files').replace("'", "''")
        text = "$ErrorActionPreference='Stop'\n. '" + files + "\\package-common.ps1'\nImport-PackageEngineHelpers '" + files + "'\n" + body
        script.write_text(text, encoding='utf-8-sig')
        self.run_ps(script, env, 0)

    def install(self, env: dict[str, str], expect: int = 0):
        return self.run_ps(self.fixture / "files/install-package.ps1", env, expect)

    def start(self, env: dict[str, str], expect: int = 0):
        program, _, _ = self.paths(env)
        return self.run_ps(program / "files/start-package.ps1", env, expect)

    def uninstall(self, env: dict[str, str], expect: int = 0):
        return self.run_ps(self.fixture / "files/uninstall-package.ps1", env, expect)

    def cleanup(self, env: dict[str, str]) -> None:
        root = Path(env["NASA_TEST_ROOT"])
        spec = json.loads((root / "cleanup-invocation.json").read_text(encoding="utf-8-sig"))
        helper = Path(spec["ScriptPath"])
        if sha(helper) != sha(self.fixture / "files/cleanup-owned.ps1"):
            raise AssertionError("captured cleanup helper differs from production payload")
        p = subprocess.run([str(self.ps), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
                            "-File", str(helper), "-WaitForPid", "0", "-InstanceId", spec["InstanceId"], "-ResultName", spec["ResultName"]],
                           env=env, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=120)
        if p.returncode != 0:
            raise AssertionError(f"production cleanup failed:\n{p.stdout}\n{p.stderr}")
        result = Path(env["LOCALAPPDATA"]) / "CodexDreamSkin/logs" / spec["ResultName"]
        if json.loads(result.read_text(encoding="utf-8-sig"))["status"] != "complete":
            raise AssertionError("production cleanup did not report complete")

    def happy_retry_and_cleanup(self) -> None:
        env = self.env("happy-retry", fail_stage=True)
        program, state, _ = self.paths(env)
        config = Path(env["CODEX_HOME"]) / "config.toml"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text('user_note = "original"\n[desktop]\nappearanceTheme = "dark"\n', encoding="utf-8")
        original = config.read_bytes()
        failed = self.install(env, expect=1)
        record_path = state / "installation.json"
        backup = state / "before-nasa.toml"
        if not record_path.exists() or backup.read_bytes() != original:
            raise AssertionError("failed Stage did not preserve first-install recovery state\n" + failed.stdout + '\n' + failed.stderr)
        backup_hash = sha(backup)
        self.install(env)
        record = json.loads(record_path.read_text(encoding="utf-8-sig"))
        if not record["installed"] or record["phase"] != "installed" or not record.get("importedFingerprint"):
            raise AssertionError("retry did not finish with a real semantic fingerprint")
        if sha(backup) != backup_hash:
            raise AssertionError("retry overwrote first-install baseline")
        shortcuts = [Path(env["USERPROFILE"]) / "Desktop/ChatGPT NASA.lnk",
                     Path(env["USERPROFILE"]) / "Programs/NASA Punk Test/ChatGPT NASA.lnk",
                     Path(env["USERPROFILE"]) / "Programs/NASA Punk Test/Uninstall NASA.lnk"]
        if not all(p.is_file() for p in shortcuts):
            raise AssertionError("install did not create all three real sandbox shortcuts")
        self.code(env, r"""
$program=(Get-PackageLocations).Program
$expected=(Join-Path $program 'files\.support\chatgpt.ico')+',0'
$shell=New-Object -ComObject WScript.Shell
foreach ($entry in (Get-PackageShortcutPaths|Where-Object Kind -eq 'start')) {
  if ($shell.CreateShortcut($entry.Path).IconLocation -ine $expected) { throw 'Startup shortcut icon did not match the installed icon.' }
}
""")
        trace = Path(env["NASA_TEST_ROOT"]) / "manager-actions.txt"
        self.start(env)
        self.start(env)
        if trace.read_text(encoding="utf-8").splitlines() != ["Stage", "Stage", "Launch", "Launch"]:
            raise AssertionError("daily start unexpectedly staged/reimported theme")
        if sha(backup) != backup_hash:
            raise AssertionError("daily start changed original backup")
        old_trace = trace.read_bytes()
        busy_env = env.copy()
        busy_env['NASA_TEST_CLIENT_RUNNING'] = '1'
        self.start(busy_env, expect=2)
        if trace.read_bytes() != old_trace:
            raise AssertionError("client-running guard reached manager")
        legacy = json.loads(record_path.read_text(encoding="utf-8-sig"))
        legacy.update({"schemaVersion": 1, "installed": False, "importedFingerprint": None})
        for key in ("ownsAppearance", "ownedActiveFingerprint", "ownedImageHash", "lastLaunch"):
            legacy.pop(key, None)
        record_path.write_text(json.dumps(legacy), encoding="utf-8")
        self.install(env)
        if sha(backup) != backup_hash or not json.loads(record_path.read_text(encoding="utf-8-sig"))["installed"]:
            raise AssertionError("legacy recovery overwrote baseline or failed")
        self.uninstall(env)
        self.cleanup(env)
        if program.exists() or state.exists():
            raise AssertionError("production cleanup left package-owned folders")

    def preserve_baseline_and_foreign_data(self) -> None:
        env = self.env('preserve')
        program, state, runtime = self.paths(env)
        config = Path(env['CODEX_HOME']) / 'config.toml'
        config.write_text('user_note = "before"\n[desktop]\nappearanceTheme = "dark"\n', encoding='utf-8')
        self.code(env, r"""
$loaded=Read-DreamSkinTheme -ThemeDirectory (Join-Path $PSScriptRoot '..\fixture-package\files\lone-star-theme')
$loaded.Theme.id='baseline-theme'
$null=Set-DreamSkinActiveTheme -ImagePath $loaded.ImagePath -Theme $loaded.Theme -SafeCssPath (Join-Path $PSScriptRoot '..\fixture-package\files\lone-star-theme\theme.css') -StateRoot (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin')
""")
        self.install(env)
        self.start(env)
        config.write_text(config.read_text(encoding='utf-8-sig').replace('"before"','"after"'), encoding='utf-8')
        saved = runtime / 'themes/nasa-punk-device-light'
        foreign = runtime / 'themes/foreign-theme'
        shutil.copytree(saved, foreign)
        doc = json.loads((foreign/'theme.json').read_text(encoding='utf-8-sig'))
        doc['id'] = 'foreign-theme'
        (foreign/'theme.json').write_text(json.dumps(doc, ensure_ascii=False), encoding='utf-8')
        css = saved/'theme.css'
        css.write_bytes(css.read_bytes()+b'\n/* User saved edit */\n')
        saved_hash = sha(css)
        self.code(env, r"""
$shortcut=Join-Path $env:USERPROFILE 'Desktop\ChatGPT NASA.lnk'
$shell=New-Object -ComObject WScript.Shell
$link=$shell.CreateShortcut($shortcut);$link.TargetPath=Join-Path $env:SystemRoot 'notepad.exe';$link.Save()
""")
        self.uninstall(env)
        if json.loads((runtime/'active-theme/theme.json').read_text(encoding='utf-8-sig'))['id'] != 'baseline-theme':
            raise AssertionError('uninstall did not restore original active theme')
        if 'user_note = "after"' not in config.read_text(encoding='utf-8-sig') or 'appearanceTheme = "dark"' not in config.read_text(encoding='utf-8-sig'):
            raise AssertionError('selective restore lost foreign config edits or base appearance')
        if not foreign.exists() or not css.exists() or sha(css) != saved_hash:
            raise AssertionError('uninstall removed foreign theme or edited saved NASA theme')
        if not (Path(env['USERPROFILE'])/'Desktop/ChatGPT NASA.lnk').is_file():
            raise AssertionError('uninstall removed a shortcut repointed to a foreign program')
        self.cleanup(env)
        if not (runtime/'engine/VERSION').is_file():
            raise AssertionError('uninstall removed a preexisting shared runtime')

    def preserve_active_edits(self, change_id: bool) -> None:
        env = self.env('foreign-id' if change_id else 'same-id-edit')
        _, _, runtime = self.paths(env)
        config = Path(env['CODEX_HOME'])/'config.toml'
        config.write_text('[desktop]\nappearanceTheme = "dark"\n', encoding='utf-8')
        self.install(env)
        self.start(env)
        active = runtime/'active-theme'
        if change_id:
            doc=json.loads((active/'theme.json').read_text(encoding='utf-8-sig'))
            doc['id']='foreign-active'
            (active/'theme.json').write_text(json.dumps(doc,ensure_ascii=False),encoding='utf-8')
        else:
            css=active/'theme.css'
            css.write_bytes(css.read_bytes()+b'\n/* User active edit */\n')
        before = {p.name: sha(p) for p in active.iterdir() if p.is_file()}
        config_hash=sha(config)
        self.uninstall(env)
        after = {p.name: sha(p) for p in active.iterdir() if p.is_file()}
        if after != before or sha(config) != config_hash:
            raise AssertionError('uninstall overwrote user-owned active content/config')
        self.cleanup(env)

    def missing_backup_preflight(self) -> None:
        env = self.env("missing-backup")
        (Path(env['CODEX_HOME'])/'config.toml').write_text('[desktop]\nappearanceTheme = "dark"\n',encoding='utf-8')
        self.install(env)
        program, state, _ = self.paths(env)
        self.start(env)
        config = Path(env["CODEX_HOME"]) / "config.toml"
        config_hash = sha(config)
        (state / "before-nasa.toml").unlink()
        self.uninstall(env, expect=1)
        if sha(config) != config_hash or not program.exists() or not (state / "installation.json").exists():
            raise AssertionError("missing-backup preflight changed state")

    def run(self) -> None:
        self.happy_retry_and_cleanup()
        self.preserve_baseline_and_foreign_data()
        self.preserve_active_edits(change_id=False)
        self.preserve_active_edits(change_id=True)
        self.missing_backup_preflight()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path, help="built package folder containing files/")
    parser.add_argument("--output", required=True, type=Path, help="new, unique directory for isolated fixtures")
    parser.add_argument("--node", required=True, type=Path, help="real signed Node.js 22+ executable used by upstream validators")
    args = parser.parse_args()
    try:
        suite = Suite(args.package, args.output, args.node)
        suite.run()
        print(f"Lifecycle regression cases passed. Isolated artifacts: {suite.output}")
        return 0
    except Exception as exc:
        print(f"Lifecycle regression failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
