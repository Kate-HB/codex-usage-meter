# Codex Meter

## 项目简介

Codex Meter 是面向 Windows Codex Desktop 用户的轻量悬浮监视器。它从 Codex 写入本机的会话日志中读取数据，显示周额度剩余、当前对话上下文剩余和周额度重置时间。

程序使用 Windows PowerShell 5.1 与 WPF 实现，无需安装 PowerShell 模块或其他运行库。Codex Desktop 未运行时，悬浮窗会自动隐藏。

## 功能

- 显示周额度剩余百分比，并用绿、黄、红三种颜色提示余量。
- 显示当前对话上下文剩余百分比，使用蓝色进度条。
- 显示周额度的本地重置日期和时间。
- 每秒检查最新 Codex 会话日志中的新数据。
- 仅在 Codex Desktop 运行时显示，始终置顶且不占用任务栏位置。
- 支持拖动窗口，并自动保存位置。
- 支持按住 `Ctrl` 滚动鼠标滚轮，在 60%–120% 之间缩放。
- 安装后随 Windows 登录静默启动。

## 系统要求

- Windows 10 或 Windows 11。
- Codex Desktop Windows 应用。
- Windows PowerShell 5.1（Windows 自带的 `powershell.exe`）。
- Git，用于克隆和更新项目。

本项目不承诺支持 macOS、Linux、PowerShell 7 或其他 Codex 客户端。

## 快速安装

打开 PowerShell，依次执行：

```powershell
git clone https://github.com/Kate-HB/codex-usage-meter.git
cd codex-usage-meter
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

安装脚本会在 Windows 的“启动”文件夹创建 `Codex Meter.lnk`，并在监视器尚未运行时立即静默启动。以后登录 Windows 时会自动启动。

仓库目录不能在安装后移动或删除，因为快捷方式保存的是 `src\CodexMeter.ps1` 的绝对路径。若移动了目录，请在新位置重新运行安装脚本。

## 使用方法

1. 启动 Codex Desktop。监视器只在检测到 Codex Desktop 正在运行时显示；关闭 Codex Desktop 后会自动隐藏。
2. 在 Codex 中发送一条消息，并等待 Codex 写入会话日志。监视器随后显示最新数据。
3. 按住悬浮窗上方区域拖动，可改变窗口位置；松开后自动保存。
4. 将鼠标放在悬浮窗上，按住 `Ctrl` 滚动滚轮，可按 5% 步长缩放。范围为 60%–120%。

右上角的百分比是悬浮窗的缩放比例，不是额度或上下文指标。

## 指标说明

### 周额度剩余

周额度剩余按日志中的 `used_percent` 计算：

```text
周额度剩余 = 100 - used_percent
```

显示值会限制在 0%–100%，颜色阈值如下：

| 颜色 | 周额度剩余 |
| --- | --- |
| 绿色 | 大于或等于 50% |
| 黄色 | 大于或等于 20% 且小于 50% |
| 红色 | 小于 20% |

“重置”后的时间来自同一条日志记录中的 `resets_at`，并转换为 Windows 当前本地时区。

### 当前对话上下文剩余

蓝色进度条表示当前对话上下文窗口的剩余比例，计算依据是日志中的已用 token 总数和模型上下文窗口大小：

```text
上下文剩余 = 100 - (total_tokens / model_context_window * 100)
```

显示值会限制在 0%–100%。它描述当前对话可用的上下文空间，不代表周额度。

## 数据刷新规则

监视器每秒轮询 `%USERPROFILE%\.codex\sessions` 下最后修改的 `.jsonl` 日志，并读取新增内容中的最新 `token_count` 事件。

仅切换对话通常不会产生新的 `token_count`，因此上下文数值可能不会立即变化。请在目标对话中发送消息，并等待 Codex 完成响应、写入日志；下一次轮询后才会刷新。日志没有新增有效事件时，界面保留最近一次有效数据。

## 数据来源与隐私

Codex Meter 只读以下本机会话目录：

```text
%USERPROFILE%\.codex\sessions
```

程序不联网、不上传日志，也不修改 Codex 会话文件。它只解析本地 `.jsonl` 日志中的 `token_count` 数据。

窗口位置和缩放设置保存在：

```text
%LOCALAPPDATA%\CodexMeter\settings.json
```

## 更新

进入已克隆的仓库，拉取最新代码，先卸载以停止旧进程并移除旧快捷方式，再重新安装：

```powershell
cd codex-usage-meter
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

卸载脚本会保留 `%LOCALAPPDATA%\CodexMeter\settings.json`，更新后仍使用原来的窗口位置和缩放设置。

## 卸载

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

卸载脚本会删除开机启动快捷方式，并停止由本项目 `CodexMeter.ps1` 启动的 PowerShell 进程。卸载会保留 `%LOCALAPPDATA%\CodexMeter\settings.json`，以后重新安装仍可使用原来的位置和缩放设置。

## 故障排查

### 看不到悬浮窗

先确认 Codex Desktop 正在运行。监视器检测不到 Codex Desktop 时会主动隐藏；仅启动脚本而不启动 Codex Desktop，不会显示窗口。

### 切换对话后上下文没有变化

仅切换对话不会产生新的 `token_count`。在目标对话中发送一条消息，等待 Codex 完成响应并写入日志。监视器每秒检查一次，写入完成后会自动刷新。

### 更新代码后行为仍未变化

安装脚本检测到监视器已运行时不会重启旧进程。拉取代码后，请先运行卸载脚本停止旧进程，再运行安装脚本：

```powershell
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

此操作保留 `%LOCALAPPDATA%\CodexMeter\settings.json`。

### 窗口位置或缩放异常

先运行卸载脚本停止监视器，再删除设置文件并重新安装：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
Remove-Item -LiteralPath "$env:LOCALAPPDATA\CodexMeter\settings.json" -Force -ErrorAction SilentlyContinue
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

删除设置后，位置和缩放会恢复默认值。

### PowerShell 提示禁止运行脚本

使用文档中的完整命令，通过当前进程的 `ExecutionPolicy Bypass` 运行脚本，无需修改系统级执行策略：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

### 中文显示乱码

README 和 XAML 使用 UTF-8。Windows PowerShell 5.1 的默认文本编码行为与新版 PowerShell 不同；读取文件时请明确指定 UTF-8：

```powershell
Get-Content -LiteralPath .\README.md -Raw -Encoding UTF8
```

控制器脚本为兼容 Windows PowerShell 5.1，避免在脚本字符串中直接使用非 ASCII 文本。控制台编码异常不影响 WPF 悬浮窗中的中文显示。

## 手动运行

不安装开机启动快捷方式时，可在仓库根目录手动启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File .\src\CodexMeter.ps1
```

命令会隐藏 PowerShell 控制台。监视器仍只在 Codex Desktop 运行时显示。

## 开发与测试

项目只使用 Windows PowerShell 5.1、WPF 和内置 .NET API。修改后，在仓库根目录运行测试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-CodexUsage.ps1
```

测试覆盖日志解析、增量读取、会话日志选择、Codex Desktop 进程识别、缩放范围、设置读写、XAML 控件及安装/卸载脚本的基本约束。成功时输出：

```text
PASS Test-CodexUsage
```

## 项目结构

```text
codex-usage-meter/
├─ scripts/
│  ├─ install.ps1          创建开机启动快捷方式并启动监视器
│  └─ uninstall.ps1        删除快捷方式并停止监视器
├─ src/
│  ├─ CodexMeter.ps1       WPF 窗口控制、轮询和交互
│  ├─ CodexMeter.xaml      悬浮窗界面
│  ├─ CodexSettings.psm1   位置与缩放设置读写
│  └─ CodexUsage.psm1      日志查找、增量读取和指标计算
├─ tests/
│  ├─ fixtures/
│  │  └─ token-count.jsonl 测试日志样本
│  └─ Test-CodexUsage.ps1  PowerShell 测试入口
└─ README.md               使用文档
```

## 已知限制

- 仅支持 Windows Codex Desktop；不承诺支持 macOS、Linux、VS Code 中的 Codex 或其他客户端。
- 数据完全依赖 Codex Desktop 写入本地会话日志；日志尚未写入、格式变化或缺少 `token_count` 时无法更新。
- 只读取最后修改的会话日志，因此指标以当前最新活动会话为准。
- 仅切换对话不会触发刷新，必须发送消息并等待 Codex 写入日志。
- 悬浮窗只显示日志提供的剩余比例和重置时间，不管理或更改账户额度。
