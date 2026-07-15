$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$meterPath = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'src\CodexMeter.ps1')).Path
$startupPath = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupPath 'Codex Meter.lnk'
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "{0}"' -f $meterPath

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $projectRoot
$shortcut.Save()

$escapedMeterPath = [regex]::Escape($meterPath)
$meterIsRunning = @(
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match ('(?i)(?:^|\s|")' + $escapedMeterPath + '(?:"|\s|$)') }
).Count -gt 0

if (-not $meterIsRunning) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden
}

Write-Output ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5a6J6KOF5oiQ5Yqf77yM5bey5Yqg5YWl5byA5py65ZCv5Yqo44CC')))
