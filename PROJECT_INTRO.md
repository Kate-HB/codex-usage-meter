# Codex Meter：Codex 剩余用量实时悬浮监视器

## 摘要

Codex Meter 是一款面向 Windows Codex Desktop 用户的轻量级桌面悬浮工具，用于持续显示 Codex 周额度剩余比例、当前活动对话的上下文剩余比例以及周额度重置时间。项目直接读取 Codex Desktop 写入本机的 JSONL 会话日志，不调用网络接口，不上传日志，也不修改 Codex 数据。

项目采用 Windows PowerShell 5.1、WPF/XAML 与内置 .NET API 实现，无需 Flask、Vue、Node.js、Python 或第三方 PowerShell 模块。监视器随 Windows 登录静默启动，仅在检测到 Codex Desktop 运行时显示，并支持窗口置顶、拖动、缩放和设置持久化。

## 完整介绍

### 项目背景

Codex Desktop 的周额度和当前对话上下文会随使用持续消耗。用户若想了解剩余量，通常需要进入相关界面或执行额外操作，难以在连续编码过程中快速掌握当前状态。Codex Meter 将这些信息提取为常驻悬浮视图，使用户无需频繁切换页面即可观察额度变化。

### 项目目标

项目聚焦以下目标：

- 持续展示 Codex 周额度剩余比例和重置时间。
- 展示当前最新活动对话的上下文剩余比例。
- 在不访问外部服务的前提下读取 Codex 本地数据。
- 保持低资源占用，不引入额外运行时和第三方依赖。
- 仅在 Codex Desktop 运行时显示，减少对桌面的干扰。
- 提供拖动、缩放、位置记忆和开机静默启动能力。

### 核心功能

1. **周额度监视**：读取日志中的 `used_percent`，计算周额度剩余比例，并显示额度重置时间。
2. **上下文监视**：根据当前日志事件中的 token 使用量和模型上下文窗口大小，计算上下文剩余比例。
3. **状态颜色提示**：周额度剩余不少于 50% 时显示绿色，20%–49% 时显示黄色，低于 20% 时显示红色；上下文进度条使用蓝色。
4. **自动显隐**：检测 WindowsApps 中的 Codex Desktop 进程。Codex 运行时显示悬浮窗，退出后自动隐藏。
5. **实时跟随日志**：每秒检查最新活动会话日志，仅处理新增内容，避免反复读取完整文件。
6. **窗口交互**：支持拖动窗口；按住 `Ctrl` 滚动鼠标滚轮，可在 60%–120% 范围内缩放。
7. **设置持久化**：窗口坐标和缩放比例保存到 `%LOCALAPPDATA%\CodexMeter\settings.json`。
8. **静默启动**：安装脚本在当前用户的 Windows 启动目录中创建快捷方式，登录系统后自动启动监视器。

### 指标说明

周额度剩余比例的计算公式为：

```text
周额度剩余 = 100 - used_percent
```

当前对话上下文剩余比例的计算公式为：

```text
上下文剩余 = 100 - (当前 token 使用量 / 模型上下文窗口大小 × 100)
```

两项结果都会限制在 0%–100% 范围。右上角显示的百分比是悬浮窗缩放比例，不是用量指标。

相关数据来自 `token_count` 事件中的以下字段：

| 含义 | JSON 字段路径 |
| --- | --- |
| 周额度已用比例 | `payload.rate_limits.primary.used_percent` |
| 周额度重置时间 | `payload.rate_limits.primary.resets_at` |
| 当前 token 使用量 | `payload.info.last_token_usage.total_tokens` |
| 模型上下文窗口大小 | `payload.info.model_context_window` |

日志事件的最小结构示例如下：

```json
{
  "payload": {
    "type": "token_count",
    "rate_limits": {
      "primary": {
        "used_percent": 27,
        "resets_at": 1784692776
      }
    },
    "info": {
      "last_token_usage": {
        "total_tokens": 33702
      },
      "model_context_window": 258400
    }
  }
}
```

### 运行流程

1. Windows 登录后，启动快捷方式以隐藏控制台的方式运行 `CodexMeter.ps1`。
2. 程序每秒检查 Codex Desktop 进程是否存在。
3. 检测到 Codex 后，程序定位 `%USERPROFILE%\.codex\sessions` 中最后修改的 `.jsonl` 文件。
4. 增量日志读取器从上次记录的字节位置继续读取新内容，并处理日志轮换、截断和未写完的行。
5. 解析器筛选最新的 `token_count` 事件，计算周额度和上下文剩余比例。
6. WPF 界面更新百分比、进度条、重置时间和最后更新时间。
7. Codex Desktop 退出后，悬浮窗隐藏，后台监视器继续等待下一次启动。

仅切换 Codex 对话通常不会立即产生新的 `token_count` 事件。因此，切换对话后需要在目标对话中发送消息并等待 Codex 写入日志，面板才会更新该对话的上下文数据。

### 用户交互

- 拖动悬浮窗上方区域可调整位置。
- 按住 `Ctrl` 滚动鼠标滚轮可调整缩放比例。
- 窗口始终置顶，但不显示任务栏图标。
- 缩放只改变整体尺寸，两条进度条始终保留。
- 保存的位置位于屏幕外时，程序会将窗口恢复到主屏幕右上角。

### 数据与隐私

Codex Meter 的用量数据只来自本机会话目录：

```text
%USERPROFILE%\.codex\sessions
```

程序不联网、不上传日志、不调用 Codex API，也不修改会话文件。为完成自身功能，程序还会读取 Codex Desktop 进程路径、写入本地窗口设置；安装脚本会创建当前用户的开机启动快捷方式。安装和更新时执行的 `git clone`、`git pull` 需要联网，但与监视器的数据读取过程无关。

### 适用范围与限制

- 当前仅支持 Windows 10/11 和 Windows Codex Desktop。
- 不承诺支持 macOS、Linux、PowerShell 7、VS Code Codex 扩展或其他 Codex 客户端。
- 指标依赖 Codex Desktop 写入的本地日志；日志格式变化或缺少 `token_count` 时无法更新。
- 程序选择最后修改的会话日志，因此显示的是最新活动会话数据。
- 项目只展示日志提供的数据，不管理或修改账户额度。

## 技术路线

### 总体方案

项目采用“本地日志解析 + 原生桌面悬浮窗”的技术路线。数据层从 Codex JSONL 会话日志中增量提取用量事件，业务层完成数据校验和百分比计算，界面层通过 WPF 更新两个进度条。整个系统运行在 Windows PowerShell 5.1 中，不需要启动 Web 服务，也不需要浏览器渲染界面。

### 技术栈

| 类别 | 技术 | 用途 |
| --- | --- | --- |
| 运行环境 | Windows PowerShell 5.1 | 脚本执行、模块加载、定时轮询和流程控制 |
| 桌面界面 | WPF + XAML | 创建无边框、透明、置顶的悬浮窗口 |
| 基础平台 | .NET Framework 内置 API | 文件读取、进程检测、JSON 处理、屏幕与窗口控制 |
| 数据格式 | JSONL | 读取 Codex 会话事件流 |
| 配置格式 | JSON | 保存窗口位置和缩放比例 |
| 启动管理 | WScript.Shell 快捷方式 | 创建当前用户的 Windows 开机启动项 |
| 测试方式 | PowerShell 自定义断言脚本 | 验证解析、计算、设置、界面契约和安装脚本 |
| 版本管理 | Git + GitHub | 源码管理、发布与协作 |

### 模块划分

```text
src/
├─ CodexMeter.ps1       程序入口、WPF 生命周期、轮询、显隐和交互
├─ CodexMeter.xaml      悬浮窗布局、颜色、字体和进度条
├─ CodexUsage.psm1      日志查找、增量读取、事件解析和进程识别
└─ CodexSettings.psm1   缩放约束、设置读取与持久化

scripts/
├─ install.ps1          创建启动快捷方式并启动监视器
└─ uninstall.ps1        删除快捷方式并停止监视器

tests/
├─ Test-CodexUsage.ps1  自动化测试入口
└─ fixtures/            固定 JSONL 测试样本
```

### 数据流

```text
Codex Desktop
    ↓ 写入
本地 JSONL 会话日志
    ↓ 增量读取
CodexUsage.psm1
    ↓ 校验、解析、计算
CodexMeter.ps1
    ↓ 更新控件
WPF 悬浮窗
```

### 关键实现

#### 1. 增量日志读取

程序使用日志游标记录当前文件路径、已读取字节位置和未完成的行。首次读取时最多扫描文件尾部 2 MB；后续仅读取追加内容。日志被截断或切换到新会话文件时，游标自动重置。

#### 2. 容错解析

解析器忽略空行、损坏 JSON、非 `token_count` 事件和非法数值。百分比计算前会验证数值是否有限，并将最终结果限制在 0%–100%，避免单条异常日志导致监视器退出。

#### 3. Codex Desktop 进程识别

程序同时检查 `ChatGPT` 和 `codex` 进程名称，并要求可执行文件路径位于 WindowsApps 的 `OpenAI.Codex_` 应用目录，从而避免把 VS Code 扩展中的 `codex.exe` 误判为 Codex Desktop。

#### 4. WPF 定时更新

界面线程使用 `DispatcherTimer` 每秒执行一次轮询，确保控件更新发生在 WPF 调度线程。日志暂时没有新事件时保留最近一次有效数据；读取失败时显示等待状态，不清空已有数值。

#### 5. DPI 与多显示器适配

WPF 使用设备无关像素，而 Windows Forms 屏幕信息使用物理像素。程序根据 DPI 比例转换坐标，避免高分辨率缩放环境下窗口被放置到屏幕外。

#### 6. PowerShell 5.1 中文兼容

XAML 文件按 UTF-8 读取。控制器中的动态中文文本使用 Unicode 码点构造，避免 Windows PowerShell 5.1 将无 BOM 的 UTF-8 脚本文本按系统 ANSI 编码解析而产生乱码。

### 为什么不使用 Flask 或 Vue

Flask 适合提供 HTTP 服务，Vue 适合构建浏览器界面；本项目只需要读取本机文件并显示一个原生 Windows 悬浮窗。如果采用 Flask + Vue，需要额外引入 Python、Node.js、Web 服务进程、前端构建产物以及本地端口管理，部署和资源开销明显高于需求。

PowerShell 5.1 和 WPF 已包含在目标 Windows 环境中，更适合实现零额外运行时、低资源占用、开机静默启动和原生窗口交互。因此，本项目选择原生桌面技术，而不是前后端 Web 技术栈。

### 测试与验证

自动化测试覆盖以下内容：

- 周额度和上下文剩余比例计算。
- 损坏日志、非法数值和缺失字段处理。
- 日志追加、未完成行、截断和轮换。
- 最新会话日志选择。
- Codex Desktop 与 VS Code Codex 进程区分。
- 缩放范围和设置持久化。
- XAML 必需控件及窗口属性。
- 安装、卸载脚本的基本约束。

在 Windows PowerShell 5.1 中进入项目根目录后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-CodexUsage.ps1
```

测试成功时输出：

```text
PASS Test-CodexUsage
```

自动化测试通过后，还应执行以下手工验收：

1. 启动 Codex Desktop，确认悬浮窗出现；关闭 Codex，确认窗口隐藏。
2. 在目标对话发送消息，确认两项用量和更新时间随新日志事件变化。
3. 拖动窗口并按住 `Ctrl` 滚动滚轮，确认位置与 60%–120% 缩放能够保存。
4. 在启用 DPI 缩放的显示器上重启监视器，确认窗口位于可视区域。
5. 执行卸载和重新安装，确认快捷方式、进程和设置保留行为符合说明。
