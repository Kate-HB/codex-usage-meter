$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\CodexUsage.psm1') -Force

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

Write-Output 'PASS Test-CodexUsage'
