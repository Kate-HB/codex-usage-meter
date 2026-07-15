# Codex Usage Float Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dependency-free Windows floating meter that appears with Codex and shows official weekly and context remaining usage.

**Architecture:** A PowerShell 5.1 entry script hosts a WPF window and polls isolated process-detection and incremental JSONL parsing functions. Pure functions own calculations and settings normalization so behavior can be tested without opening a window.

**Tech Stack:** Windows PowerShell 5.1, WPF/XAML, built-in JSON/filesystem APIs, custom PowerShell assertion runner

---

## File map

- `src/CodexUsage.psm1`: process identification, JSONL parsing, incremental reading, calculations.
- `src/CodexSettings.psm1`: settings defaults, zoom bounds, JSON persistence.
- `src/CodexMeter.xaml`: borderless always-on-top two-meter layout.
- `src/CodexMeter.ps1`: WPF lifecycle, polling, drag, zoom, visibility.
- `scripts/install.ps1`: create the per-user Startup shortcut.
- `scripts/uninstall.ps1`: remove the shortcut and stop this monitor.
- `tests/fixtures/token-count.jsonl`: deterministic Codex event samples.
- `tests/Test-CodexUsage.ps1`: dependency-free behavior tests.
- `README.md`: install, usage, privacy, uninstall.

### Task 1: Usage parser and process detection

**Files:**
- Create: `tests/fixtures/token-count.jsonl`
- Create: `tests/Test-CodexUsage.ps1`
- Create: `src/CodexUsage.psm1`

- [ ] **Step 1: Write failing tests**

Create a JSONL fixture containing one malformed line and one `token_count` record with `used_percent=27`, `resets_at=1784692776`, `total_tokens=33702`, and `model_context_window=258400`. Add this assertion runner and checks:

```powershell
Import-Module "$PSScriptRoot\..\src\CodexUsage.psm1" -Force
function Assert-Equal($Expected, $Actual, [string]$Name) {
    if ($Expected -ne $Actual) { throw "$Name expected '$Expected', got '$Actual'" }
}
$snapshot = $null
Get-Content "$PSScriptRoot\fixtures\token-count.jsonl" | ForEach-Object {
    $parsed = ConvertFrom-CodexLogLine $_
    if ($null -ne $parsed) { $snapshot = $parsed }
}
Assert-Equal 73 ([math]::Round($snapshot.WeeklyRemaining)) 'weekly remaining'
Assert-Equal 87 ([math]::Round($snapshot.ContextRemaining)) 'context remaining'
$desktop = [pscustomobject]@{ ProcessName='ChatGPT'; Path='C:\Program Files\WindowsApps\OpenAI.Codex_1\app\ChatGPT.exe' }
$vscode = [pscustomobject]@{ ProcessName='codex'; Path='C:\Users\me\.vscode\extensions\openai.chatgpt\codex.exe' }
Assert-Equal $true (Test-IsCodexDesktopProcess $desktop) 'desktop process'
Assert-Equal $false (Test-IsCodexDesktopProcess $vscode) 'VS Code process'
```

- [ ] **Step 2: Verify the test fails**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-CodexUsage.ps1`. Expected: module import fails.

- [ ] **Step 3: Implement the parser and detector**

```powershell
function ConvertFrom-CodexLogLine([string]$Line) {
    try { $event = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($event.payload.type -ne 'token_count') { return $null }
    $limits, $info = $event.payload.rate_limits, $event.payload.info
    if ($null -eq $limits.primary -and $null -eq $info) { return $null }
    $weekly = if ($null -ne $limits.primary.used_percent) {
        [math]::Max(0, [math]::Min(100, 100 - [double]$limits.primary.used_percent))
    } else { $null }
    $context = if ($info.model_context_window -gt 0 -and $null -ne $info.last_token_usage.total_tokens) {
        [math]::Max(0, [math]::Min(100, 100 - 100 * [double]$info.last_token_usage.total_tokens / [double]$info.model_context_window))
    } else { $null }
    [pscustomobject]@{ WeeklyRemaining=$weekly; ContextRemaining=$context; ResetsAt=$limits.primary.resets_at; Timestamp=$event.timestamp }
}
function Test-IsCodexDesktopProcess($Process) {
    ($Process.ProcessName -in @('ChatGPT','codex')) -and ([string]$Process.Path -match '[\\/]WindowsApps[\\/]OpenAI\.Codex_')
}
Export-ModuleMember -Function ConvertFrom-CodexLogLine, Test-IsCodexDesktopProcess
```

- [ ] **Step 4: Verify tests pass and commit**

Run the Task 1 test command. Expected: exit code 0. Commit with `git commit -am "feat: parse Codex usage events"` after adding new files.

### Task 2: Incremental reader and settings

**Files:**
- Modify: `tests/Test-CodexUsage.ps1`
- Modify: `src/CodexUsage.psm1`
- Create: `src/CodexSettings.psm1`

- [ ] **Step 1: Add failing cursor and zoom tests**

Copy the fixture to a temporary log, call `New-CodexLogCursor`, read it, append a record with `used_percent=40`, read again, and assert results 73 then 60. A third read must return `$null`. Assert `Limit-CodexZoom 0.2` equals `0.6` and `Limit-CodexZoom 2` equals `1.2`.

- [ ] **Step 2: Verify undefined-function failures**

Run the suite. Expected: `New-CodexLogCursor` is undefined.

- [ ] **Step 3: Implement incremental reading**

Implement `New-CodexLogCursor` with `Path`, `Position`, and `Remainder`. Implement `Read-CodexLogUpdate`: on file switch or truncation, start at `max(0, Length-2097152)`; discard an initial partial line, read only new bytes, retain the last unterminated fragment, parse complete lines, and return the newest snapshot. Implement `Get-LatestCodexLog` by selecting the newest `*.jsonl` under `$env:USERPROFILE\.codex\sessions`. Export all three functions.

- [ ] **Step 4: Implement settings**

```powershell
function Limit-CodexZoom([double]$Zoom) { [math]::Max(0.6, [math]::Min(1.2, [math]::Round($Zoom, 2))) }
function Get-CodexSettingsPath { Join-Path $env:LOCALAPPDATA 'CodexMeter\settings.json' }
function Read-CodexSettings {
    $default = [pscustomobject]@{ Left=$null; Top=$null; Zoom=1.0 }
    $path = Get-CodexSettingsPath
    if (-not (Test-Path $path)) { return $default }
    try {
        $saved = Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop
        [pscustomobject]@{ Left=$saved.Left; Top=$saved.Top; Zoom=(Limit-CodexZoom $saved.Zoom) }
    } catch { $default }
}
function Save-CodexSettings($Settings) {
    $path = Get-CodexSettingsPath
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $Settings | ConvertTo-Json | Set-Content -Encoding UTF8 $path
}
```

- [ ] **Step 5: Verify and commit**

Run the suite. Expected: pass. Commit `src/CodexUsage.psm1`, `src/CodexSettings.psm1`, and tests as `feat: follow Codex logs and persist settings`.

### Task 3: WPF floating window

**Files:**
- Create: `src/CodexMeter.xaml`
- Create: `src/CodexMeter.ps1`
- Modify: `tests/Test-CodexUsage.ps1`

- [ ] **Step 1: Add failing UI contract tests**

Load XAML as XML. Assert named controls `WeeklyBar`, `WeeklyValue`, `ResetValue`, `ContextBar`, `ContextValue`, `FreshnessValue`, and `ZoomValue` exist. Assert `Topmost=True`, `ShowInTaskbar=False`, and `WindowStyle=None`.

- [ ] **Step 2: Verify the XAML-missing failure**

Run the suite. Expected: `src/CodexMeter.xaml` is missing.

- [ ] **Step 3: Create the layout**

Create a 320×210 transparent WPF window containing one rounded dark card, compact header, green weekly track, blue context track, reset label, freshness label, and zoom label. Both meter rows remain visible at every scale.

- [ ] **Step 4: Implement behavior**

Load WPF assemblies and both modules, parse XAML, cache named controls, and start a one-second `DispatcherTimer`. Each tick gets `ChatGPT` and `codex` processes with paths, filters through `Test-IsCodexDesktopProcess`, controls visibility, reads the newest log, and updates both values. Before data, show `--` and `等待 Codex 数据`. Format reset epoch in local time.

Mouse drag calls `DragMove()` and saves coordinates. `Ctrl+MouseWheel` changes zoom by 0.05, clamps through `Limit-CodexZoom`, applies one `ScaleTransform`, and saves. Restore saved values; if no screen intersects the saved rectangle, place the window 24 pixels from the primary work area's top-right. Catch polling errors, retain valid values, and show `等待更新`.

- [ ] **Step 5: Verify automated and visual behavior**

Run the suite, then `powershell -NoProfile -ExecutionPolicy Bypass -STA -File src\CodexMeter.ps1`. Expected: two bars appear with Codex, dragging works, Ctrl+wheel scales from 60% through 120%, and plain wheel does nothing.

- [ ] **Step 6: Commit**

Commit XAML, controller, and tests as `feat: add Codex usage floating window`.

### Task 4: Startup and documentation

**Files:**
- Create: `scripts/install.ps1`
- Create: `scripts/uninstall.ps1`
- Create: `README.md`

- [ ] **Step 1: Implement installation**

Resolve `src/CodexMeter.ps1`; create `Codex Meter.lnk` in the current user's Startup folder through `WScript.Shell`. Target `powershell.exe` with `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "<resolved path>"`. Start it once unless an existing PowerShell command line contains that resolved path.

- [ ] **Step 2: Implement uninstallation**

Delete only `Codex Meter.lnk`. Stop only PowerShell processes whose command line contains the resolved `CodexMeter.ps1` path. Preserve local settings.

- [ ] **Step 3: Write README**

Document exact install command, drag and Ctrl+wheel controls, Codex-driven visibility, local-only `%USERPROFILE%\.codex\sessions` data source, and exact uninstall command.

- [ ] **Step 4: Verify and commit**

Run install; verify shortcut and one hidden monitor. Close/reopen Codex and verify hide/show. Run uninstall and verify removal. Commit as `feat: install Codex meter at user startup`.

### Task 5: Final verification

**Files:**
- Modify only if verification exposes a defect.

- [ ] **Step 1: Run automated checks**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-CodexUsage.ps1`, `git diff --check`, and `git status --short`. Expected: PASS, no whitespace errors, clean worktree.

- [ ] **Step 2: Run acceptance checks**

Verify both progress bars always remain; values match the latest event; reset time is local; malformed and incomplete lines do not crash; file rotation works; Codex Desktop controls visibility; VS Code Codex alone does not; drag and zoom persist; zoom bounds hold; off-screen coordinates recover.

- [ ] **Step 3: Record evidence**

Capture exact test output and current commit hash in the handoff. Create no commit unless verification required a fix.
