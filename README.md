# ClaudeMemBar

ClaudeMemBar 是一个轻量级 macOS 顶部菜单栏看板，用来快速查看本机 [claude-mem](https://github.com/thedotmack/claude-mem) 的运行状态、记忆数量、项目概览，并提供常用入口。

点击菜单栏里的 `记忆` 后，会直接弹出一个小型可视化面板，而不是传统下拉菜单。

## 功能

- 查看 claude-mem worker 是否运行
- 显示 worker 版本、PID、运行时长和 MCP 状态
- 显示记忆、会话、摘要数量
- 显示最近项目和最近记忆
- 一键打开 claude-mem 在线页面
- 一键复制本地在线地址
- 一键刷新状态
- 一键重启 claude-mem worker
- 一键打开日志目录

## 依赖

- macOS 13 或更新版本
- Swift 编译器和 AppKit
- 已安装并运行 claude-mem

安装 claude-mem：

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

## 安装到本机

```sh
./scripts/install.sh
```

安装脚本会：

1. 构建并签名 `ClaudeMemBar.app`
2. 安装到 `~/Applications/ClaudeMemBar.app`
3. 写入 `~/Library/LaunchAgents/local.claude-mem-bar.plist`
4. 通过 launchd 启动菜单栏应用

## 使用

安装后，macOS 顶部菜单栏会出现 `记忆`。

点击 `记忆`：

- 直接打开可视化面板
- 再次点击会关闭面板

面板分为四个区域：

- `运行状态`
- `记忆概览`
- `内容`
- `快捷入口`

## 开发

源码入口：

```text
Sources/ClaudeMemBar/main.swift
```

应用信息：

```text
Resources/Info.plist
```

本项目使用原生 AppKit 实现，没有额外第三方依赖。

## License

MIT
