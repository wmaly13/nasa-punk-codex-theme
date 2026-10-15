#!/usr/bin/env python3
"""Build the NASA-Punk Windows beta package from a flat source staging folder.

Place this script beside the flat, reviewed source inputs. Supply an extracted
Codex-Dream-Skin-1.5.20 checkout and its pinned installer with --upstream and
--installer. The builder validates every source before creating any output.
--check-only performs validation without compiling or creating files. A normal
build refuses to replace either the output directory or archive.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import zipfile


RUNTIME_VERSION = "1.5.20"
PACKAGE_NAME = "NASA-Punk-Windows-v0.7.3-beta"
INSTALLER_SHA256 = "2b13c6816c30ea4000aaa0dd7ef9a4935508816192124e7b87e3b29759c1f8b3"
THEME_ZIP_SHA256 = "4d340a449d19e7c183a1cb848c1d1c3f8602958e27722f00fc2c6212b0d58e89"
THEME_FILES = ("theme.json", "theme.css", "background.png")
PACKAGE_SCRIPTS = (
    "cleanup-owned.ps1",
    "install-package.ps1",
    "package-common.ps1",
    "uninstall-package.ps1",
    "start-package.ps1",
)
UPSTREAM_API = "scripts/lone-star-runtime-api.mjs"


class BuildError(Exception):
    """A concise, user-correctable source or build configuration error."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_file(path: Path, description: str) -> Path:
    if not path.is_file():
        raise BuildError(f"Missing {description}: {path}")
    return path


def safe_runtime_entries(manifest_path: Path) -> list[dict[str, str]]:
    require_file(manifest_path, "selected runtime hash manifest")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"Cannot read runtime hash manifest: {exc}") from exc
    if manifest.get("runtimeVersion") != RUNTIME_VERSION or not isinstance(manifest.get("files"), list):
        raise BuildError("Runtime hash manifest must identify version 1.5.20 and a files list.")
    entries: list[dict[str, str]] = []
    seen: set[str] = set()
    for entry in manifest["files"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise BuildError("Runtime manifest contains an invalid file entry.")
        rel = PurePosixPath(entry["path"].replace("\\", "/"))
        digest = entry.get("sha256")
        if rel.is_absolute() or not rel.parts or any(part in ("", ".", "..") or ':' in part for part in rel.parts):
            raise BuildError(f"Unsafe path in runtime manifest: {entry['path']!r}")
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdefABCDEF" for c in digest):
            raise BuildError(f"Invalid SHA-256 for runtime file: {entry['path']}")
        canonical = rel.as_posix()
        if canonical in seen:
            raise BuildError(f"Duplicate runtime manifest entry: {canonical}")
        seen.add(canonical)
        entries.append({"path": canonical, "sha256": digest.lower()})
    if not entries:
        raise BuildError("Runtime hash manifest contains no files.")
    return entries


def validate_sources(root: Path, upstream: Path, installer: Path) -> tuple[list[dict[str, str]], dict[str, Path]]:
    required_names = [
        "Launcher.cs", *PACKAGE_SCRIPTS, "lone-star-adapter.mjs", "lone-star-style.mjs", "manage-lone-star.ps1",
        "lone-star-runtime-api.mjs", *THEME_FILES, "Codex-Dream-Skin-LICENSE.txt",
        "使用说明.txt", "NASA-Punk-Theme.zip", "selected-runtime-hashes.json",
        "Codex-Dream-Skin-NOTICE.md", "Inno-Setup-License.txt", "THIRD_PARTY_NOTICES.md",
    ]
    sources = {name: require_file(root / name, f"staged source {name}") for name in required_names}
    installer = require_file(installer, "pinned Codex Dream Skin installer")
    if sha256(installer).lower() != INSTALLER_SHA256:
        raise BuildError("Installer SHA-256 does not match the pinned v1.5.20 installer.")

    entries = safe_runtime_entries(sources["selected-runtime-hashes.json"])
    upstream = upstream.resolve()
    version_file = require_file(upstream / "windows" / "VERSION", "upstream Windows runtime VERSION")
    version = version_file.read_text(encoding="utf-8-sig").strip()
    if version != RUNTIME_VERSION:
        raise BuildError(f"Upstream runtime version is {version!r}; expected {RUNTIME_VERSION}.")

    # Validate all required runtime sources, including the API helper, before
    # creating the destination directory or compiling the launcher.
    for entry in entries:
        source = upstream / "windows" / Path(entry["path"])
        require_file(source, f"upstream runtime source {entry['path']}")
        if sha256(source).lower() != entry["sha256"]:
            raise BuildError(f"Upstream runtime hash mismatch: {entry['path']}")
    # This repository carries its own adapted runtime API; the unmodified
    # upstream archive does not contain that additional filename.
    require_file(sources["lone-star-runtime-api.mjs"], "adapted runtime API helper")
    for name in ("start-dream-skin.ps1", "verify-dream-skin.ps1"):
        nasa_session_script(upstream, name)

    # The separately staged exact ZIP is what the manager's pinned hash expects.
    theme_zip = sources["NASA-Punk-Theme.zip"]
    if sha256(theme_zip).lower() != THEME_ZIP_SHA256:
        raise BuildError("NASA-Punk-Theme.zip SHA-256 does not match the release manager's pinned value.")
    try:
        with zipfile.ZipFile(theme_zip) as archive:
            names = set(archive.namelist())
            if names != set(THEME_FILES) or archive.testzip() is not None:
                raise BuildError("The staged theme ZIP must contain exactly theme.json, theme.css, and background.png.")
            for name in THEME_FILES:
                if archive.read(name) != sources[name].read_bytes():
                    raise BuildError(f"Theme ZIP content differs from staged source: {name}")
    except (OSError, zipfile.BadZipFile, KeyError) as exc:
        raise BuildError(f"Cannot validate staged theme ZIP: {exc}") from exc

    # Ensure the separate upstream license is present with an actual notice.
    license_text = sources["Codex-Dream-Skin-LICENSE.txt"].read_text(encoding="utf-8-sig")
    if "MIT License" not in license_text or "Copyright" not in license_text:
        raise BuildError("The staged third-party MIT license is missing its expected attribution.")
    if THEME_ZIP_SHA256 not in sources['manage-lone-star.ps1'].read_text(encoding='utf-8-sig'):
        raise BuildError('Manager does not contain the expected inner theme ZIP hash.')
    return entries, sources


def compiler_path() -> Path:
    system_root = Path(os.environ.get("SystemRoot", r"C:\Windows"))
    compiler = system_root / "Microsoft.NET" / "Framework64" / "v4.0.30319" / "csc.exe"
    return require_file(compiler, ".NET Framework 64-bit C# compiler")


def nasa_session_script(upstream: Path, name: str) -> str:
    """Use the pinned lifecycle with our unified injector and installed Node.

    The upstream source stays intact. Required substitutions fail closed when the
    pinned source contract changes; generated copies belong to this package.
    """
    text = (upstream / "windows/scripts" / name).read_text(encoding="utf-8-sig")
    variable = "$Injector" if name.startswith("start-") else "$injector"
    original = variable + " = Join-Path $PSScriptRoot 'injector.mjs'"
    anchor = ". (Join-Path $PSScriptRoot 'theme-windows.ps1')"
    if text.count(original) != 1 or text.count(anchor) != 1:
        raise BuildError(f"Pinned lifecycle adapter contract changed: {name}")
    text = text.replace(original, variable + " = Join-Path $PSScriptRoot 'lone-star-runtime-api.mjs'", 1)
    if name.startswith("start-"):
        seed_source = "Initialize-DreamSkinThemeStore -SkillRoot (Split-Path -Parent $PSScriptRoot) -StateRoot $StateRoot"
        if text.count(seed_source) != 1:
            raise BuildError("Pinned theme-store initialization contract changed.")
        # The selected private source tree has validators and runtime code, but
        # does not ship the upstream default artwork. Seed from the complete
        # installed engine, which the manager verifies before this script runs.
        text = text.replace(seed_source,
            "Initialize-DreamSkinThemeStore -SkillRoot (Join-Path $StateRoot 'engine') -StateRoot $StateRoot", 1)
    node_override = """
# NASA package: use the signed Node shipped by the installed, verified engine.
function Get-DreamSkinNodeRuntime {
  param([int]$MinimumMajor = 22)
  $nodePath = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\\engine\\runtime\\node\\node.exe'
  return Get-DreamSkinValidatedNodeRuntime -Path $nodePath -MinimumMajor $MinimumMajor
}
"""
    return text.replace(anchor, anchor + "\n" + node_override, 1)


def write_package(root: Path, output: Path, archive_path: Path, upstream: Path,
                  installer: Path, entries: list[dict[str, str]], sources: dict[str, Path]) -> dict[str, object]:
    # Validate the compiler before making output. The compilation itself writes
    # only inside the newly created package directory.
    compiler = compiler_path()
    if output.exists() or archive_path.exists():
        raise BuildError(f"Refusing to overwrite existing output: {output if output.exists() else archive_path}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir()
    files = output / "files"
    support = files / ".support"
    runtime_root = support / "upstream" / f"Codex-Dream-Skin-{RUNTIME_VERSION}" / "windows"
    for directory in (files, support, files / 'licenses', files / 'lone-star-theme', runtime_root / 'scripts', runtime_root / 'assets'):
        directory.mkdir(parents=True, exist_ok=True)

    for name in PACKAGE_SCRIPTS:
        (files / name).write_text(sources[name].read_text(encoding='utf-8-sig'), encoding='utf-8-sig')
    (files / "使用说明.txt").write_bytes(sources["使用说明.txt"].read_bytes())
    shutil.copyfile(sources["lone-star-adapter.mjs"], support / "lone-star-adapter.mjs")
    shutil.copyfile(sources["lone-star-style.mjs"], support / "lone-star-style.mjs")
    (support / "manage-lone-star.ps1").write_text(sources['manage-lone-star.ps1'].read_text(encoding='utf-8-sig'), encoding='utf-8-sig')
    shutil.copyfile(sources["selected-runtime-hashes.json"], support / "selected-runtime-hashes.json")
    shutil.copyfile(installer, support / 'CodexDreamSkin-Setup-v1.5.20.exe')
    shutil.copyfile(sources["Codex-Dream-Skin-LICENSE.txt"], files / "licenses" / "Codex-Dream-Skin-LICENSE.txt")
    for notice in ('Codex-Dream-Skin-NOTICE.md', 'Inno-Setup-License.txt', 'THIRD_PARTY_NOTICES.md'):
        shutil.copyfile(sources[notice], files / 'licenses' / notice)
    for name in THEME_FILES:
        shutil.copyfile(sources[name], files / "lone-star-theme" / name)
    shutil.copyfile(sources["NASA-Punk-Theme.zip"], files / "NASA-Punk-Theme.zip")
    shutil.copyfile(sources["lone-star-runtime-api.mjs"], runtime_root / UPSTREAM_API)
    version_source = upstream / "windows" / "VERSION"
    shutil.copyfile(version_source, runtime_root / "VERSION")
    for entry in entries:
        target = runtime_root / Path(entry['path'])
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(upstream / "windows" / Path(entry["path"]), target)
    for source_name, target_name in (
        ("start-dream-skin.ps1", "start-nasa-session.ps1"),
        ("verify-dream-skin.ps1", "verify-nasa-session.ps1"),
    ):
        (runtime_root / "scripts" / target_name).write_text(
            nasa_session_script(upstream, source_name), encoding="utf-8-sig")

    exe = output / "安装主题.exe"
    command = [
        str(compiler), "/nologo", "/target:winexe", "/platform:x64",
        "/reference:System.Windows.Forms.dll", "/reference:System.Drawing.dll",
        "/out:" + str(exe), str(sources["Launcher.cs"]),
    ]
    try:
        subprocess.run(command, check=True, cwd=str(root))
    except (OSError, subprocess.CalledProcessError) as exc:
        raise BuildError(f"Could not compile Launcher.cs: {exc}") from exc
    shutil.copyfile(exe, output / "卸载主题.exe")
    shutil.copyfile(exe, files / "ChatGPT-NASA.exe")

    manifest_files = sorted(path for path in output.rglob("*") if path.is_file() and path.name != "package-manifest.json")
    manifest = {
        "schemaVersion": 1,
        "packageId": "NASA-PunkTheme",
        "packageVersion": "0.7.3-beta",
        "platform": "Windows x64",
        "runtimeVersion": RUNTIME_VERSION,
        "files": [
            {"path": path.relative_to(output).as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in manifest_files
        ],
    }
    (files / "package-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    try:
        with zipfile.ZipFile(archive_path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for path in sorted(output.rglob("*")):
                if path.is_file():
                    bundle.write(path, f"{output.name}/{path.relative_to(output).as_posix()}")
        with zipfile.ZipFile(archive_path) as bundle:
            if bundle.testzip() is not None:
                raise BuildError("Output ZIP failed its integrity check.")
            top = {PurePosixPath(item.filename).parts[1] for item in bundle.infolist() if len(PurePosixPath(item.filename).parts) > 1}
            if top != {"files", "安装主题.exe", "卸载主题.exe"}:
                raise BuildError(f"Unexpected release ZIP top-level layout: {sorted(top)}")
    except (OSError, zipfile.BadZipFile) as exc:
        raise BuildError(f"Could not finish output ZIP: {exc}") from exc

    return {
        "package": str(output),
        "archive": str(archive_path),
        "archiveSha256": sha256(archive_path),
        "archiveBytes": archive_path.stat().st_size,
        "files": len(manifest["files"]),
        "realInstallationRun": False,
        "clientClosedOrRestarted": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", required=True, type=Path,
                        help="Path to an extracted Codex-Dream-Skin-1.5.20 repository")
    parser.add_argument("--installer", required=True, type=Path,
                        help="Path to the pinned CodexDreamSkin-Setup-v1.5.20.exe")
    parser.add_argument("--check-only", action="store_true",
                        help="Validate every staged input without compiling or writing output")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    upstream = args.upstream.resolve()
    installer = args.installer.resolve()
    output = root / "dist" / PACKAGE_NAME
    archive_path = root / "dist" / f"{PACKAGE_NAME}.zip"
    try:
        entries, sources = validate_sources(root, upstream, installer)
        if args.check_only:
            print(json.dumps({"check": "passed", "runtimeFiles": len(entries), "outputCreated": False}, indent=2))
            return 0
        result = write_package(root, output, archive_path, upstream, installer, entries, sources)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except BuildError as exc:
        print(f"build.py: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
