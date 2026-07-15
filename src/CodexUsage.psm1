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

function New-CodexLogCursor {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        Path = $null
        Position = [long]0
        Remainder = ''
    }
}

function Read-CodexLogUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Cursor
    )

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $file = Get-Item -LiteralPath $fullPath -ErrorAction Stop
        $length = [long]$file.Length
        $pathChanged = -not [string]::Equals([string]$Cursor.Path, $fullPath, [StringComparison]::OrdinalIgnoreCase)
        $restart = $pathChanged -or $length -lt [long]$Cursor.Position
        $discardPartialLine = $false

        if ($restart) {
            $Cursor.Path = $fullPath
            $Cursor.Position = [math]::Max([long]0, $length - [long]2097152)
            $Cursor.Remainder = ''

            if ($Cursor.Position -gt 0) {
                $probe = New-Object IO.FileStream($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                try {
                    $null = $probe.Seek($Cursor.Position - 1, [IO.SeekOrigin]::Begin)
                    $discardPartialLine = $probe.ReadByte() -ne 10
                }
                finally {
                    $probe.Dispose()
                }
            }
        }

        $available = $length - [long]$Cursor.Position
        if ($available -le 0) {
            return $null
        }

        $stream = New-Object IO.FileStream($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            $null = $stream.Seek([long]$Cursor.Position, [IO.SeekOrigin]::Begin)
            $buffer = New-Object byte[] ([int]$available)
            $read = 0
            while ($read -lt $buffer.Length) {
                $count = $stream.Read($buffer, $read, $buffer.Length - $read)
                if ($count -le 0) { break }
                $read += $count
            }
        }
        finally {
            $stream.Dispose()
        }

        if ($read -le 0) {
            return $null
        }

        $chunk = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        if ($discardPartialLine) {
            $firstNewline = $chunk.IndexOf("`n")
            if ($firstNewline -lt 0) {
                return $null
            }
            $chunk = $chunk.Substring($firstNewline + 1)
        }

        $Cursor.Position = [long]$Cursor.Position + $read
        $text = [string]$Cursor.Remainder + $chunk
        $lastNewline = $text.LastIndexOf("`n")
        if ($lastNewline -lt 0) {
            $Cursor.Remainder = $text
            return $null
        }

        $completeText = $text.Substring(0, $lastNewline)
        $Cursor.Remainder = $text.Substring($lastNewline + 1)
        $latest = $null
        foreach ($line in ($completeText -split "`n")) {
            $snapshot = ConvertFrom-CodexLogLine -Line $line.TrimEnd("`r")
            if ($null -ne $snapshot) {
                $latest = $snapshot
            }
        }
        return $latest
    }
    catch {
        return $null
    }
}

function Get-LatestCodexLog {
    [CmdletBinding()]
    param()

    try {
        $sessionsPath = Join-Path $env:USERPROFILE '.codex\sessions'
        $latest = Get-ChildItem -LiteralPath $sessionsPath -Filter '*.jsonl' -File -Recurse -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $latest) {
            return $latest.FullName
        }
    }
    catch {
        return $null
    }
}

Export-ModuleMember -Function ConvertFrom-CodexLogLine, Test-IsCodexDesktopProcess, New-CodexLogCursor, Read-CodexLogUpdate, Get-LatestCodexLog
