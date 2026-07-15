function ConvertTo-CodexFiniteDouble {
    param($Value)

    if ($null -eq $Value -or $Value -is [bool] -or
        ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        return $null
    }

    try {
        $number = [double]$Value
    }
    catch {
        return $null
    }

    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        return $null
    }

    $number
}

function ConvertFrom-CodexLogLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

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
        $usedPercent = ConvertTo-CodexFiniteDouble $event.payload.rate_limits.primary.used_percent
        if ($null -ne $usedPercent) {
            $weeklyRemaining = [math]::Min(100, [math]::Max(0, 100 - $usedPercent))
            $resetTimestamp = ConvertTo-CodexFiniteDouble $event.payload.rate_limits.primary.resets_at
            if ($null -ne $resetTimestamp) {
                $resetsAt = $event.payload.rate_limits.primary.resets_at
            }
        }
    }

    if ($null -ne $event.payload.info -and
        $null -ne $event.payload.info.last_token_usage -and
        $null -ne $event.payload.info.last_token_usage.total_tokens -and
        $null -ne $event.payload.info.model_context_window) {
        $totalTokens = ConvertTo-CodexFiniteDouble $event.payload.info.last_token_usage.total_tokens
        $contextWindow = ConvertTo-CodexFiniteDouble $event.payload.info.model_context_window
        if ($null -ne $totalTokens -and $null -ne $contextWindow -and $contextWindow -gt 0) {
            $contextUsedPercent = 100 * $totalTokens / $contextWindow
            $contextRemaining = [math]::Min(100, [math]::Max(0, 100 - $contextUsedPercent))
        }
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
