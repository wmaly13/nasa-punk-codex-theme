[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$startupClock=[Diagnostics.Stopwatch]::StartNew()
. (Join-Path $PSScriptRoot 'package-common.ps1')
$mutex=$null;$locked=$false
try {
  $locations=Get-PackageLocations
  $packageRoot=Split-Path -Parent $PSScriptRoot
  $null=Read-PackageManifest -PackageRoot $packageRoot -Profile DailyLaunch
  $manifestMs=[math]::Round($startupClock.Elapsed.TotalMilliseconds)
  Import-PackageEngineHelpers $PSScriptRoot
  if ($CheckOnly) { Write-Output '{"action":"start","checkOnly":true}';exit 0 }
  if ($packageRoot -ine $locations.Program -or -not (Test-Path -LiteralPath $locations.Record -PathType Leaf)) { throw '请先运行安装主题.exe，再使用桌面的“ChatGPT · NASA 朋克”入口。' }
  $record=Read-PackageRecord $locations
  if (-not $record.installed -or $record.cleanupPending) { throw '安装尚未完成或正在卸载。请退出客户端后，重新运行新版安装入口。' }
  Assert-PackageWorkerIdle $PSScriptRoot
  $mutex=[Threading.Mutex]::new($false,'Local\NASAPunkTheme-Package')
  $locked=$mutex.WaitOne(0)
  if (-not $locked) { throw '另一个主题操作正在运行，请等待它完成。' }
  $session=Get-PackageLaunchSession
  $admissionMs=[math]::Round($startupClock.Elapsed.TotalMilliseconds)-$manifestMs
  if ($session -and (Get-PackageUnifiedRuntimeHealth -FilesRoot $PSScriptRoot -Session $session)) {
    $focused=Show-PackageVerifiedWindow $session
    $record.lastLaunch=(Get-Date).ToString('o');$record.phase='installed'
    Write-PackageJson $locations.Record $record
    Write-PackageJson (Join-Path $locations.State 'last-start-timings.json') ([ordered]@{
      route='reuse-healthy';manifestMs=$manifestMs;admissionMs=$admissionMs
      totalMs=[math]::Round($startupClock.Elapsed.TotalMilliseconds);windowFocused=[bool]$focused
      clientLaunched=$false;watcherRestarted=$false
    })
    if ($focused) { Write-Output '已切回正在运行的 NASA 主题窗口。' }
    else { Write-Output 'NASA 主题窗口已经运行，请从任务栏切回。' }
    exit 0
  }
  $paths=Get-DreamSkinThemePaths -StateRoot $locations.Runtime
  $saved=Get-PackageChildPath $paths.Saved $script:ThemeId
  $null=Read-DreamSkinTheme -ThemeDirectory $saved
  # Save ownership before startup: a failed launch must still be recoverable.
  $record.ownsAppearance=$true;$record.phase='launching'
  Write-PackageJson $locations.Record $record
  $logs=Join-Path $locations.State ('logs\start-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  New-Item -ItemType Directory -Path $logs -Force|Out-Null
  Invoke-PackageManager -FilesRoot $PSScriptRoot -LogRoot $logs -Action Launch
  $active=Read-DreamSkinTheme -ThemeDirectory $paths.Active
  if ($active.Theme.id -cne $script:ThemeId) { throw '当前主题身份与 NASA 主题不一致，请查看启动日志。' }
  $record.ownedImage=[IO.Path]::GetFileName($active.ImagePath)
  $record.ownedImageHash=(Get-FileHash -LiteralPath $active.ImagePath -Algorithm SHA256).Hash
  $record.ownedActiveFingerprint=Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $paths.Active
  $record.ownedActiveThemeId=$script:ThemeId
  $record.lastLaunch=(Get-Date).ToString('o');$record.phase='installed'
  Write-PackageJson $locations.Record $record
  Write-PackageJson (Join-Path $locations.State 'last-start-timings.json') ([ordered]@{
    route=if ($session) {'repair-existing'} else {'cold-start'}
    manifestMs=$manifestMs;admissionMs=$admissionMs;totalMs=[math]::Round($startupClock.Elapsed.TotalMilliseconds)
  })
  Write-Output '客户端与 NASA 朋克主题已启动。未重新安装，也未覆盖首次安装备份。'
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
