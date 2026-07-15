# GitHub Publishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Codex Meter as the public GitHub repository `Kate-HB/codex-usage-meter` with a complete Chinese usage guide.

**Architecture:** Keep the repository source-first and dependency-free. Rewrite the root README around copyable PowerShell commands, validate it against the actual scripts, then create and push the repository with GitHub CLI and verify the public remote.

**Tech Stack:** Markdown, Git, GitHub CLI, Windows PowerShell 5.1

---

### Task 1: Rewrite the user guide

**Files:**
- Modify: `README.md`
- Verify: `scripts/install.ps1`
- Verify: `scripts/uninstall.ps1`
- Verify: `src/CodexMeter.ps1`

- [ ] **Step 1: Record the required README contract**

The final README must contain these exact user-facing sections:

```text
Codex Meter
功能
系统要求
快速安装
使用方法
指标说明
数据刷新规则
数据来源与隐私
更新
卸载
故障排查
手动运行
开发与测试
项目结构
已知限制
```

It must include copyable commands for `git clone`, `scripts\install.ps1`, `scripts\uninstall.ps1`, `src\CodexMeter.ps1`, and `tests\Test-CodexUsage.ps1`.

- [ ] **Step 2: Inspect actual commands before writing**

Run:

```powershell
Get-Content scripts\install.ps1 -Encoding UTF8
Get-Content scripts\uninstall.ps1 -Encoding UTF8
Get-Content src\CodexMeter.ps1 -Encoding UTF8 | Select-Object -First 40
```

Expected: install/uninstall paths and PowerShell 5.1 flags match the commands documented below.

- [ ] **Step 3: Rewrite README.md**

Write concise Chinese prose that includes:

```markdown
git clone https://github.com/Kate-HB/codex-usage-meter.git
cd codex-usage-meter
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Explain that the green/yellow/red weekly meter is `100 - used_percent`, the blue meter is the current conversation context remaining, and the header percentage is window zoom. State that switching conversations alone does not create a new `token_count`; users must send a message and wait for Codex to write the event. State that the tool only reads `%USERPROFILE%\.codex\sessions`, makes no network request, and stores window settings in `%LOCALAPPDATA%\CodexMeter\settings.json`.

Troubleshooting must cover: window hidden until Codex Desktop runs; sending a message to refresh context; rerunning install after update; resetting off-screen/invalid settings by removing `settings.json`; PowerShell execution-policy command; UTF-8 Chinese rendering requirement.

- [ ] **Step 4: Validate README contract**

Run a PowerShell check that loads README with `-Encoding UTF8`, verifies every heading and command above, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-CodexUsage.ps1
git diff --check
```

Expected: all required README strings exist, test output is `PASS Test-CodexUsage`, and diff check exits 0.

- [ ] **Step 5: Commit documentation**

```powershell
git add README.md
git commit -m "docs: add complete user guide"
```

### Task 2: Reader-test the documentation

**Files:**
- Modify: `README.md` only if reader testing finds a gap.

- [ ] **Step 1: Test with a context-free reader**

Give a fresh reader only the README and ask it to answer: how to install, what each percentage means, when context updates, whether data leaves the machine, how to resize, how to update, how to uninstall, and what to do if the window is missing.

- [ ] **Step 2: Check ambiguity and contradictions**

Ask the reader to identify assumed knowledge, ambiguous commands, contradictory statements, and missing prerequisites. Fix only concrete gaps.

- [ ] **Step 3: Revalidate and commit any fixes**

Run the Task 1 validation commands. If README changed, commit as:

```powershell
git add README.md
git commit -m "docs: clarify Codex Meter usage"
```

### Task 3: Create and publish the GitHub repository

**Files:**
- No source-file changes expected.

- [ ] **Step 1: Verify local publication state**

```powershell
git status --short
git branch --show-current
gh auth status
```

Expected: clean worktree, branch `master`, authenticated GitHub account `Kate-HB`.

- [ ] **Step 2: Create the public repository and push**

```powershell
gh repo create Kate-HB/codex-usage-meter --public --source . --remote origin --description "Windows floating meter for Codex weekly quota and context usage." --push
```

Expected: repository URL `https://github.com/Kate-HB/codex-usage-meter` and `master` pushed to `origin`.

- [ ] **Step 3: Add repository topics**

```powershell
gh repo edit Kate-HB/codex-usage-meter --add-topic codex --add-topic powershell --add-topic windows --add-topic wpf --add-topic usage-monitor
```

- [ ] **Step 4: Verify the public remote**

```powershell
git remote -v
git ls-remote --heads origin master
gh repo view Kate-HB/codex-usage-meter --json nameWithOwner,isPrivate,url,description,defaultBranchRef,repositoryTopics
```

Expected: `isPrivate=false`, default branch `master`, correct description and five topics, and remote head matching local `git rev-parse HEAD`.

- [ ] **Step 5: Verify published README**

Use GitHub to read `README.md` from `master`; verify Chinese headings, commands, and privacy statement render correctly. Record the final repository URL and pushed commit SHA.
