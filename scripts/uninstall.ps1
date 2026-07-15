$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$meterPath = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'src\CodexMeter.ps1')).Path
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Meter.lnk'

Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue

$escapedMeterPath = [regex]::Escape($meterPath)
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match ('(?i)(?:^|\s|")' + $escapedMeterPath + '(?:"|\s|$)') } |
    ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null }

Write-Output ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5Y246L295oiQ5Yqf77yM6K6+572u5bey5L+d55WZ44CC')))
