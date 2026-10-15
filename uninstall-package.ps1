[CmdletBinding()]
param([switch]$CheckOnly,[ValidateRange(0,2147483647)][int]$WaitForLauncherPid=0)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'package-common.ps1')
$mutex=$null;$locked=$false
try {
  $packageRoot=Split-Path -Parent $PSScriptRoot
  $null=Read-PackageManifest $packageRoot
  if ($CheckOnly) { Write-Output '{"action":"uninstall","checkOnly":true}';exit 0 }
  Import-PackageEngineHelpers $PSScriptRoot
  Assert-PackageClientClosed
  $locations=Get-PackageLocations
  Assert-PackageWorkerIdle (Join-Path $locations.Program 'files')
  if (-not (Test-Path -LiteralPath $locations.Record -PathType Leaf)) { Write-Output '未发现本主题的安装记录，无需卸载。';exit 0 }
  $mutex=[Threading.Mutex]::new($false,'Local\NASAPunkTheme-Package')
  $locked=$mutex.WaitOne(0)
  if (-not $locked) { throw '另一个安装或卸载入口正在运行，请等待它完成。' }
  $record=Read-PackageRecord $locations
  if ($record.cleanupPending) { Write-Output '卸载清理已提交。请关闭卸载窗口并等待清理完成。';exit 0 }
  $config=Resolve-DreamSkinConfigPaths -StateRoot $locations.Runtime -AllowMissingConfig
  if ($config.ConfigPath -ine $record.configPath) { throw '当前配置位置已改变，请在安装时的配置环境中卸载。已保留备份。' }
  $paths=Get-DreamSkinThemePaths -StateRoot $locations.Runtime
  $active=$null
  if (Test-Path -LiteralPath (Join-Path $paths.Active 'theme.json')) { $active=Read-DreamSkinTheme -ThemeDirectory $paths.Active }
  $restoreOwn=$record.ownsAppearance -and $null -eq $active
  if ($record.ownsAppearance -and $active) {
    if ($record.ownedActiveFingerprint) {
      $expectedId=if ($record.ownedActiveThemeId) { $record.ownedActiveThemeId } else { $script:ThemeId }
      $restoreOwn=$active.Theme.id -ceq $expectedId -and (Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $paths.Active) -ceq $record.ownedActiveFingerprint
    }
    elseif ($active.Theme.id -ceq $script:ThemeId) { $restoreOwn=Test-PackageBundledActiveTheme -ActiveDirectory $paths.Active -FilesRoot $PSScriptRoot }
  }
  # Preflight every saved payload and restoration input before altering anything.
  $saved=Get-PackageChildPath $paths.Saved $script:ThemeId
  $removeSaved=$false
  if (Test-Path -LiteralPath $saved) {
    $fingerprint=Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $saved
    $expected=if ($record.importedFingerprint) { $record.importedFingerprint } else { Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory (Join-Path $PSScriptRoot 'lone-star-theme') }
    $removeSaved=$fingerprint -ceq $expected
  }
  $old=$null;$oldCss=$null
  $backup=Join-Path $locations.State 'before-nasa.toml'
  if ($restoreOwn) {
    Assert-NoPackageReparse $backup
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw '恢复所需的原外观备份缺失，未执行卸载。' }
    if ($record.beforeActive) {
      $snapshot=Join-Path $locations.State 'before-active'
      $old=Read-DreamSkinTheme -ThemeDirectory $snapshot
      $oldCss=Join-Path $snapshot 'theme.css'
      if (-not (Test-Path -LiteralPath $oldCss)) { $oldCss=$null }
    }
  }
  $record.phase='uninstalling'
  Write-PackageJson $locations.Record $record
  Stop-PackageAdapter $locations.Program
  # A unified watcher lives in this package even when a shared engine or an
  # edited active theme is preserved. Stop only that exact recorded watcher
  # before its private script/asset files are removed.
  $state=Read-DreamSkinState -Path $paths.State
  $ownedInjector=Join-Path $locations.Program 'files\.support\upstream\Codex-Dream-Skin-1.5.20\windows\scripts\lone-star-runtime-api.mjs'
  $stoppedOwnedUnified=$false
  if ($state -and (Test-DreamSkinPathEqual -Left $state.injectorPath -Right $ownedInjector)) {
    $null=Stop-DreamSkinRecordedInjector -State $state
    $stoppedOwnedUnified=$true
  }
  if ($restoreOwn) {
    Write-Output '正在恢复本主题管理的外观设置。'
    $state=Read-DreamSkinState -Path $paths.State
    $null=Stop-DreamSkinRecordedInjector -State $state
    if ($record.beforeActive) {
      $null=Set-DreamSkinActiveTheme -ImagePath $old.ImagePath -Theme $old.Theme -SafeCssPath $oldCss -StateRoot $locations.Runtime
    } else {
      if (Test-Path -LiteralPath $paths.Active) { Remove-PackageTree $paths.Active $paths.Active }
    }
    if (Test-Path -LiteralPath $config.ConfigPath) { Restore-DreamSkinBaseTheme -ConfigPath $config.ConfigPath -BackupPath $backup }
    if (Test-Path -LiteralPath $paths.State) { Remove-Item -LiteralPath $paths.State -Force }
  } else {
    if ($stoppedOwnedUnified -and (Test-Path -LiteralPath $paths.State)) {
      $latest=Read-DreamSkinState -Path $paths.State
      if ($latest.browserId -ceq $state.browserId -and $latest.injectorPid -eq $state.injectorPid -and
          (Test-DreamSkinPathEqual -Left $latest.injectorPath -Right $ownedInjector)) { Remove-Item -LiteralPath $paths.State -Force }
    }
    Write-Output '当前已使用其他主题，保留该主题及当前外观设置。'
  }
  if (Test-Path -LiteralPath $saved) {
    if ($removeSaved) {
      Remove-PackageTree $saved $saved
    } else { Write-Output '保存的主题文件已有变化，已保留用户修改。' }
  }
  if ($record.ownedImage -and $record.ownedImage -eq [IO.Path]::GetFileName($record.ownedImage)) {
    $archive=Get-PackageChildPath $paths.Images $record.ownedImage
    $imageHash=if ($record.ownedImageHash) { $record.ownedImageHash } else { (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'lone-star-theme\background.png') -Algorithm SHA256).Hash }
    if ((Test-Path -LiteralPath $archive) -and (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq $imageHash -and $restoreOwn) {
      Assert-NoPackageReparse $archive
      Remove-Item -LiteralPath $archive -Force
    }
  }
  $otherThemes=@(Get-DreamSkinSavedThemes -StateRoot $locations.Runtime)
  if (-not $record.runtimeWasPresent -and $otherThemes.Count -eq 0 -and ($restoreOwn -or -not $record.ownsAppearance)) {
    $runtimeUninstaller=Join-Path $env:LOCALAPPDATA 'Programs\CodexDreamSkin\unins000.exe'
    Assert-NoPackageReparse $runtimeUninstaller
    if (Test-Path -LiteralPath $runtimeUninstaller -PathType Leaf) {
      Write-Output '正在移除此包首次安装的换肤运行器。'
      Invoke-PackageRuntimeUninstaller $runtimeUninstaller
    }
  } else { Write-Output '保留已有或被其他主题使用的共享换肤运行器。' }
  Remove-PackageShortcuts $locations.Program
  # A running EXE cannot delete itself on Windows. An owned temporary helper
  # waits for the launcher to exit before removing the exact package folders.
  $waitFor=0
  if ($WaitForLauncherPid -gt 0) {
    $launcher=Get-Process -Id $WaitForLauncherPid -ErrorAction SilentlyContinue
    if ($launcher -and $launcher.Path -and [IO.Path]::GetFileName($launcher.Path) -ceq '卸载主题.exe') { $waitFor=$launcher.Id }
  }
  $temporary=Join-Path ([IO.Path]::GetTempPath()) ('NASAPunk-Cleanup-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $temporary|Out-Null
  $cleanup=Join-Path $temporary 'cleanup-owned.ps1'
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'cleanup-owned.ps1') -Destination $cleanup
  $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $resultName='nasa-cleanup-'+[guid]::NewGuid().ToString('N')+'.json'
  $record.cleanupPending=$true
  Write-PackageJson $locations.Record $record
  $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "'+$cleanup+'" -WaitForPid '+$waitFor+' -InstanceId '+$record.instanceId+' -ResultName '+$resultName
  try { Start-PackageCleanup -PowerShell $powershell -Arguments $arguments }
  catch { $record.cleanupPending=$false;Write-PackageJson $locations.Record $record;throw }
  Write-Output 'NASA-PACKAGE-CLEANUP-PENDING'
  Write-Output '外观已恢复。关闭卸载窗口后会清理本主题程序及备份；客户端、聊天和其他配置保留。'
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
