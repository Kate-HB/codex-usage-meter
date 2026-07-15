function Limit-CodexZoom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Zoom
    )

    [math]::Max(0.6, [math]::Min(1.2, [math]::Round($Zoom, 2)))
}

function Get-CodexSettingsPath {
    [CmdletBinding()]
    param()

    Join-Path $env:LOCALAPPDATA 'CodexMeter\settings.json'
}

function New-DefaultCodexSettings {
    [pscustomobject]@{
        Left = $null
        Top = $null
        Zoom = 1.0
    }
}

function Read-CodexSettings {
    [CmdletBinding()]
    param()

    $path = Get-CodexSettingsPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return New-DefaultCodexSettings
    }

    try {
        $saved = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $zoom = 1.0
        if ($null -ne $saved.PSObject.Properties['Zoom'] -and $null -ne $saved.Zoom) {
            $zoom = Limit-CodexZoom -Zoom ([double]$saved.Zoom)
        }
        [pscustomobject]@{
            Left = $saved.Left
            Top = $saved.Top
            Zoom = $zoom
        }
    }
    catch {
        New-DefaultCodexSettings
    }
}

function Save-CodexSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $path = Get-CodexSettingsPath
    $directory = Split-Path -Parent $path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $normalized = [pscustomobject]@{
        Left = $Settings.Left
        Top = $Settings.Top
        Zoom = Limit-CodexZoom -Zoom ([double]$Settings.Zoom)
    }
    $normalized | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
}

Export-ModuleMember -Function Limit-CodexZoom, Get-CodexSettingsPath, Read-CodexSettings, Save-CodexSettings
