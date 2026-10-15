[CmdletBinding()]
param(
  [ValidateSet('Check','Stage','Hot','Apply','Launch','Verify','Restore')][string]$Action = 'Apply',
  [switch]$NoUI,
  [switch]$SkipVisualCheck
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 6) {
  # A helper launched from PowerShell 7 can inherit its module path. Restore
  # Windows PowerShell's own module discovery for this child process only.
  $nativeModules = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
  $programModules = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
  $documents=[Environment]::GetFolderPath('MyDocuments',[Environment+SpecialFolderOption]::DoNotVerify)
  if (-not $documents) { $documents=Join-Path $env:USERPROFILE 'Documents' }
  $userModules = Join-Path $documents 'WindowsPowerShell\Modules'
  $env:PSModulePath = @($nativeModules,$programModules,$userModules) -join ';'
}
$taskRoot = Split-Path -Parent $PSScriptRoot
$sourceWindows = Join-Path $PSScriptRoot 'upstream\Codex-Dream-Skin-1.5.20\windows'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$engineRoot = Join-Path $stateRoot 'engine'
$installer = Join-Path $PSScriptRoot 'CodexDreamSkin-Setup-v1.5.20.exe'
$archive = Join-Path $taskRoot 'NASA-Punk-Theme.zip'
$expectedInstallerHash = '2b13c6816c30ea4000aaa0dd7ef9a4935508816192124e7b87e3b29759c1f8b3'
$expectedArchiveHash = '4d340a449d19e7c183a1cb848c1d1c3f8602958e27722f00fc2c6212b0d58e89'
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logRoot = Join-Path $PSScriptRoot ('runs\' + $runId)
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$report = [ordered]@{
  action = $Action; runtimeVersion = '1.5.20'; themeId = 'nasa-punk-device-light';
  createdAt = (Get-Date).ToString('o'); liveApplied = $false; liveVerified = $false;
  status = 'preparing'; logDirectory = $logRoot
}

function Save-LoneStarState {
  $resultName = if ($Action -eq 'Check') { 'last-check.json' } elseif ($Action -eq 'Stage') { 'prepared-theme.json' } else { 'last-run.json' }
  $json = $report | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $resultName), $json, $utf8)
  [System.IO.File]::WriteAllText((Join-Path $logRoot 'result.json'), $json, $utf8)
}

function Show-LoneStarMessage {
  param([string]$Message, [switch]$ErrorMessage, [switch]$AllowCancel)
  if ($NoUI) { Write-Output $Message; return $true }
  Add-Type -AssemblyName System.Windows.Forms
  $buttons = if ($AllowCancel) { [System.Windows.Forms.MessageBoxButtons]::OKCancel } else { [System.Windows.Forms.MessageBoxButtons]::OK }
  $icon = if ($ErrorMessage) { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
  $result = [System.Windows.Forms.MessageBox]::Show($Message, 'NASA 朋克主题', $buttons, $icon)
  return ($result -eq [System.Windows.Forms.DialogResult]::OK)
}

function Assert-LoneStarHash {
  param([string]$Path, [string]$Expected)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file missing: $Path" }
  if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Expected) {
    throw "File integrity check failed: $Path"
  }
}

function Assert-LoneStarEngine {
  param([string]$Root, [switch]$Installed)
  $manifestPath = Join-Path $PSScriptRoot 'selected-runtime-hashes.json'
  $manifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  foreach ($file in $manifest.files) {
    $target = Join-Path $Root $file.path
    if (-not $Installed) {
      Assert-LoneStarHash -Path $target -Expected $file.sha256
    } elseif ($file.path -ceq 'assets\theme.json') {
      # Official Setup v1.5.20 seeds Gothic Void Crusade; the source tag uses
      # another preset. Pin the verified release's data file independently.
      Assert-LoneStarHash -Path $target -Expected 'f760df6e4d203ead527a00604110e5077d3024f697a3c98e3289cbe70d74fbe5'
    } else {
      # Setup normalizes Windows line endings and UTF-8 BOM. Decode strictly
      # and permit only CRLF/LF differences, with no other code changes.
      $source = Join-Path $sourceWindows $file.path
      Assert-LoneStarHash -Path $source -Expected $file.sha256
      $strictUtf8 = [System.Text.UTF8Encoding]::new($false,$true)
      $expectedText = [System.IO.File]::ReadAllText($source,$strictUtf8).Replace("`r`n","`n")
      $actualText = [System.IO.File]::ReadAllText($target,$strictUtf8).Replace("`r`n","`n")
      if ($actualText -cne $expectedText) { throw "Installed runtime code differs from the verified release source: $target" }
    }
  }
  $version = [System.IO.File]::ReadAllText((Join-Path $Root 'VERSION'), [System.Text.Encoding]::UTF8).Trim()
  if ($version -cne '1.5.20') { throw "Expected Dream Skin 1.5.20; found $version. Recheck compatibility before changing the engine." }
}

function Invoke-LoneStarScript {
  param([string]$Path, [string[]]$Arguments, [string]$Label)
  # Every path is a local absolute path chosen by this package. Never feed arbitrary commands to a shell.
  if ($Path.Contains('"') -or @($Arguments | Where-Object { $_.Contains('"') }).Count -gt 0) { throw 'Unexpected quote in a script argument.' }
  $quoted = @('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File',('"' + $Path + '"'))
  foreach ($argument in $Arguments) { $quoted += ('"' + $argument + '"') }
  $process = Start-Process -FilePath $powershell -ArgumentList ($quoted -join ' ') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logRoot ($Label + '.stdout.log')) -RedirectStandardError (Join-Path $logRoot ($Label + '.stderr.log'))
  # Windows PowerShell can lose the exit status unless its Process handle is
  # retained before exit. Wait only for this command, never watcher descendants.
  $null = $process.Handle
  if (-not $process.WaitForExit(240000)) { throw "$Label timed out (PID $($process.Id)). See $logRoot. The client was not stopped." }
  $process.Refresh()
  $exitCode = $process.ExitCode
  if ($null -eq $exitCode) { throw "$Label exited but its status could not be read (PID $($process.Id)). See $logRoot" }
  if ($exitCode -ne 0) { throw "$Label failed (exit $exitCode). See $logRoot" }
  $process.Dispose()
}

function Start-LoneStarAdapter {
  # The unified engine owns base and detail styles. This one-shot only verifies
  # the result and retires the former, package-owned detail watcher.
  $state = Read-DreamSkinState -Path (Join-Path $stateRoot 'state.json')
  $client = Get-DreamSkinCodexInstallFromState -State $state
  $identity = Get-DreamSkinVerifiedCdpIdentity -Port $state.port -Codex $client
  if (-not $identity -or $identity.BrowserId -cne $state.browserId) { throw 'Current theme session identity did not verify.' }
  $expectedInjector=Join-Path $sourceWindows 'scripts\lone-star-runtime-api.mjs'
  if (-not (Test-DreamSkinPathEqual -Left $state.injectorPath -Right $expectedInjector)) { throw 'The unified NASA runtime was not started.' }
  $node = Get-DreamSkinNodeRuntime
  $adapter = Join-Path $PSScriptRoot 'lone-star-adapter.mjs'
  $output = @(& $node.Path $adapter health 2>&1)
  $healthExit=$LASTEXITCODE
  [System.IO.File]::WriteAllText((Join-Path $logRoot 'adapter.log'), ($output -join [Environment]::NewLine), $utf8)
  if ($healthExit -ne 0) { throw "Unified theme details did not verify. See $(Join-Path $logRoot 'adapter.log')" }
  $health=($output -join [Environment]::NewLine)|ConvertFrom-Json
  if (-not $health.pass -or $health.browserId -cne $state.browserId) { throw 'Unified style identity did not match.' }
  $watchPattern = '\s+"' + [regex]::Escape($adapter) + '"\s+watch\s*$'
  $retired=0
  foreach ($old in @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'")) {
    if ($old.CommandLine -and $old.CommandLine -match $watchPattern -and
        (Test-DreamSkinPathEqual -Left (Get-DreamSkinProcessExecutablePath -ProcessInfo $old) -Right $node.Path)) {
      Stop-Process -Id $old.ProcessId -Force -ErrorAction Stop
      $retired++
    }
  }
  $report.localDetailsApplied=$true
  $report.unifiedRuntime=$true
  $report.unifiedWatcherPid=$state.injectorPid
  $report.localDetailsWatcherPid=$null
  $report.retiredLegacyDetailWatchers=$retired
}

try {
  # Daily launch validates the package entries' path, size and reparse status
  # before reaching this manager. Full archive/installer hashes remain on all
  # install, check and repair actions where those payloads can be consumed.
  if ($Action -ne 'Launch') {
    Assert-LoneStarHash -Path $archive -Expected $expectedArchiveHash
    Assert-LoneStarHash -Path $installer -Expected $expectedInstallerHash
  }
  Assert-LoneStarEngine -Root $sourceWindows
  Save-LoneStarState
  if ($Action -eq 'Check') {
    if (Test-Path -LiteralPath (Join-Path $engineRoot 'VERSION') -PathType Leaf) {
      Assert-LoneStarEngine -Root $engineRoot -Installed
      $report.runtimeInstalled = $true
    }
    $report.status = 'package-integrity-checked'
    Write-Output 'Theme ZIP, official Setup.exe and selected runtime file hashes match.'
  } else {
    $existingSession=$null
    if ($Action -in @('Launch','Hot')) {
      . (Join-Path $taskRoot 'package-common.ps1')
      Import-PackageEngineHelpers $taskRoot
      if ($Action -eq 'Launch') { $existingSession=Get-PackageLaunchSession }
    }
    if ($Action -in @('Apply','Stage','Hot','Launch')) {
      if ($Action -in @('Apply','Stage','Launch')) {
        . (Join-Path $sourceWindows 'scripts\common-windows.ps1')
        $installs = @(Get-DreamSkinRegisteredCodexInstalls)
        if ($installs.Count -eq 0) { throw 'The official OpenAI.Codex Store package was not found for this Windows user.' }
        $running = @($installs | Where-Object { @(Get-DreamSkinCodexProcesses -Codex $_).Count -gt 0 })
        if ($running.Count -gt 0 -and -not $existingSession) {
          throw 'ChatGPT/Codex 仍在运行。请完全退出客户端（包括后台进程），然后从文件夹重新双击换肤入口。此入口不会关闭客户端。'
        }
      }
      if (-not (Test-Path -LiteralPath (Join-Path $engineRoot 'scripts\start-dream-skin.ps1') -PathType Leaf)) {
        if ($Action -in @('Launch','Hot')) { throw '换肤运行器缺失，请先运行安装主题.exe。' }
        $report.status = 'installing-runtime'
        Save-LoneStarState
        $setupLog = Join-Path $logRoot 'setup.log'
        $setupArgs = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="' + $setupLog + '"'))
        $setup = Start-Process -FilePath $installer -ArgumentList ($setupArgs -join ' ') -WindowStyle Hidden -PassThru
        $null = $setup.Handle
        if (-not $setup.WaitForExit(480000)) { throw "Official Dream Skin installer timed out (PID $($setup.Id)). See $setupLog. No client was stopped." }
        $setup.Refresh()
        $setupCode = $setup.ExitCode
        if ($null -eq $setupCode) { throw "Official Dream Skin installer exited without a readable status. See $setupLog" }
        if ($setupCode -ne 0) { throw "Official Dream Skin installer failed (exit $setupCode). See $setupLog" }
        $setup.Dispose()
      }
      Assert-LoneStarEngine -Root $engineRoot -Installed
      . (Join-Path $engineRoot 'scripts\common-windows.ps1')
      . (Join-Path $engineRoot 'scripts\theme-windows.ps1')
      if ($Action -eq 'Launch') {
        $paths=Get-DreamSkinThemePaths -StateRoot $stateRoot
        $saved=Join-Path $paths.Saved 'nasa-punk-device-light'
        $null=Read-DreamSkinTheme -ThemeDirectory $saved
        $imported=[pscustomobject]@{Path=$saved}
        $report.themeImported=$false
      } else {
        $report.status = 'importing-theme'
        Save-LoneStarState
        $lock = Enter-DreamSkinOperationLock
        try {
          $imported = Import-DreamSkinThemeZip -ArchivePath $archive -ExpectedArchiveBytes (Get-Item -LiteralPath $archive).Length -ExpectedArchiveSha256 $expectedArchiveHash
          [System.IO.File]::WriteAllText((Join-Path $logRoot 'import-result.json'), ($imported | ConvertTo-Json -Depth 10), $utf8)
          if ($Action -eq 'Hot') { Use-DreamSkinSavedTheme -ThemeDirectory $imported.Path | Out-Null }
        } finally { Exit-DreamSkinOperationLock -Mutex $lock }
        $report.themeImported = $true
      }
      $report.savedThemeDirectory = $imported.Path
      $report.runtimeInstalled = $true
      if ($Action -eq 'Stage') {
        $report.status = 'prepared-for-manual-application'
      } elseif ($Action -eq 'Hot') {
        $report.status = 'theme-files-updated-live'
        $null=Get-PackageLaunchSession
        Invoke-LoneStarScript -Path (Join-Path $sourceWindows 'scripts\start-nasa-session.ps1') -Arguments @() -Label 'start'
        Start-LoneStarAdapter
        $report.liveApplied = $true
      } else {
        $report.status = 'launching-theme-session'
        Save-LoneStarState
        if ($existingSession) {
          $report.reusedExistingSession=$true
          $report.windowFocused=Show-PackageVerifiedWindow $existingSession
          $report.clientLaunched=$false
          Invoke-LoneStarScript -Path (Join-Path $sourceWindows 'scripts\start-nasa-session.ps1') -Arguments @() -Label 'start'
          $report.runtimeRepaired=$true
        } else {
          Invoke-LoneStarScript -Path (Join-Path $sourceWindows 'scripts\start-nasa-session.ps1') -Arguments @('-SavedThemeDirectory', $imported.Path) -Label 'start'
          $report.reusedExistingSession=$false
          $report.clientLaunched=$true
        }
        $report.liveApplied = $true
        $report.status = 'applying-local-details'
        Save-LoneStarState
        Start-LoneStarAdapter
        $report.status = 'theme-and-details-applied'
      }
    } else { Assert-LoneStarEngine -Root $engineRoot -Installed }
    if ($Action -in @('Apply','Launch','Verify') -and -not $SkipVisualCheck) {
      $report.status = 'verifying-real-renderer'
      Save-LoneStarState
      $screenshot = Join-Path $logRoot 'client.png'
      Invoke-LoneStarScript -Path (Join-Path $sourceWindows 'scripts\verify-nasa-session.ps1') -Arguments @('-ScreenshotPath',$screenshot) -Label 'verify'
      if (-not (Test-Path -LiteralPath $screenshot -PathType Leaf)) { throw 'Verification did not save a real client screenshot.' }
      $report.liveVerified = $true
      $report.screenshot = $screenshot
      $report.status = 'renderer-verified-awaiting-visual-review'
      $null = Show-LoneStarMessage -Message "主题已应用，引擎检查通过。`r`n`r`n请确认侧栏、标题栏、输入框都正常，并回到这条聊天继续核对真实界面。检查截图及日志保存在：`r`n$logRoot"
    } elseif ($Action -eq 'Restore') {
      Invoke-LoneStarScript -Path (Join-Path $engineRoot 'scripts\restore-dream-skin.ps1') -Arguments @('-RestoreBaseTheme','-NoRelaunch') -Label 'restore'
      $report.status = 'restore-command-completed'
      $null = Show-LoneStarMessage -Message '恢复流程已运行。请核对重新打开后的原外观。'
    }
  }
} catch {
  $report.status = 'failed'
  $report.error = $_.Exception.Message
  $null = Show-LoneStarMessage -Message ("操作未完成：`r`n" + $_.Exception.Message + "`r`n`r`n检查日志：`r`n" + $logRoot + "`r`n`r`n此入口不会修改 WindowsApps 或官方 app.asar，也不会绕过系统安全拦截。") -ErrorMessage
  Save-LoneStarState
  exit 1
}
Save-LoneStarState
Write-Output ($report | ConvertTo-Json -Depth 10)
