# Codex Meter

Windows PowerShell 5.1 零依赖悬浮监视器，显示周额度与当前上下文剩余量。只读本机 `%USERPROFILE%\.codex\sessions`，不联网。

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

随系统静默启动，仅 Codex Desktop 运行时显示。拖动窗口可移动；按住 `Ctrl` 滚轮可缩放 60%–120%。

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

卸载保留 `%LOCALAPPDATA%\CodexMeter` 设置。

## 手动运行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File .\src\CodexMeter.ps1
```
