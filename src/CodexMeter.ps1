param(
    [ValidateRange(0, 300)]
    [int]$SmokeTestSeconds = 0
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:windir)) {
    $env:windir = $env:SystemRoot
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

Import-Module (Join-Path $PSScriptRoot 'CodexUsage.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'CodexSettings.psm1') -Force

$baseWidth = 320.0
$baseHeight = 210.0
$barWidth = 284.0
$xamlPath = Join-Path $PSScriptRoot 'CodexMeter.xaml'
$xamlText = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
$xmlReader = New-Object Xml.XmlNodeReader ([xml]$xamlText)
$window = [Windows.Markup.XamlReader]::Load($xmlReader)

$controls = @{}
foreach ($name in @(
    'RootScale', 'DragSurface', 'WeeklyBar', 'WeeklyValue', 'ResetValue',
    'ContextBar', 'ContextValue', 'FreshnessValue', 'ZoomValue'
)) {
    $controls[$name] = $window.FindName($name)
    if ($null -eq $controls[$name]) {
        throw "Missing XAML control: $name"
    }
}

$weeklyHealthyBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#FF63D99A')
$weeklyWarningBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFF0B75B')
$weeklyCriticalBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFFF6B6B')
$contextBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#FF55A9F4')
$textWaitingForData = -join @([char]0x7B49, [char]0x5F85, ' Codex ', [char]0x6570, [char]0x636E)
$textReset = -join @([char]0x91CD, [char]0x7F6E)
$textUpdated = -join @([char]0x66F4, [char]0x65B0)
$textWaitingForUpdate = -join @([char]0x7B49, [char]0x5F85, [char]0x66F4, [char]0x65B0)
$settings = Read-CodexSettings
$cursor = New-CodexLogCursor
$hasSnapshot = $false
$zoom = Limit-CodexZoom -Zoom ([double]$settings.Zoom)

function Save-CurrentCodexMeterSettings {
    try {
        Save-CodexSettings -Settings ([pscustomobject]@{
            Left = $window.Left
            Top = $window.Top
            Zoom = $zoom
        })
    }
    catch {
        # Persistence failure must not interrupt the live meter.
    }
}

function Set-CodexMeterZoom {
    param([double]$Value)

    $script:zoom = Limit-CodexZoom -Zoom $Value
    $controls.RootScale.ScaleX = $script:zoom
    $controls.RootScale.ScaleY = $script:zoom
    $window.Width = $baseWidth * $script:zoom
    $window.Height = $baseHeight * $script:zoom
    $controls.ZoomValue.Text = '{0:0}%' -f ($script:zoom * 100)
}

function Test-CodexMeterRectangleOnScreen {
    param([double]$Left, [double]$Top)

    if ([double]::IsNaN($Left) -or [double]::IsInfinity($Left) -or
        [double]::IsNaN($Top) -or [double]::IsInfinity($Top)) {
        return $false
    }

    $right = $Left + $window.Width
    $bottom = $Top + $window.Height
    $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($window)
    foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
        $physicalArea = $screen.WorkingArea
        $area = New-Object Windows.Rect -ArgumentList @(
            ($physicalArea.Left / $dpi.DpiScaleX),
            ($physicalArea.Top / $dpi.DpiScaleY),
            ($physicalArea.Width / $dpi.DpiScaleX),
            ($physicalArea.Height / $dpi.DpiScaleY)
        )
        if ($right -gt $area.Left -and $Left -lt $area.Right -and
            $bottom -gt $area.Top -and $Top -lt $area.Bottom) {
            return $true
        }
    }
    return $false
}

function Restore-CodexMeterPosition {
    $savedPositionIsValid = $false
    if ($null -ne $settings.Left -and $null -ne $settings.Top) {
        try {
            $savedLeft = [double]$settings.Left
            $savedTop = [double]$settings.Top
            $savedPositionIsValid = Test-CodexMeterRectangleOnScreen -Left $savedLeft -Top $savedTop
        }
        catch {
            $savedPositionIsValid = $false
        }
    }

    if ($savedPositionIsValid) {
        $window.Left = $savedLeft
        $window.Top = $savedTop
        return
    }

    $primaryArea = [Windows.SystemParameters]::WorkArea
    $window.Left = $primaryArea.Right - $window.Width - 24
    $window.Top = $primaryArea.Top + 24
}

function Set-CodexWeeklyValue {
    param([double]$Remaining)

    $remaining = [math]::Max(0, [math]::Min(100, $Remaining))
    $brush = if ($remaining -lt 20) {
        $weeklyCriticalBrush
    }
    elseif ($remaining -lt 50) {
        $weeklyWarningBrush
    }
    else {
        $weeklyHealthyBrush
    }
    $controls.WeeklyBar.Width = $barWidth * $remaining / 100
    $controls.WeeklyBar.Background = $brush
    $controls.WeeklyValue.Foreground = $brush
    $controls.WeeklyValue.Text = '{0:0}%' -f $remaining
}

function Set-CodexContextValue {
    param([double]$Remaining)

    $remaining = [math]::Max(0, [math]::Min(100, $Remaining))
    $controls.ContextBar.Width = $barWidth * $remaining / 100
    $controls.ContextBar.Background = $contextBrush
    $controls.ContextValue.Text = '{0:0}%' -f $remaining
}

function Get-CodexDesktopIsRunning {
    $matches = @(
        Get-Process -Name 'ChatGPT', 'codex' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $candidate = [pscustomobject]@{
                    ProcessName = $_.ProcessName
                    Path = $_.Path
                }
                if (Test-IsCodexDesktopProcess -Process $candidate) {
                    $candidate
                }
            }
            catch {
                # Protected or exiting processes are ignored.
            }
        }
    )
    $matches.Count -gt 0
}

function Invoke-CodexMeterPoll {
    try {
        if (-not (Get-CodexDesktopIsRunning)) {
            $window.Hide()
            return
        }

        if (-not $window.IsVisible) {
            $window.Show()
        }

        $logPath = Get-LatestCodexLog
        if ([string]::IsNullOrWhiteSpace($logPath)) {
            if (-not $hasSnapshot) {
                $controls.FreshnessValue.Text = $textWaitingForData
            }
            return
        }

        $snapshot = Read-CodexLogUpdate -Path $logPath -Cursor $cursor
        if ($null -eq $snapshot) {
            return
        }

        if ($null -ne $snapshot.WeeklyRemaining) {
            Set-CodexWeeklyValue -Remaining ([double]$snapshot.WeeklyRemaining)
        }
        if ($null -ne $snapshot.ContextRemaining) {
            Set-CodexContextValue -Remaining ([double]$snapshot.ContextRemaining)
        }
        if ($null -ne $snapshot.ResetsAt) {
            $epoch = [datetime]::SpecifyKind([datetime]'1970-01-01T00:00:00', [DateTimeKind]::Utc)
            $resetLocal = $epoch.AddSeconds([double]$snapshot.ResetsAt).ToLocalTime()
            $controls.ResetValue.Text = $textReset + (' {0:MM-dd HH:mm}' -f $resetLocal)
        }

        $script:hasSnapshot = $true
        $controls.FreshnessValue.Text = $textUpdated + (' {0:HH:mm:ss}' -f (Get-Date))
    }
    catch {
        $controls.FreshnessValue.Text = $textWaitingForUpdate
    }
}

Set-CodexMeterZoom -Value $zoom
Restore-CodexMeterPosition

$controls.DragSurface.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)

    if ($eventArgs.LeftButton -eq [Windows.Input.MouseButtonState]::Pressed) {
        try {
            $window.DragMove()
        }
        finally {
            Save-CurrentCodexMeterSettings
        }
    }
})

$window.Add_MouseLeftButtonUp({ Save-CurrentCodexMeterSettings })
$window.Add_PreviewMouseWheel({
    param($sender, $eventArgs)

    $controlPressed = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
    if (-not $controlPressed) {
        return
    }

    $step = if ($eventArgs.Delta -gt 0) { 0.05 } else { -0.05 }
    Set-CodexMeterZoom -Value ($zoom + $step)
    Save-CurrentCodexMeterSettings
    $eventArgs.Handled = $true
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({ Invoke-CodexMeterPoll })
$window.Add_Closed({
    $timer.Stop()
    $window.Dispatcher.BeginInvokeShutdown([Windows.Threading.DispatcherPriority]::Background)
})

$smokeTimer = $null
if ($SmokeTestSeconds -gt 0) {
    $smokeTimer = New-Object Windows.Threading.DispatcherTimer
    $smokeTimer.Interval = [TimeSpan]::FromSeconds($SmokeTestSeconds)
    $smokeTimer.Add_Tick({
        $smokeTimer.Stop()
        $window.Close()
    })
    $smokeTimer.Start()
}

Invoke-CodexMeterPoll
$timer.Start()
[Windows.Threading.Dispatcher]::Run()
