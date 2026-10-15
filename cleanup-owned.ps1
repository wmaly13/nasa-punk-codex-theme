[CmdletBinding()]
param([int]$WaitForPid=0,[Parameter(Mandatory=$true)][string]$InstanceId,[Parameter(Mandatory=$true)][string]$ResultName)
$ErrorActionPreference='Stop'
$local=[IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
$program=[IO.Path]::GetFullPath((Join-Path $local 'Programs\NASA-PunkTheme')).TrimEnd('\')
$state=[IO.Path]::GetFullPath((Join-Path $local 'NASA-PunkTheme')).TrimEnd('\')
$temporary=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$mutex=$null;$locked=$false
if ($InstanceId -notmatch '^[0-9a-f]{32}$' -or $ResultName -notmatch '^nasa-cleanup-[0-9a-f]{32}\.json$') { throw 'Invalid cleanup identity.' }
$logDir=Join-Path $local 'CodexDreamSkin\logs'
New-Item -ItemType Directory -Path $logDir -Force|Out-Null
$resultPath=Join-Path $logDir $ResultName
function Write-CleanupResult {
  param([string]$Status,[string]$ErrorMessage)
  $result=[ordered]@{packageId='NASA-PunkTheme';instanceId=$InstanceId;status=$Status;error=$ErrorMessage;completedAt=(Get-Date).ToString('o')}
  [IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
function Remove-OwnedFolder {
  param([string]$Target,[string]$ExactExpected)
  $full=[IO.Path]::GetFullPath($Target).TrimEnd('\')
  if ($full -ine $ExactExpected -or -not $full.StartsWith($local+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid cleanup target.' }
  if (-not (Test-Path -LiteralPath $full)) { return }
  $current=$full
  while ($current) {
    $item=Get-Item -LiteralPath $current -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing reparse cleanup.' }
    if ($current -ieq $local) { break }
    $current=[IO.Path]::GetDirectoryName($current)
  }
  foreach ($item in Get-ChildItem -LiteralPath $full -Recurse -Force) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing reparse contents.' }
  }
  Remove-Item -LiteralPath $full -Recurse -Force
}
try {
  Write-CleanupResult 'waiting-for-launcher' ''
  if ($WaitForPid -gt 0) {
    $deadline=(Get-Date).AddHours(1)
    while (Get-Process -Id $WaitForPid -ErrorAction SilentlyContinue) {
      if ((Get-Date) -gt $deadline) { throw 'Launcher is still open; package folders were preserved.' }
      Start-Sleep -Seconds 2
    }
  }
  $mutex=[Threading.Mutex]::new($false,'Local\NASAPunkTheme-Package')
  $locked=$mutex.WaitOne(10000)
  if (-not $locked) { throw 'Another package operation is active; folders were preserved.' }
  $recordPath=Join-Path $state 'installation.json'
  if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) { throw 'Missing ownership record.' }
  $record=[IO.File]::ReadAllText($recordPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
  if ($record.packageId -cne 'NASA-PunkTheme' -or $record.programPath -ine $program -or $record.instanceId -cne $InstanceId -or -not $record.cleanupPending) { throw 'Ownership record mismatch.' }
  Remove-OwnedFolder $program $program
  Remove-OwnedFolder $state $state
  Write-CleanupResult 'complete' ''
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  Write-CleanupResult 'failed' $_.Exception.Message
  if (Test-Path -LiteralPath (Join-Path $state 'installation.json')) {
    try {
      $retained=[IO.File]::ReadAllText((Join-Path $state 'installation.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
      if ($retained.instanceId -ceq $InstanceId) {
        $retained.cleanupPending=$false
        [IO.File]::WriteAllText((Join-Path $state 'installation.json'),($retained|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
      }
    } catch {}
  }
  Add-Type -AssemblyName System.Windows.Forms
  $null=[Windows.Forms.MessageBox]::Show(('外观已经恢复，但程序文件清理未完成。可从下载包重新运行卸载入口。'+[Environment]::NewLine+'详情：'+$resultPath),'NASA 朋克主题',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  if ($mutex) { $mutex.Dispose() }
  # Only the unique temporary folder created by this uninstaller is eligible.
  if ($temporary.StartsWith($tempBase+'\',[StringComparison]::OrdinalIgnoreCase) -and
      [IO.Path]::GetFileName($temporary) -match '^NASAPunk-Cleanup-[0-9a-f]{32}$') {
    $item=Get-Item -LiteralPath $temporary -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
      Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
