$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$script:PackageId = 'NASA-PunkTheme'
$script:ThemeId = 'nasa-punk-device-light'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
if ($PSVersionTable.PSVersion.Major -lt 6) {
  $documents=[Environment]::GetFolderPath('MyDocuments',[Environment+SpecialFolderOption]::DoNotVerify)
  if (-not $documents) { $documents=Join-Path $env:USERPROFILE 'Documents' }
  $env:PSModulePath=@((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),(Join-Path $documents 'WindowsPowerShell\Modules')) -join ';'
}

function Get-PackageChildPath {
  param([string]$Root,[string]$Relative)
  if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
      $Relative -match '(^|[\\/])\.\.([\\/]|$)|[:*?"<>|]') { throw 'Invalid package path.' }
  $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  $target = [IO.Path]::GetFullPath((Join-Path $base $Relative))
  if (-not $target.StartsWith($base + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Package path escaped its folder.' }
  return $target
}
function Assert-NoPackageReparse {
  param([string]$Path)
  $current = [IO.Path]::GetFullPath($Path)
  while ($current) {
    if (Test-Path -LiteralPath $current) {
      $item=Get-Item -LiteralPath $current -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse path is not supported: $current" }
    }
    $parent=[IO.Path]::GetDirectoryName($current.TrimEnd('\'))
    if (-not $parent -or $parent -eq $current) { break }
    $current=$parent
  }
}
function Read-PackageManifest {
  param([string]$PackageRoot,[ValidateSet('FullIntegrity','DailyLaunch')][string]$Profile='FullIntegrity')
  if ($Profile -eq 'DailyLaunch') {
    $caller=Get-PSCallStack | Select-Object -Skip 1 -First 1
    $expectedCaller=Get-PackageChildPath $PackageRoot 'files\start-package.ps1'
    if (-not $caller -or -not $caller.ScriptName -or
        [IO.Path]::GetFullPath($caller.ScriptName) -ine $expectedCaller) {
      throw 'DailyLaunch manifest verification is reserved for the package start entry point.'
    }
  }
  $manifestPath=Get-PackageChildPath $PackageRoot 'files\package-manifest.json'
  Assert-NoPackageReparse $manifestPath
  $manifest=[IO.File]::ReadAllText($manifestPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
  if ($manifest.schemaVersion -ne 1 -or $manifest.packageId -cne $script:PackageId -or $manifest.files.Count -gt 200) { throw 'Invalid package manifest.' }
  foreach ($entry in $manifest.files) {
    $file=Get-PackageChildPath $PackageRoot $entry.path
    Assert-NoPackageReparse $file
    $item=Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
    $skipDailyHash = $Profile -eq 'DailyLaunch' -and (
      $entry.path -match '(?i)(^|[\\/])CodexDreamSkin-Setup-v1\.5\.20\.exe$' -or
      $entry.path -match '(?i)(^|[\\/])NASA-Punk-Theme\.zip$')
    if (-not $item -or $item.PSIsContainer -or $item.Length -ne $entry.bytes -or
        (-not $skipDailyHash -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256)) {
      throw "程序文件缺失或校验失败：$($entry.path)。请重新完整解压安装包。"
    }
  }
  return $manifest
}
function Get-PackageLocations {
  $local=[IO.Path]::GetFullPath($env:LOCALAPPDATA)
  if ($local -notmatch '^[A-Za-z]:\\' ) { throw 'A local Windows user profile is required.' }
  $program=Get-PackageChildPath (Join-Path $local 'Programs') $script:PackageId
  $state=Get-PackageChildPath $local $script:PackageId
  Assert-NoPackageReparse $program
  Assert-NoPackageReparse $state
  return [pscustomobject]@{Program=$program;State=$state;Record=(Join-Path $state 'installation.json');Runtime=(Join-Path $local 'CodexDreamSkin');Engine=(Join-Path $local 'CodexDreamSkin\engine')}
}
function Import-PackageEngineHelpers {
  param([string]$FilesRoot)
  if ($PSVersionTable.PSVersion.Major -lt 6) {
    $documents=[Environment]::GetFolderPath('MyDocuments',[Environment+SpecialFolderOption]::DoNotVerify)
    if (-not $documents) { $documents=Join-Path $env:USERPROFILE 'Documents' }
    $env:PSModulePath=@((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),(Join-Path $documents 'WindowsPowerShell\Modules')) -join ';'
  }
  $scripts=Join-Path $FilesRoot '.support\upstream\Codex-Dream-Skin-1.5.20\windows\scripts'
  . (Join-Path $scripts 'common-windows.ps1')
  . (Join-Path $scripts 'theme-windows.ps1')
  foreach ($function in Get-ChildItem Function:\ | Where-Object { $_.Name -match 'DreamSkin' }) {
    Set-Item -Path ('Function:global:'+$function.Name) -Value $function.ScriptBlock
  }
  foreach ($name in @('Get-DreamSkinThemeSemanticFingerprint','Read-DreamSkinTheme','Get-DreamSkinThemePaths','Resolve-DreamSkinConfigPaths','Restore-DreamSkinBaseTheme','Set-DreamSkinActiveTheme')) {
    if (-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) { throw "运行器接口缺失：$name。尚未修改安装状态。" }
  }
}
function Assert-PackageClientClosed {
  param([switch]$RequireInstall)
  $installs=@(Get-DreamSkinRegisteredCodexInstalls)
  if ($RequireInstall -and $installs.Count -eq 0) { throw '未找到受支持的 Windows 版 ChatGPT/Codex。请先安装并打开官方客户端一次。' }
  foreach ($client in $installs) {
    if (@(Get-DreamSkinCodexProcesses -Codex $client).Count -gt 0) {
      $error=[InvalidOperationException]::new('ChatGPT/Codex 仍在运行，请完全退出后再运行入口。程序不会替你关闭客户端。')
      $error.Data['UserActionRequired']=$true
      throw $error
    }
  }
}
function Get-PackageLaunchSession {
  $installs=@(Get-DreamSkinRegisteredCodexInstalls)
  if ($installs.Count -eq 0) { throw '未找到受支持的 ChatGPT/Codex 客户端。' }
  $running=@($installs|Where-Object { @(Get-DreamSkinCodexProcesses -Codex $_).Count -gt 0 })
  if ($running.Count -eq 0) { return $null }
  $locations=Get-PackageLocations
  $paths=Get-DreamSkinThemePaths -StateRoot $locations.Runtime
  $state=Read-DreamSkinState -Path $paths.State
  $live=if ($state) { Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port $state.port } else { $null }
  $active=if (Test-Path -LiteralPath (Join-Path $paths.Active 'theme.json')) { Read-DreamSkinTheme -ThemeDirectory $paths.Active -SkipImageMetadata } else { $null }
  $config=Resolve-DreamSkinConfigPaths -StateRoot $locations.Runtime -AllowMissingConfig
  if ($live -and $live.Identity.BrowserId -ceq $state.browserId -and $active -and $active.Theme.id -ceq $script:ThemeId -and -not (Test-DreamSkinPendingAppearanceTransaction -BackupPath $config.BackupPath)) {
    $owners=@(Get-DreamSkinPortListeners -Port $state.port|Select-Object -ExpandProperty OwningProcess -Unique)
    if ($owners.Count -eq 1) { return [pscustomobject]@{Port=$state.port;BrowserId=$state.browserId;OwnerPid=[int]$owners[0];Codex=$live.Codex} }
  }
  $error=[InvalidOperationException]::new('已有原生客户端或无法验证的主题会话正在运行。请手动退出相关窗口后再启动；程序不会另外打开或关闭客户端。')
  $error.Data['UserActionRequired']=$true
  throw $error
}
function Show-PackageVerifiedWindow {
  param([object]$Session)
  $live=Get-DreamSkinVerifiedCdpIdentity -Port $Session.Port -Codex $Session.Codex
  if (-not $live -or $live.BrowserId -cne $Session.BrowserId) { throw '窗口会话已改变，未切换窗口。' }
  $process=Get-Process -Id $Session.OwnerPid -ErrorAction Stop
  if (-not $process.Path -or -not (Test-DreamSkinPathEqual -Left $process.Path -Right $Session.Codex.Executable)) { throw '窗口进程身份已改变。' }
  if ('NasaPunk.WindowFocus' -as [type]) { }
  else {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace NasaPunk {
  public static class WindowFocus {
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int n);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    public static bool Show(IntPtr window, uint expectedPid) {
      if (window == IntPtr.Zero) return false;
      uint owner; GetWindowThreadProcessId(window, out owner);
      if (owner != expectedPid) return false;
      if (IsIconic(window)) ShowWindowAsync(window, 9);
      return SetForegroundWindow(window);
    }
  }
}
'@
  }
  return [NasaPunk.WindowFocus]::Show($process.MainWindowHandle,[uint32]$Session.OwnerPid)
}
function Get-PackageUnifiedRuntimeHealth {
  param([string]$FilesRoot,[object]$Session)
  try {
    $locations=Get-PackageLocations
    $state=Read-DreamSkinState -Path (Join-Path $locations.Runtime 'state.json')
    $injector=Get-PackageChildPath $FilesRoot '.support\upstream\Codex-Dream-Skin-1.5.20\windows\scripts\lone-star-runtime-api.mjs'
    if (-not $state -or $state.browserId -cne $Session.BrowserId -or $state.port -ne $Session.Port -or
        -not (Test-DreamSkinPathEqual -Left $state.injectorPath -Right $injector) -or
        -not $state.injectorPid -or -not $state.injectorStartedAt -or
        (Test-DreamSkinPaused -StateRoot $locations.Runtime)) { return $false }
    $node=Get-DreamSkinValidatedNodeRuntime -Path (Join-Path $locations.Engine 'runtime\node\node.exe')
    if (-not (Test-DreamSkinPathEqual -Left $state.nodePath -Right $node.Path)) { return $false }
    $watcher=Get-CimInstance Win32_Process -Filter "ProcessId = $($state.injectorPid)" -ErrorAction Stop
    $handle=Get-Process -Id $state.injectorPid -ErrorAction Stop
    if (-not $watcher -or [int]$watcher.ProcessId -ne [int]$state.injectorPid -or $handle.HasExited -or
        -not (Test-DreamSkinPathEqual -Left (Get-DreamSkinProcessExecutablePath -ProcessInfo $watcher) -Right $node.Path) -or
        $handle.StartTime.ToUniversalTime().ToString('o') -cne $state.injectorStartedAt) { return $false }
    foreach ($token in @($injector,'--watch','--port',"$($Session.Port)",'--browser-id',$Session.BrowserId)) {
      if (-not (Test-DreamSkinCommandLineToken -CommandLine $watcher.CommandLine -Token $token)) { return $false }
    }
    $adapter=Get-PackageChildPath $FilesRoot '.support\lone-star-adapter.mjs'
    $legacyPattern='\s+"'+[regex]::Escape($adapter)+'"\s+watch\s*$'
    $matchingWatchers=0
    foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'")) {
      if (-not $candidate.CommandLine) { continue }
      if ($candidate.CommandLine -and $candidate.CommandLine -match $legacyPattern) { return $false }
      if ((Test-DreamSkinCommandLineToken -CommandLine $candidate.CommandLine -Token $injector) -and
          (Test-DreamSkinCommandLineToken -CommandLine $candidate.CommandLine -Token '--watch') -and
          (Test-DreamSkinCommandLineToken -CommandLine $candidate.CommandLine -Token $Session.BrowserId)) { $matchingWatchers++ }
    }
    if ($matchingWatchers -ne 1) { return $false }
    $result=Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList @($adapter,'health') -DiscardStderr
    if ($result.ExitCode -ne 0) { return $false }
    $health=($result.Output -join [Environment]::NewLine)|ConvertFrom-Json
    return ($health.pass -is [bool] -and $health.pass -and $health.browserId -ceq $Session.BrowserId)
  } catch { return $false }
}
function Write-PackageJson {
  param([string]$Path,[object]$Value)
  Assert-NoPackageReparse $Path
  $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  try {
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 12),$script:Utf8)
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temporary,$Path) }
  } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Read-PackageRecord {
  param([object]$Locations)
  Assert-NoPackageReparse $Locations.Record
  $record=[IO.File]::ReadAllText($Locations.Record,[Text.Encoding]::UTF8)|ConvertFrom-Json
  if ($record.packageId -cne $script:PackageId -or $record.programPath -ine $Locations.Program -or $record.instanceId -notmatch '^[0-9a-f]{32}$') { throw '安装记录与目标不一致。' }
  # Keep the original baseline when repairing a failed older installation.
  foreach ($entry in @{phase='legacy';ownsAppearance=$true;ownedActiveFingerprint=$null;ownedActiveThemeId=$null;ownedImageHash=$null;lastLaunch=$null}.GetEnumerator()) {
    if (-not $record.PSObject.Properties[$entry.Key]) { $record|Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value }
  }
  return $record
}
function Test-PackageBundledActiveTheme {
  param([string]$ActiveDirectory,[string]$FilesRoot)
  # Legacy records lack a post-launch fingerprint. Establish exact known
  # content, allowing only the upstream-generated image filename to differ.
  $active=Read-DreamSkinTheme -ThemeDirectory $ActiveDirectory
  $bundled=Read-DreamSkinTheme -ThemeDirectory (Join-Path $FilesRoot 'lone-star-theme')
  if ($active.Theme.id -cne $script:ThemeId -or (Get-FileHash $active.ImagePath).Hash -cne (Get-FileHash $bundled.ImagePath).Hash) { return $false }
  $activeCss=Join-Path $ActiveDirectory 'theme.css'
  $bundleCss=Join-Path $FilesRoot 'lone-star-theme\theme.css'
  if (-not (Test-Path -LiteralPath $activeCss) -or (Get-FileHash $activeCss).Hash -cne (Get-FileHash $bundleCss).Hash) { return $false }
  $active.Theme.image='package-image';$bundled.Theme.image='package-image'
  return ((ConvertTo-PackageCanonicalObject $active.Theme)|ConvertTo-Json -Depth 12 -Compress) -ceq ((ConvertTo-PackageCanonicalObject $bundled.Theme)|ConvertTo-Json -Depth 12 -Compress)
}
function ConvertTo-PackageCanonicalObject {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [Collections.IDictionary]) {
    $result=[ordered]@{}
    foreach ($key in @($Value.Keys|Sort-Object)) { $result[$key]=ConvertTo-PackageCanonicalObject $Value[$key] }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result=[ordered]@{}
    foreach ($property in @($Value.PSObject.Properties|Sort-Object Name)) { $result[$property.Name]=ConvertTo-PackageCanonicalObject $property.Value }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $result=@(foreach ($item in $Value) { ConvertTo-PackageCanonicalObject $item })
    Write-Output -NoEnumerate $result
    return
  }
  return $Value
}
function Get-PackageShortcutPaths {
  $desktop=[Environment]::GetFolderPath('Desktop',[Environment+SpecialFolderOption]::DoNotVerify)
  $menu=Join-Path ([Environment]::GetFolderPath('Programs',[Environment+SpecialFolderOption]::DoNotVerify)) 'NASA 朋克主题'
  return @(
    [pscustomobject]@{Path=(Join-Path $desktop 'ChatGPT · NASA 朋克.lnk');Kind='start'},
    [pscustomobject]@{Path=(Join-Path $menu 'ChatGPT · NASA 朋克.lnk');Kind='start'},
    [pscustomobject]@{Path=(Join-Path $menu '卸载 NASA 朋克主题.lnk');Kind='uninstall'}
  )
}
function Get-PackageShortcutTarget {
  param([string]$Path)
  Assert-NoPackageReparse $Path
  $shell=New-Object -ComObject WScript.Shell
  return $shell.CreateShortcut($Path).TargetPath
}
function Set-PackageShortcut {
  param([string]$Path,[string]$Target,[string]$WorkingDirectory,[string]$Description,[string]$IconPath)
  Assert-NoPackageReparse $Path
  New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force|Out-Null
  $shell=New-Object -ComObject WScript.Shell
  $shortcut=$shell.CreateShortcut($Path)
  $shortcut.TargetPath=$Target;$shortcut.WorkingDirectory=$WorkingDirectory;$shortcut.Description=$Description
  if ($IconPath) { $shortcut.IconLocation=$IconPath+',0' }
  $shortcut.Save()
  if ((Get-PackageShortcutTarget $Path) -ine $Target) { throw "启动入口保存校验失败：$Path" }
  if ($IconPath -and $shell.CreateShortcut($Path).IconLocation -ine ($IconPath+',0')) { throw "启动图标保存校验失败：$Path" }
}
function Get-PackageChatGPTIcon {
  param([string]$ProgramRoot)
  if ([IO.Path]::GetFullPath($ProgramRoot).TrimEnd('\') -ine (Get-PackageLocations).Program.TrimEnd('\')) { throw '图标目标不属于已安装主题目录。' }
  $client=Get-DreamSkinCodexInstall
  $iconPath=Get-PackageChildPath $ProgramRoot 'files\.support\chatgpt.ico'
  Assert-NoPackageReparse $iconPath
  New-Item -ItemType Directory -Path (Split-Path -Parent $iconPath) -Force|Out-Null
  Add-Type -AssemblyName System.Drawing
  $icon=[Drawing.Icon]::ExtractAssociatedIcon($client.Executable)
  if (-not $icon) { throw '无法读取官方 ChatGPT 图标。' }
  $temporary=$iconPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  try {
    $stream=[IO.File]::Create($temporary)
    try { $icon.Save($stream) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $iconPath) { [IO.File]::Replace($temporary,$iconPath,[NullString]::Value) }
    else { [IO.File]::Move($temporary,$iconPath) }
  } finally { $icon.Dispose();if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
  return $iconPath
}
function Register-PackageShortcuts {
  param([string]$ProgramRoot)
  $startIcon=Get-PackageChatGPTIcon $ProgramRoot
  foreach ($entry in Get-PackageShortcutPaths) {
    if ((Test-Path -LiteralPath $entry.Path) -and -not (Get-PackageShortcutTarget $entry.Path).StartsWith($ProgramRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "同名快捷方式属于其他程序，已保留：$($entry.Path)" }
    $target=if ($entry.Kind -eq 'start') { Join-Path $ProgramRoot 'files\ChatGPT-NASA.exe' } else { Join-Path $ProgramRoot '卸载主题.exe' }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "启动程序缺失：$target" }
    $icon=if ($entry.Kind -eq 'start') { $startIcon } else { $null }
    Set-PackageShortcut -Path $entry.Path -Target $target -WorkingDirectory $ProgramRoot -Description 'NASA 朋克主题：启动时自动加载主题；可将此入口固定到任务栏' -IconPath $icon
  }
}
function Remove-PackageShortcuts {
  param([string]$ProgramRoot)
  $entries=@(Get-PackageShortcutPaths)
  $desktop=Split-Path -Parent $entries[0].Path
  foreach ($name in @('NASA 朋克启动.lnk','NASA 朋克卸载.lnk','Lone Star NASA 换肤.lnk')) { $entries += [pscustomobject]@{Path=(Join-Path $desktop $name)} }
  foreach ($entry in $entries) {
    if ((Test-Path -LiteralPath $entry.Path) -and (Get-PackageShortcutTarget $entry.Path).StartsWith($ProgramRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $entry.Path -Force }
  }
  $menu=Split-Path -Parent $entries[1].Path
  if ((Test-Path -LiteralPath $menu) -and @(Get-ChildItem -LiteralPath $menu -Force).Count -eq 0) { Remove-Item -LiteralPath $menu -Force }
}
function Assert-PackageWorkerIdle {
  param([string]$FilesRoot)
  $manager=Get-PackageChildPath $FilesRoot '.support\manage-lone-star.ps1'
  $pattern='-File\s+"'+[regex]::Escape($manager)+'"(?:\s|$)'
  $workers=@(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $pattern })
  if ($workers.Count -gt 0) { throw '上一轮主题处理仍在运行。请等待它结束；未开始新的操作。' }
  $setup=Get-PackageChildPath $FilesRoot '.support\CodexDreamSkin-Setup-v1.5.20.exe'
  if (@(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $setup }).Count -gt 0) { throw '上一轮运行器安装仍在进行。请等待它结束；未开始新的操作。' }
}
function Invoke-PackageRuntimeUninstaller {
  param([string]$Path)
  $process=Start-Process -FilePath $Path -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -WindowStyle Hidden -PassThru
  $null=$process.Handle
  try {
    if (-not $process.WaitForExit(480000)) { throw '运行器卸载超过等待时限，已保留主题记录；请查看运行器卸载日志。' }
    $process.Refresh()
    if ($null -eq $process.ExitCode -or $process.ExitCode -ne 0) { throw ('运行器卸载未完成（退出代码 '+$process.ExitCode+'），已保留记录以便重试。') }
  } finally { $process.Dispose() }
}
function Start-PackageCleanup {
  param([string]$PowerShell,[string]$Arguments)
  $null=Start-Process -FilePath $PowerShell -ArgumentList $Arguments -WindowStyle Hidden -PassThru
}
function Stop-PackageAdapter {
  param([string]$ProgramRoot)
  $adapter=Get-PackageChildPath $ProgramRoot 'files\.support\lone-star-adapter.mjs'
  $pattern='\s+"' + [regex]::Escape($adapter) + '"\s+watch\s*$'
  foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine -match $pattern })) {
    Stop-Process -Id $process.ProcessId -Force
  }
}
function Remove-PackageTree {
  param([string]$Target,[string]$AllowedRoot)
  $full=[IO.Path]::GetFullPath($Target).TrimEnd('\')
  $root=[IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')
  if ($full -ne $root -and -not $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Delete target outside owned folder.' }
  if (-not (Test-Path -LiteralPath $full)) { return }
  Assert-NoPackageReparse $full
  foreach ($item in Get-ChildItem -LiteralPath $full -Recurse -Force) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing recursive removal of reparse contents.' }
  }
  Remove-Item -LiteralPath $full -Recurse -Force
}
function Invoke-PackageManager {
  param([string]$FilesRoot,[string]$LogRoot,[ValidateSet('Stage','Launch')][string]$Action)
  $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $manager=Get-PackageChildPath $FilesRoot '.support\manage-lone-star.ps1'
  if ($manager.Contains('"')) { throw 'Invalid program path.' }
  $arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "'+$manager+'" -Action '+$Action+' -NoUI -SkipVisualCheck'
  $resultName=if ($Action -eq 'Stage') { 'prepared-theme.json' } else { 'last-run.json' }
  $process=Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $LogRoot 'manager.stdout.log') -RedirectStandardError (Join-Path $LogRoot 'manager.stderr.log')
  $null=$process.Handle
  $elapsed=[Diagnostics.Stopwatch]::StartNew()
  $lastStage=''
  while (-not $process.WaitForExit(500)) {
    $resultPath=Join-Path (Join-Path $FilesRoot '.support') $resultName
    if (Test-Path -LiteralPath $resultPath) {
      try {
        $result=[IO.File]::ReadAllText($resultPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
        if ($result.status -and $result.status -ne $lastStage) {
          $lastStage=$result.status
          $label=switch ($lastStage) {
            'installing-runtime' {'正在安装换肤运行器'}
            'importing-theme' {'正在导入主题文件'}
            'launching-theme-session' {'正在打开客户端'}
            'applying-local-details' {'正在加载彩带和控件细节'}
            'theme-and-details-applied' {'主题与细节已加载'}
            'prepared-for-manual-application' {'主题文件已导入，正在创建启动入口'}
            default {'正在处理主题'}
          }
          Write-Output ('NASA-PACKAGE-STAGE:'+ $label)
        }
      } catch { }
    }
    if ($elapsed.Elapsed.TotalMinutes -ge 10) { throw ('主题处理超过等待时限（管理进程 '+$process.Id+'）。请查看 '+$LogRoot+'。客户端保持运行，请勿重复安装，先检查管理进程是否结束。') }
  }
  $process.Refresh()
  $exitCode=$process.ExitCode
  if ($null -eq $exitCode) { throw ('管理进程已结束，但无法读取退出状态。请查看 '+$LogRoot) }
  $process.Dispose()
  if ($exitCode -ne 0) {
    $resultPath=Join-Path (Join-Path $FilesRoot '.support') $resultName
    $detail=''
    if (Test-Path -LiteralPath $resultPath) {
      try { $result=[IO.File]::ReadAllText($resultPath,[Text.Encoding]::UTF8)|ConvertFrom-Json; if ($result.error) {$detail=' 原因：'+$result.error} } catch { }
    }
    throw ('主题加载未完成（退出代码 '+$exitCode+'）。'+$detail+' 请查看 '+$LogRoot+'。已保留安装备份。')
  }
  $resultPath=Join-Path (Join-Path $FilesRoot '.support') $resultName
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw '处理进程没有保存完成记录，无法确认成功。' }
  $result=[IO.File]::ReadAllText($resultPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
  $expectedStatus=if ($Action -eq 'Stage') { 'prepared-for-manual-application' } else { 'theme-and-details-applied' }
  if ($result.action -cne $Action -or $result.themeId -cne $script:ThemeId -or $result.status -cne $expectedStatus) { throw ('处理记录未达到完成状态：'+$result.status+'。请查看 '+$LogRoot) }
}
