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

$desktopProcess = [pscustomobject]@{
    ProcessName = 'ChatGPT'
    Path = 'C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0.0_x64__8wekyb3d8bbwe\ChatGPT.exe'
}
$vscodeProcess = [pscustomobject]@{
    ProcessName = 'codex'
    Path = 'C:\Users\tester\.vscode\extensions\openai.chatgpt-1.0.0\bin\windows-x86_64\codex.exe'
}

Assert-Equal $true (Test-IsCodexDesktopProcess -Process $desktopProcess) 'Codex Desktop is recognized'
Assert-Equal $false (Test-IsCodexDesktopProcess -Process $vscodeProcess) 'VS Code codex process is rejected'

Write-Output 'PASS Test-CodexUsage'
