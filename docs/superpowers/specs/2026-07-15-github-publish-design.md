# GitHub 发布与使用文档设计

## 目标

将 Codex Meter 作为公开仓库发布到 `Kate-HB/codex-usage-meter`，让 Windows 用户无需额外运行时即可理解、安装、使用、更新和卸载工具。

## 发布方式

采用“源码仓库 + 一键安装脚本”。默认分支为 `master`，直接推送当前完整提交历史。暂不创建 Release 包、PowerShell Gallery 包或额外构建流程。

## README 受众

主要面向使用 Codex Desktop、熟悉基本 Windows 操作但不熟悉 PowerShell 开发的用户。说明以中文为主，命令均可直接复制执行。

## README 结构

1. 项目简介：解决的问题、运行效果和核心特性。
2. 系统要求：Windows、Codex Desktop、Windows PowerShell 5.1。
3. 快速安装：克隆仓库、进入目录、执行安装脚本。
4. 使用方法：自动显隐、拖动、缩放、指标含义和刷新时机。
5. 数据来源与隐私：只读本机 Codex JSONL 会话日志，不联网，不上传数据。
6. 更新：拉取最新代码并重新执行安装脚本。
7. 卸载：执行卸载脚本，说明设置保留位置。
8. 故障排查：窗口不显示、中文乱码、数值不刷新、执行策略限制、窗口位置异常。
9. 手动运行与开发：直接启动、测试命令、目录结构。
10. 限制：切换对话不会立刻产生新 token 统计，需发送消息并等待 Codex 写入事件。

## 仓库元数据

- 名称：`codex-usage-meter`
- 所有者：`Kate-HB`
- 可见性：公开
- 描述：Windows floating meter for Codex weekly quota and context usage.
- 主题：`codex`、`powershell`、`windows`、`wpf`、`usage-monitor`

## 发布验证

- 本地测试脚本通过。
- 工作树无未提交变更。
- 远端默认分支包含 README、`src`、`scripts`、`tests`。
- GitHub README 可正确显示中文与代码块。
- 从 README 复制的安装、测试、卸载命令路径均与仓库一致。
- 远端仓库为公开状态，描述和主题正确。

## 非目标

- 不发布二进制安装包。
- 不增加第三方依赖。
- 不修改悬浮窗功能或架构。
- 不创建 CI、Release 或包管理器条目。
