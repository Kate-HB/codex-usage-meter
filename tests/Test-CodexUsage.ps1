$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\CodexUsage.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\CodexSettings.psm1') -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message. Expected: $Expected; Actual: $Actual"
    }
}

$meterXamlPath = Join-Path $PSScriptRoot '..\src\CodexMeter.xaml'
Assert-Equal $true (Test-Path -LiteralPath $meterXamlPath -PathType Leaf) 'Meter XAML exists'
[xml]$meterXaml = Get-Content -LiteralPath $meterXamlPath -Raw -Encoding UTF8
$xamlNamespace = New-Object Xml.XmlNamespaceManager($meterXaml.NameTable)
$xamlNamespace.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')

foreach ($controlName in @('WeeklyBar', 'WeeklyValue', 'ResetValue', 'ContextBar', 'ContextValue', 'FreshnessValue', 'ZoomValue')) {
    $namedControl = $meterXaml.SelectSingleNode("//*[@x:Name='$controlName']", $xamlNamespace)
    Assert-Equal $true ($null -ne $namedControl) "XAML contains $controlName"
}

Assert-Equal 'True' $meterXaml.Window.Topmost 'Meter stays topmost'
Assert-Equal 'False' $meterXaml.Window.ShowInTaskbar 'Meter is hidden from the taskbar'
Assert-Equal 'None' $meterXaml.Window.WindowStyle 'Meter has no window chrome'

$meterScriptPath = Join-Path $PSScriptRoot '..\src\CodexMeter.ps1'
Assert-Equal $true (Test-Path -LiteralPath $meterScriptPath -PathType Leaf) 'Meter controller exists'
$parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($meterScriptPath, [ref]$null, [ref]$parseErrors)
Assert-Equal 0 $parseErrors.Count 'Meter controller has valid PowerShell syntax'

$events = @(
    Get-Content (Join-Path $PSScriptRoot 'fixtures\token-count.jsonl') |
        ForEach-Object { ConvertFrom-CodexLogLine -Line $_ } |
        Where-Object { $null -ne $_ }
)

Assert-Equal 1 $events.Count 'Only the valid token_count event is parsed'
Assert-Equal 73 ([math]::Round($events[0].WeeklyRemaining)) 'Weekly remaining is rounded correctly'
Assert-Equal 87 ([math]::Round($events[0].ContextRemaining)) 'Context remaining is rounded correctly'
Assert-Equal 1784692776 $events[0].ResetsAt 'Reset timestamp is preserved'
Assert-Equal '2026-07-15T07:01:00Z' $events[0].Timestamp 'Event timestamp is preserved'

$emptyLineResult = ConvertFrom-CodexLogLine -Line ''
Assert-Equal $true ($null -eq $emptyLineResult) 'Empty lines are ignored'

$invalidWeekly = ConvertFrom-CodexLogLine -Line '{"timestamp":"invalid-weekly","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"not-a-number","resets_at":"not-a-number"}},"info":{"last_token_usage":{"total_tokens":33702},"model_context_window":258400}}}'
Assert-Equal $true ($null -eq $invalidWeekly.WeeklyRemaining) 'Invalid weekly usage is ignored'
Assert-Equal 87 ([math]::Round($invalidWeekly.ContextRemaining)) 'Valid context usage survives invalid weekly usage'
Assert-Equal $true ($null -eq $invalidWeekly.ResetsAt) 'Invalid reset timestamp is ignored'

$invalidContext = ConvertFrom-CodexLogLine -Line '{"timestamp":"invalid-context","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":27,"resets_at":1784692776}},"info":{"last_token_usage":{"total_tokens":"not-a-number"},"model_context_window":258400}}}'
Assert-Equal 73 ([math]::Round($invalidContext.WeeklyRemaining)) 'Valid weekly usage survives invalid context usage'
Assert-Equal $true ($null -eq $invalidContext.ContextRemaining) 'Invalid context usage is ignored'

$invalidOnlyEvents = @(
    '{"payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"NaN"}}}}',
    '{"payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"Infinity"}}}}',
    '{"payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":1},"model_context_window":0}}}',
    '{"payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":1},"model_context_window":"invalid"}}}',
    '{"payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":"NaN"},"model_context_window":258400}}}',
    '{"payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":1},"model_context_window":"Infinity"}}}'
)

foreach ($line in $invalidOnlyEvents) {
    Assert-Equal $true ($null -eq (ConvertFrom-CodexLogLine -Line $line)) 'Invalid-only token events are ignored'
}

$desktopProcess = [pscustomobject]@{
    ProcessName = 'ChatGPT'
    Path = 'C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0.0_x64__8wekyb3d8bbwe\ChatGPT.exe'
}
$desktopCodexProcess = [pscustomobject]@{
    ProcessName = 'codex'
    Path = 'C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0.0_x64__8wekyb3d8bbwe\codex.exe'
}
$vscodeProcess = [pscustomobject]@{
    ProcessName = 'codex'
    Path = 'C:\Users\tester\.vscode\extensions\openai.chatgpt-1.0.0\bin\windows-x86_64\codex.exe'
}

Assert-Equal $true (Test-IsCodexDesktopProcess -Process $desktopProcess) 'Codex Desktop is recognized'
Assert-Equal $true (Test-IsCodexDesktopProcess -Process $desktopCodexProcess) 'Codex Desktop helper is recognized'
Assert-Equal $false (Test-IsCodexDesktopProcess -Process $vscodeProcess) 'VS Code codex process is rejected'

function New-TokenCountLine {
    param([double]$UsedPercent, [string]$Timestamp = '2026-07-15T08:00:00Z')

    '{"timestamp":"' + $Timestamp + '","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":' +
        ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $UsedPercent)) + '}}}}'
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('CodexMeterTests-' + [guid]::NewGuid())
$originalLocalAppData = $env:LOCALAPPDATA
$originalUserProfile = $env:USERPROFILE
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $logPath = Join-Path $tempRoot 'session.jsonl'
    Copy-Item (Join-Path $PSScriptRoot 'fixtures\token-count.jsonl') $logPath
    $cursor = New-CodexLogCursor

    $firstUpdate = Read-CodexLogUpdate -Path $logPath -Cursor $cursor
    Assert-Equal 73 ([math]::Round($firstUpdate.WeeklyRemaining)) 'Initial cursor read finds latest fixture event'

    [IO.File]::AppendAllText($logPath, (New-TokenCountLine 40) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    $secondUpdate = Read-CodexLogUpdate -Path $logPath -Cursor $cursor
    Assert-Equal 60 ([math]::Round($secondUpdate.WeeklyRemaining)) 'Incremental cursor read finds appended event'
    Assert-Equal $true ($null -eq (Read-CodexLogUpdate -Path $logPath -Cursor $cursor)) 'Unchanged log returns null'

    $partialLine = New-TokenCountLine 55 '2026-07-15T08:01:00Z'
    $splitAt = [math]::Floor($partialLine.Length / 2)
    [IO.File]::AppendAllText($logPath, $partialLine.Substring(0, $splitAt), (New-Object Text.UTF8Encoding($false)))
    Assert-Equal $true ($null -eq (Read-CodexLogUpdate -Path $logPath -Cursor $cursor)) 'Unterminated JSON is retained'
    [IO.File]::AppendAllText($logPath, $partialLine.Substring($splitAt) + "`n", (New-Object Text.UTF8Encoding($false)))
    $completedUpdate = Read-CodexLogUpdate -Path $logPath -Cursor $cursor
    Assert-Equal 45 ([math]::Round($completedUpdate.WeeklyRemaining)) 'Retained JSON is parsed after newline arrives'

    [IO.File]::WriteAllText($logPath, (New-TokenCountLine 80 '2026-07-15T08:02:00Z') + "`n", (New-Object Text.UTF8Encoding($false)))
    $truncatedUpdate = Read-CodexLogUpdate -Path $logPath -Cursor $cursor
    Assert-Equal 20 ([math]::Round($truncatedUpdate.WeeklyRemaining)) 'Truncated log restarts cursor'

    $rotatedPath = Join-Path $tempRoot 'rotated.jsonl'
    [IO.File]::WriteAllText($rotatedPath, (New-TokenCountLine 10 '2026-07-15T08:03:00Z') + "`n", (New-Object Text.UTF8Encoding($false)))
    $rotatedUpdate = Read-CodexLogUpdate -Path $rotatedPath -Cursor $cursor
    Assert-Equal 90 ([math]::Round($rotatedUpdate.WeeklyRemaining)) 'New log path restarts cursor'

    $largeLogPath = Join-Path $tempRoot 'large.jsonl'
    $largeContent = ('x' * 2097200) + "`n" + (New-TokenCountLine 25 '2026-07-15T08:04:00Z') + "`n"
    [IO.File]::WriteAllText($largeLogPath, $largeContent, (New-Object Text.UTF8Encoding($false)))
    $largeUpdate = Read-CodexLogUpdate -Path $largeLogPath -Cursor (New-CodexLogCursor)
    Assert-Equal 75 ([math]::Round($largeUpdate.WeeklyRemaining)) 'Initial capped read discards its leading partial line'

    $env:USERPROFILE = Join-Path $tempRoot 'profile'
    $sessions = Join-Path $env:USERPROFILE '.codex\sessions\2026\07'
    New-Item -ItemType Directory -Path $sessions -Force | Out-Null
    $olderLog = Join-Path $sessions 'older.jsonl'
    $newerLog = Join-Path $sessions 'newer.jsonl'
    [IO.File]::WriteAllText($olderLog, "{}`n")
    [IO.File]::WriteAllText($newerLog, "{}`n")
    (Get-Item $olderLog).LastWriteTime = [datetime]'2026-07-15T08:00:00'
    (Get-Item $newerLog).LastWriteTime = [datetime]'2026-07-15T08:01:00'
    Assert-Equal $newerLog (Get-LatestCodexLog) 'Newest recursive session log is selected'

    Assert-Equal 0.6 (Limit-CodexZoom 0.2) 'Zoom lower bound is enforced'
    Assert-Equal 1.2 (Limit-CodexZoom 2) 'Zoom upper bound is enforced'
    Assert-Equal 1.01 (Limit-CodexZoom 1.006) 'Zoom is rounded to two decimals'

    $env:LOCALAPPDATA = Join-Path $tempRoot 'local'
    $defaults = Read-CodexSettings
    Assert-Equal $true ($null -eq $defaults.Left) 'Default left is null'
    Assert-Equal $true ($null -eq $defaults.Top) 'Default top is null'
    Assert-Equal 1.0 $defaults.Zoom 'Default zoom is one'

    $savedSettings = [pscustomobject]@{ Left = 12; Top = 34; Zoom = 1.234 }
    Save-CodexSettings -Settings $savedSettings
    $loadedSettings = Read-CodexSettings
    Assert-Equal 12 $loadedSettings.Left 'Saved left is restored'
    Assert-Equal 34 $loadedSettings.Top 'Saved top is restored'
    Assert-Equal 1.2 $loadedSettings.Zoom 'Saved zoom is normalized'

    [IO.File]::WriteAllText((Get-CodexSettingsPath), '{broken json', (New-Object Text.UTF8Encoding($false)))
    $damagedSettings = Read-CodexSettings
    Assert-Equal $true ($null -eq $damagedSettings.Left) 'Damaged settings restore default left'
    Assert-Equal $true ($null -eq $damagedSettings.Top) 'Damaged settings restore default top'
    Assert-Equal 1.0 $damagedSettings.Zoom 'Damaged settings restore default zoom'
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:USERPROFILE = $originalUserProfile
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'PASS Test-CodexUsage'
