[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'package-common.ps1')
$mutex=$null;$locked=$false
try {
  $packageRoot=Split-Path -Parent $PSScriptRoot
  $manifest=Read-PackageManifest $packageRoot
  if ($CheckOnly) { Write-Output ($manifest|Select-Object packageId,packageVersion,schemaVersion|ConvertTo-Json);exit 0 }
  Import-PackageEngineHelpers $PSScriptRoot
  Assert-PackageClientClosed -RequireInstall
  $locations=Get-PackageLocations
  $freshBaseline=$false
  Assert-PackageWorkerIdle (Join-Path $locations.Program 'files')
  $mutex=[Threading.Mutex]::new($false,'Local\NASAPunkTheme-Package')
  $locked=$mutex.WaitOne(0)
  if (-not $locked) { throw '另一个安装或卸载入口正在运行，请等待它完成。' }
  if ((Test-Path -LiteralPath $locations.Program) -and -not (Test-Path -LiteralPath $locations.Record -PathType Leaf)) {
    throw '安装目录已存在但没有本主题的安装记录。请先检查该目录，程序不会覆盖它。'
  }
  New-Item -ItemType Directory -Path $locations.State -Force|Out-Null
  $record=$null
  if (Test-Path -LiteralPath $locations.Record) {
    $record=Read-PackageRecord $locations
    if ($record.cleanupPending) { throw '卸载后的清理尚未完成，请关闭卸载窗口并等待清理完成后再安装。' }
  } else {
    $freshBaseline=$true
    $existing=Get-PackageChildPath (Join-Path $locations.Runtime 'themes') $script:ThemeId
    if (Test-Path -LiteralPath $existing) { throw '发现没有本安装记录的同名主题，已停止安装，避免覆盖已有文件。' }
    $config=Resolve-DreamSkinConfigPaths -StateRoot $locations.Runtime -AllowMissingConfig
    $backup=Join-Path $locations.State 'before-nasa.toml'
    if (Test-Path -LiteralPath $config.ConfigPath -PathType Leaf) {
      [IO.File]::WriteAllBytes($backup,[IO.File]::ReadAllBytes($config.ConfigPath))
    } else { [IO.File]::WriteAllText($backup,'',$script:Utf8) }
    Write-DreamSkinAppearanceMarker -BackupPath $backup -Managed $true
    $beforeTheme=$false
    $paths=Get-DreamSkinThemePaths -StateRoot $locations.Runtime
    if (Test-Path -LiteralPath (Join-Path $paths.Active 'theme.json')) {
      $previous=Read-DreamSkinTheme -ThemeDirectory $paths.Active
      $snapshot=Join-Path $locations.State 'before-active'
      New-Item -ItemType Directory -Path $snapshot -Force|Out-Null
      Copy-Item -LiteralPath (Join-Path $paths.Active 'theme.json') -Destination $snapshot
      Copy-Item -LiteralPath $previous.ImagePath -Destination $snapshot
      if (Test-Path -LiteralPath (Join-Path $paths.Active 'theme.css')) { Copy-Item -LiteralPath (Join-Path $paths.Active 'theme.css') -Destination $snapshot }
      $beforeTheme=$true
    }
    $record=[pscustomobject]@{
      schemaVersion=2;packageId=$script:PackageId;packageVersion=$manifest.packageVersion
      instanceId=[guid]::NewGuid().ToString('N');cleanupPending=$false
      programPath=$locations.Program;configPath=$config.ConfigPath;beforeActive=$beforeTheme
      runtimeWasPresent=(Test-Path -LiteralPath (Join-Path $locations.Engine 'VERSION'))
      importedFingerprint=$null;ownedImage=$null;ownedImageHash=$null
      installed=$false;phase='baseline-saved';ownsAppearance=$false;ownedActiveFingerprint=$null;ownedActiveThemeId=$null;lastLaunch=$null;createdAt=(Get-Date).ToString('o')
    }
    Write-PackageJson $locations.Record $record
  }
  Write-Output '正在复制主题与程序文件到当前用户目录。'
  Stop-PackageAdapter $locations.Program
  New-Item -ItemType Directory -Path $locations.Program -Force|Out-Null
  if ([IO.Path]::GetFullPath($packageRoot).TrimEnd('\') -ine $locations.Program.TrimEnd('\')) {
    foreach ($entry in $manifest.files) {
      $from=Get-PackageChildPath $packageRoot $entry.path
      $to=Get-PackageChildPath $locations.Program $entry.path
      Assert-NoPackageReparse $to
      New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force|Out-Null
      Copy-Item -LiteralPath $from -Destination $to -Force
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'package-manifest.json') -Destination (Join-Path $locations.Program 'files\package-manifest.json') -Force
  }
  $installedFiles=Join-Path $locations.Program 'files'
  $null=Read-PackageManifest $locations.Program
  $record.phase='files-copied';$record.installed=$false
  Write-PackageJson $locations.Record $record
  $logs=Join-Path $locations.State ('logs\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Path $logs -Force|Out-Null
  Write-Output '正在安装或复用换肤运行器，并导入 NASA 朋克主题。此步骤不打开客户端。'
  Invoke-PackageManager -FilesRoot $installedFiles -LogRoot $logs -Action Stage
  $paths=Get-DreamSkinThemePaths -StateRoot $locations.Runtime
  $saved=Get-PackageChildPath $paths.Saved $script:ThemeId
  $expected=Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory (Join-Path $installedFiles 'lone-star-theme')
  $record.importedFingerprint=Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $saved
  if ($record.importedFingerprint -cne $expected) { throw '导入后的主题与安装包不一致，已保留备份。' }
  $record.phase='theme-imported'
  if (-not $record.runtimeWasPresent -and $freshBaseline) {
    # Setup may seed its own base appearance. Remember precisely what we own.
    $record.ownsAppearance=$true
    if (Test-Path -LiteralPath (Join-Path $paths.Active 'theme.json')) {
      $record.ownedActiveFingerprint=Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $paths.Active
      $record.ownedActiveThemeId=(Read-DreamSkinTheme -ThemeDirectory $paths.Active).Theme.id
    }
  }
  Write-PackageJson $locations.Record $record
  Write-Output 'NASA-PACKAGE-STAGE:正在创建并验证桌面和开始菜单入口'
  Register-PackageShortcuts $locations.Program
  $record.schemaVersion=2;$record.installed=$true;$record.phase='installed';$record.packageVersion=$manifest.packageVersion
  Write-PackageJson $locations.Record $record
  Write-Output '安装已完成。桌面已创建“ChatGPT · NASA 朋克”。以后使用此入口，可将它固定到任务栏；原来的 ChatGPT 图标仍打开官方外观。安装程序不会自动打开或关闭客户端。'
  exit 0
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  [Console]::Error.WriteLine($_.InvocationInfo.PositionMessage)
  if ($_.Exception.Data['UserActionRequired']) { exit 2 }
  exit 1
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  if ($mutex) { $mutex.Dispose() }
}
