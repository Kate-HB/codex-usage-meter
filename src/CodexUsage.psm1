function ConvertFrom-CodexLogLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    try {
        $event = $Line | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    if ($null -eq $event.payload -or $event.payload.type -ne 'token_count') {
        return $null
    }

    $weeklyRemaining = $null
    $contextRemaining = $null
    $resetsAt = $null

    if ($null -ne $event.payload.rate_limits -and
        $null -ne $event.payload.rate_limits.primary -and
        $null -ne $event.payload.rate_limits.primary.used_percent) {
        $weeklyRemaining = [math]::Min(100, [math]::Max(0, 100 - [double]$event.payload.rate_limits.primary.used_percent))
        $resetsAt = $event.payload.rate_limits.primary.resets_at
    }

    if ($null -ne $event.payload.info -and
        $null -ne $event.payload.info.last_token_usage -and
        $null -ne $event.payload.info.last_token_usage.total_tokens -and
        $null -ne $event.payload.info.model_context_window -and
        [double]$event.payload.info.model_context_window -gt 0) {
        $usedPercent = 100 * [double]$event.payload.info.last_token_usage.total_tokens / [double]$event.payload.info.model_context_window
        $contextRemaining = [math]::Min(100, [math]::Max(0, 100 - $usedPercent))
    }

    if ($null -eq $weeklyRemaining -and $null -eq $contextRemaining) {
        return $null
    }

    [pscustomobject]@{
        WeeklyRemaining = $weeklyRemaining
        ContextRemaining = $contextRemaining
        ResetsAt = $resetsAt
        Timestamp = $event.timestamp
    }
}

function Test-IsCodexDesktopProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Process
    )

    $Process.ProcessName -in @('ChatGPT', 'codex') -and
        $Process.Path -match '\\WindowsApps\\OpenAI\.Codex_'
}

Export-ModuleMember -Function ConvertFrom-CodexLogLine, Test-IsCodexDesktopProcess
