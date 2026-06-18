# ClaudeMemBar

ClaudeMemBar 是一个轻量级 macOS 顶部菜单栏看板，用来快速查看本机 [claude-mem](https://github.com/thedotmack/claude-mem) 的运行状态、记忆数量、项目概览，并提供常用入口。

点击菜单栏里的 `记忆` 后，会直接弹出一个小型可视化面板，而不是传统下拉菜单。

## 功能

- 查看 claude-mem worker 是否运行
- 显示 worker 版本、PID、运行时长和 MCP 状态
- 显示记忆、会话、摘要数量
- 点击「记忆」或「摘要」在面板内查看最近条目列表，再点单条查看完整详情
- 切换 claude-mem 记忆生成语言（中文 / English，默认中文）
- 显示最近项目和最近记忆
- 右滑切换到轻量系统页，查看本机 CPU、内存、磁盘、负载和可用温度读数
- 汇总本机 claude-mem 记录到的 Codex、Claude Code、Claude CLI、Codex CLI 等来源 Token 消耗
- 展示 claude-mem 基于本机记忆压缩估算节省的 Token
- 继续右滑切换到「Repo 工作流」页，查看 repo-harness 当前计划、任务、检查和 handoff 状态
- 复制 repo-harness 恢复 Prompt，快速把 Codex / Claude 接回当前仓库上下文
- 手动运行 repo-harness `status`、`doctor`、`adopt --dry-run` 只读命令
- 一键打开 claude-mem 在线页面
- 一键复制本地在线地址
- 一键刷新状态
- 一键重启 claude-mem worker
- 一键打开日志目录
- 首次运行若未检测到 claude-mem，自动安装并启动后再进入面板
- 自动检测 GitHub 新版本并一键更新（非强制）

## 快速安装

打开 [GitHub Releases](https://github.com/AliceDel66/ClaudeMemBar/releases/latest)，下载最新版本安装包：

- 推荐：`ClaudeMemBar-x.y.z.pkg`，双击安装
- 备用：`ClaudeMemBar-x.y.z-macOS.zip`，解压后运行 `install.command`

安装完成后，macOS 顶部菜单栏会出现 `记忆`。首次运行如果未检测到 claude-mem，ClaudeMemBar 会自动执行 `npx claude-mem@latest install` 并启动后台服务。

当前安装包未做 Apple notarization；如果 macOS 拦截，请在「系统设置 > 隐私与安全性」里允许打开，或右键安装文件选择「打开」。

## 依赖

- macOS 13 或更新版本
- Node.js（提供 `npx`，用于在缺失时自动安装 claude-mem）
- 从源码构建时需要 Swift 编译器和 AppKit

首次启动时，如果未检测到 claude-mem，应用会自动执行：

```sh
npx claude-mem@latest install
```

并在安装完成后启动后台服务。如果机器上没有 Node.js，面板会提示先安装 Node.js 再重试。也可手动安装 claude-mem：

```sh
npx claude-mem@latest install
```

claude-mem 项目地址：

```text
https://github.com/thedotmack/claude-mem
```

默认读取：

- Web UI: `http://127.0.0.1:37701`
- Health API: `http://127.0.0.1:37701/api/health`
- 数据库: `~/.claude-mem/claude-mem.db`
- 日志目录: `~/.claude-mem/logs`

## 构建

```sh
./scripts/build.sh
```

构建产物会输出到：

```text
dist/ClaudeMemBar.app
```

## 本地开发安装

```sh
./scripts/install.sh
```

安装脚本会：

1. 构建并签名 `ClaudeMemBar.app`
2. 安装到 `~/Applications/ClaudeMemBar.app`
3. 写入 `~/Library/LaunchAgents/local.claude-mem-bar.plist`
4. 通过 launchd 启动菜单栏应用

## 制作 Release 安装包

```sh
./scripts/package-release.sh
```

脚本会生成：

```text
dist/release/ClaudeMemBar-x.y.z.pkg
dist/release/ClaudeMemBar-x.y.z-macOS.zip
```

推送 `v*` tag 后，GitHub Actions 会自动构建这些安装包并上传到 GitHub Release：

```sh
git tag v1.2.1
git push origin v1.2.1
```

## 使用

安装后，macOS 顶部菜单栏会出现 `记忆`。

点击 `记忆`：

- 直接打开可视化面板
- 再次点击会关闭面板

面板自上而下分为多个区域：

- 顶部标题栏（应用图标 + 实时运行状态指示）
- `记忆概览`（记忆 / 会话 / 摘要 数量）
- `运行状态`（版本、PID、运行时长、MCP、模型）
- `最近活动`（最近项目 + 最近记忆）
- `记忆语言`（中文 / English 切换）
- `快捷操作`（在线 / 复制 / 刷新 / 重启 / 日志 / 退出）
- 底部更新时间

面板使用原生半透明材质，并自动适配浅色与深色模式。

### 系统与 Token 页面

在主面板上横向滑动可切换到第二页。第二页包含：

- `顶部摘要`：全平台 Token、节省率、内存占用
- `系统资源`：CPU 占用、内存占用、磁盘占用、系统负载、可用温度状态
- `Token 经济`：本机全平台总 Token、已节省 Token、读取成本、节省率、来源拆分

Token 数据来自本机 `~/.claude-mem/claude-mem.db`：

- 总 Token 使用 `observations.discovery_tokens + session_summaries.discovery_tokens`
- 来源按 claude-mem 会话来源汇总，例如 Codex、Claude / CLI
- 已节省 Token 为 claude-mem 生成记忆的工作量减去本机记忆文本读取成本的估算值

第二页按轻量化策略采样：

- 常规系统指标每 30 秒刷新一次
- Token 汇总每 60 秒刷新一次
- 温度最多每 120 秒尝试读取一次
- 不调用需要 `sudo` 的 `powermetrics`

macOS 默认不开放完整温度传感器接口。ClaudeMemBar 会自动尝试读取本机已安装的 `osx-cpu-temp` 或 `istats`；如果机器上没有这些工具，温度项会显示 `需工具`，CPU、内存、磁盘、负载和 Token 汇总仍会正常显示。

### 查看记忆与摘要详情

点击「记忆概览」里的 `记忆` 或 `摘要` 数字，面板会切换到详情列表：

- 直接读取本机 `~/.claude-mem/claude-mem.db`，按时间倒序展示最近条目
- 列表在后台线程异步加载，不阻塞界面（无卡顿）
- 每条显示标题、内容摘要和「项目 · 时间」
- 点击任意条目可在面板内查看该条的完整字段（要点、概述、涉及文件等）
- 底部「在浏览器中查看全部」可打开网页查看器
- 点「返回」回到上一级

### 切换记忆语言

`记忆语言` 卡片可在 **中文** 与 **English** 之间切换 claude-mem 生成记忆/摘要所用的语言：

- 默认中文（首次运行会自动写入 `code--zh`）
- 切换会写入 `~/.claude-mem/settings.json` 的 `CLAUDE_MEM_MODE`，并自动重启 worker 生效
- 仅影响切换后新生成的记忆，历史记忆不受影响

### Repo 工作流

第三页「Repo 工作流」把 [repo-harness](https://github.com/Ancienttwo/repo-harness) 的 repo-local 状态压缩到菜单栏里：

- 当前 repo 名称、分支和接入状态
- active plan、最近 contract、`tasks/current.md` 摘要
- `.ai/harness/checks/latest.json` 的检查状态和最近运行时间
- `tasks/reviews/` 里的 review 结论
- `.ai/harness/handoff/resume.md` / `current.md` 的交接摘要
- 一键打开 repo、handoff、current task
- 一键复制中文恢复 Prompt

Repo 列表不自动扫描全盘，使用显式 registry：

```text
~/.claude-mem/claudemembar-repos.json
```

格式：

```json
{
  "repos": [
    {
      "name": "repo-harness",
      "path": "/path/to/repo-harness",
      "enabled": true
    }
  ],
  "activeRepoPath": "/path/to/repo-harness"
}
```

如果 registry 不存在，ClaudeMemBar 只会尝试识别一个已知候选 repo，并在界面显示「可添加」；只有点击「添加」按钮才会写入 registry。

repo-harness CLI 只在你手动点击命令按钮时启动：

- `状态`：在目标 repo 目录运行 `repo-harness status`
- `Doctor`：在目标 repo 目录运行 `repo-harness doctor`
- `DryRun`：在目标 repo 目录运行 `repo-harness adopt --dry-run`

这些命令都有 5 秒超时保护，输出只显示尾部摘要。后台刷新不会启动 repo-harness、Bun、MCP、ChatGPT browser engine 或 CodeGraph。

## 自动更新

应用以 GitHub 仓库的 `VERSION` 文件作为版本来源，在启动时、每 6 小时以及打开面板时（限流 1 小时）检查更新：

- 当 [`main` 分支的 VERSION](https://raw.githubusercontent.com/AliceDel66/ClaudeMemBar/main/VERSION) 高于当前版本时，面板顶部会出现「发现新版本」横幅
- 点「更新」会自动下载最新源码 → 本地编译 → 安装到 `~/Applications` → 重启，全程在横幅内显示进度
- 更新为**非强制**：可点「✕」忽略该版本，或直接关闭面板
- 下载/编译失败时会回退为打开仓库页面

更新只会从固定的 public 仓库 `AliceDel66/ClaudeMemBar` 经 HTTPS 拉取，且仅在你主动点击时执行。

### 发布新版本

修改代码后，自增版本号并推送即可让其他机器收到更新提示：

```sh
./scripts/bump-version.sh          # patch +1
./scripts/bump-version.sh minor    # minor +1
./scripts/bump-version.sh 1.4.2    # 指定版本号
```

脚本会更新 `VERSION`、提交并推送到 `main`。构建时 `build.sh` 会把 `VERSION` 写入 `Info.plist`。

## 开发

源码入口：

```text
Sources/ClaudeMemBar/main.swift
```

应用信息：

```text
Resources/Info.plist
```

版本号唯一来源（构建时注入 `Info.plist`）：

```text
VERSION
```

本项目使用原生 AppKit 实现，没有额外第三方依赖。

## License

MIT
