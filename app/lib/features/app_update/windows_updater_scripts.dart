/// Windows self-update scripts. Keep ASCII so PowerShell 5.1 can parse them.
const windowsUpdaterScript = '''
param(
  [Parameter(Mandatory = \$true)][string]\$InstallDir,
  [Parameter(Mandatory = \$true)][string]\$SourceDir,
  [Parameter(Mandatory = \$true)][string]\$ExePath,
  [Parameter(Mandatory = \$true)][int]\$TargetPid,
  [switch]\$SkipLaunch
)
\$ErrorActionPreference = 'Stop'
\$log = Join-Path \$env:TEMP ("localsend_updater_" + \$TargetPid + ".log")
function Write-Log([string]\$msg) {
  \$line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), \$msg)
  Add-Content -LiteralPath \$log -Value \$line -Encoding UTF8
}
function Get-CanonicalPath([string]\$Path) {
  return (Get-Item -LiteralPath \$Path).FullName.TrimEnd('\\')
}
function Get-RelativePathFrom([string]\$Root, [string]\$FullPath) {
  \$rootUri = New-Object System.Uri ((\$Root.TrimEnd('\\') + '\\'))
  \$fileUri = New-Object System.Uri \$FullPath
  if (-not \$rootUri.IsBaseOf(\$fileUri)) {
    throw "File not under source dir: \$FullPath"
  }
  return [Uri]::UnescapeDataString(\$rootUri.MakeRelativeUri(\$fileUri).ToString()).Replace('/', '\\')
}
function Copy-FileWithRetry([string]\$From, [string]\$To) {
  \$attempt = 0
  while (\$true) {
    try {
      Copy-Item -LiteralPath \$From -Destination \$To -Force
      return
    } catch {
      \$attempt++
      if (\$attempt -ge 10) { throw }
      Start-Sleep -Milliseconds 500
    }
  }
}
\$failed = \$false
try {
  Write-Log "Waiting for process exit PID=\$TargetPid"
  \$deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt \$deadline) {
    if (-not (Get-Process -Id \$TargetPid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep -Seconds 2
  \$InstallDir = Get-CanonicalPath \$InstallDir
  \$SourceDir = Get-CanonicalPath \$SourceDir
  \$ExePath = (Get-Item -LiteralPath \$ExePath).FullName
  Write-Log "InstallDir=\$InstallDir"
  Write-Log "SourceDir=\$SourceDir"
  \$n = 0
  Get-ChildItem -LiteralPath \$SourceDir -Recurse -File | ForEach-Object {
    \$rel = Get-RelativePathFrom \$SourceDir \$_.FullName
    if ([string]::IsNullOrWhiteSpace(\$rel)) { return }
    \$dest = Join-Path \$InstallDir \$rel
    \$destParent = Split-Path -Parent \$dest
    if (-not (Test-Path -LiteralPath \$destParent)) {
      New-Item -ItemType Directory -Path \$destParent -Force | Out-Null
    }
    Copy-FileWithRetry \$_.FullName \$dest
    \$n++
  }
  if (\$n -le 0) { throw "No files copied from source dir" }
  if (-not (Test-Path -LiteralPath \$ExePath)) { throw "Exe missing after copy: \$ExePath" }
  Write-Log "Copied \$n files"
  if (\$SkipLaunch) { Write-Log "SkipLaunch" }
  Remove-Item -LiteralPath \$SourceDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Write-Log ("Update failed: " + \$_.Exception.Message)
  \$failed = \$true
} finally {
  Remove-Item -LiteralPath \$PSCommandPath -Force -ErrorAction SilentlyContinue
}
if (\$failed) { exit 1 }
''';

const windowsRelaunchScript = '''
param(
  [Parameter(Mandatory = \$true)][string]\$InstallDir,
  [Parameter(Mandatory = \$true)][string]\$ExePath,
  [Parameter(Mandatory = \$true)][int]\$TargetPid
)
\$ErrorActionPreference = 'Stop'
\$log = Join-Path \$env:TEMP ("localsend_relaunch_" + \$TargetPid + ".log")
\$updLog = Join-Path \$env:TEMP ("localsend_updater_" + \$TargetPid + ".log")
function Write-Log([string]\$msg) {
  \$line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), \$msg)
  Add-Content -LiteralPath \$log -Value \$line -Encoding UTF8
}
function Start-LocalSendApp([string]\$Exe, [string]\$Dir) {
  if (-not (Test-Path -LiteralPath \$Exe)) { return }
  \$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    \$_.Path -and \$_.Path.Equals(\$Exe, [StringComparison]::OrdinalIgnoreCase)
  })
  if (\$running.Count -gt 0) {
    Write-Log "Already running"
    return
  }
  Write-Log "Launch \$Exe cwd=\$Dir"
  \$d = \$Dir.TrimEnd('\\')
  \$line = '/c start "" /D "' + \$d + '" "' + \$Exe + '"'
  Start-Process -FilePath 'cmd.exe' -ArgumentList \$line -WindowStyle Hidden
}
try {
  Write-Log "Waiting for process exit PID=\$TargetPid"
  \$deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt \$deadline) {
    if (-not (Get-Process -Id \$TargetPid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 400
  }
  \$deadline = (Get-Date).AddSeconds(180)
  while ((Get-Date) -lt \$deadline) {
    if (Test-Path -LiteralPath \$updLog) {
      \$text = Get-Content -LiteralPath \$updLog -Raw -ErrorAction SilentlyContinue
      if (\$text -and (\$text -match 'Copied \\d+ files' -or \$text -match 'Update failed' -or \$text -match 'SkipLaunch')) {
        break
      }
    }
    Start-Sleep -Milliseconds 400
  }
  Start-Sleep -Seconds 1
  Start-LocalSendApp \$ExePath \$InstallDir
  Write-Log "Done"
} catch {
  Write-Log ("Relaunch failed: " + \$_.Exception.Message)
  try { Start-LocalSendApp \$ExePath \$InstallDir } catch { }
} finally {
  Remove-Item -LiteralPath \$PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
