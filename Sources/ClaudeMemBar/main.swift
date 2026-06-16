import AppKit
import Foundation

private let appName = "ClaudeMemBar"
private let webURL = URL(string: "http://127.0.0.1:37701")!
private let healthURL = URL(string: "http://127.0.0.1:37701/api/health")!
private let databasePath = NSString(string: "~/.claude-mem/claude-mem.db").expandingTildeInPath
private let logsURL = URL(fileURLWithPath: NSString(string: "~/.claude-mem/logs").expandingTildeInPath)

struct Health: Decodable {
    let status: String?
    let version: String?
    let uptime: Int?
    let pid: Int?
    let initialized: Bool?
    let mcpReady: Bool?
    let ai: AIStatus?
}

struct AIStatus: Decodable {
    let provider: String?
    let authMethod: String?
}

struct Counts {
    var observations: Int = 0
    var sessions: Int = 0
    var summaries: Int = 0
    var projects: [String] = []
    var lastTitle: String?
    var lastCreatedAt: String?
}

final class ToolbarButton: NSButton {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedRed: 0.875, green: 0.886, blue: 0.910, alpha: 1.0).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor(calibratedRed: 0.925, green: 0.932, blue: 0.948, alpha: 1.0).cgColor
    }
}

final class DashboardWindowController: NSWindowController {
    private let panelWidth: CGFloat = 376
    private let panelHeight: CGFloat = 506
    private let accent = NSColor(calibratedRed: 0.41, green: 0.24, blue: 0.90, alpha: 1.0)
    private let accentSoft = NSColor(calibratedRed: 0.93, green: 0.90, blue: 1.0, alpha: 1.0)
    private let panelBackground = NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.985, alpha: 0.98)
    private let cardBackground = NSColor(calibratedRed: 0.995, green: 0.997, blue: 1.0, alpha: 0.96)
    private let controlBackground = NSColor(calibratedRed: 0.925, green: 0.932, blue: 0.948, alpha: 1.0)
    private let mutedText = NSColor(calibratedRed: 0.43, green: 0.47, blue: 0.56, alpha: 1.0)
    private let darkText = NSColor(calibratedRed: 0.075, green: 0.095, blue: 0.15, alpha: 1.0)

    private let statusDot = NSView()
    private let statusPillView = NSView()
    private let statusBadge = NSTextField(labelWithString: "检查中")
    private let workerValue = NSTextField(labelWithString: "--")
    private let aiValue = NSTextField(labelWithString: "--")
    private let memoryValue = NSTextField(labelWithString: "0")
    private let sessionValue = NSTextField(labelWithString: "0")
    private let summaryValue = NSTextField(labelWithString: "0")
    private let projectsValue = NSTextField(labelWithString: "暂无")
    private let latestValue = NSTextField(labelWithString: "暂无")
    private let updatedValue = NSTextField(labelWithString: "--")

    init(
        actionTarget: AnyObject,
        openSelector: Selector,
        copySelector: Selector,
        refreshSelector: Selector,
        restartSelector: Selector,
        logsSelector: Selector,
        quitSelector: Selector
    ) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClaudeMem 状态看板"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.level = .statusBar

        super.init(window: panel)
        panel.contentView = buildContent(
            actionTarget: actionTarget,
            openSelector: openSelector,
            copySelector: copySelector,
            refreshSelector: refreshSelector,
            restartSelector: restartSelector,
            logsSelector: logsSelector,
            quitSelector: quitSelector
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle(health: Health?, counts: Counts, refreshedAt: Date, relativeTo button: NSStatusBarButton) {
        if window?.isVisible == true {
            window?.orderOut(nil)
            return
        }
        show(health: health, counts: counts, refreshedAt: refreshedAt, relativeTo: button)
    }

    func show(health: Health?, counts: Counts, refreshedAt: Date, relativeTo button: NSStatusBarButton) {
        update(health: health, counts: counts, refreshedAt: refreshedAt)
        position(relativeTo: button)
        window?.orderFrontRegardless()
    }

    func update(health: Health?, counts: Counts, refreshedAt: Date) {
        let ready = health?.status == "ok" || health?.status == "ready"
        let statusColor = ready ? NSColor.systemGreen : NSColor.systemRed
        statusBadge.stringValue = ready ? "运行中" : "离线"
        statusBadge.textColor = statusColor
        statusDot.layer?.backgroundColor = statusColor.cgColor
        statusPillView.layer?.backgroundColor = statusColor.withAlphaComponent(0.16).cgColor

        if let health {
            let version = health.version ?? "unknown"
            let pid = health.pid.map(String.init) ?? "--"
            let uptime = formatUptime(health.uptime ?? 0)
            let mcp = health.mcpReady == true ? "MCP 就绪" : "MCP 未就绪"
            workerValue.stringValue = "v\(version) · PID \(pid) · \(uptime) · \(mcp)"
            aiValue.stringValue = "\(health.ai?.provider ?? "unknown") · \(health.ai?.authMethod ?? "未检测到认证信息")"
        } else {
            workerValue.stringValue = "无法连接 127.0.0.1:37701"
            aiValue.stringValue = "AI 状态暂无"
        }

        memoryValue.stringValue = "\(counts.observations)"
        sessionValue.stringValue = "\(counts.sessions)"
        summaryValue.stringValue = "\(counts.summaries)"
        projectsValue.stringValue = counts.projects.isEmpty ? "暂无项目记忆" : counts.projects.prefix(2).joined(separator: "、")

        if let title = counts.lastTitle, !title.isEmpty {
            latestValue.stringValue = title
        } else {
            latestValue.stringValue = "暂无记忆。若一直为空，请确认 Claude Code 已登录。"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        updatedValue.stringValue = formatter.string(from: refreshedAt)
    }

    private func position(relativeTo button: NSStatusBarButton) {
        guard let window, let buttonWindow = button.window else {
            window?.center()
            return
        }

        let screen = buttonWindow.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonFrameInWindow)
        var originX = buttonFrame.midX - window.frame.width / 2
        originX = max(visibleFrame.minX + 8, min(originX, visibleFrame.maxX - window.frame.width - 8))

        let originY = visibleFrame.maxY - window.frame.height - 8
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func buildContent(
        actionTarget: AnyObject,
        openSelector: Selector,
        copySelector: Selector,
        refreshSelector: Selector,
        restartSelector: Selector,
        logsSelector: Selector,
        quitSelector: Selector
    ) -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = panelBackground.cgColor
        root.layer?.cornerRadius = 18
        root.layer?.cornerCurve = .continuous
        root.layer?.borderColor = NSColor(calibratedWhite: 0.76, alpha: 0.72).cgColor
        root.layer?.borderWidth = 1
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = 0.20
        root.layer?.shadowRadius = 24
        root.layer?.shadowOffset = CGSize(width: 0, height: -8)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(statusSection())
        stack.addArrangedSubview(memorySection())
        stack.addArrangedSubview(contentSection())
        stack.addArrangedSubview(actionsSection(
            target: actionTarget,
            openSelector: openSelector,
            copySelector: copySelector,
            refreshSelector: refreshSelector,
            restartSelector: restartSelector,
            logsSelector: logsSelector,
            quitSelector: quitSelector
        ))

        return root
    }

    private func header() -> NSView {
        let icon = iconTile(symbol: "brain.head.profile", size: 40, symbolSize: 24)

        let title = label("ClaudeMem 监控", size: 20, weight: .bold)
        title.textColor = darkText
        title.maximumNumberOfLines = 1

        let subtitle = label("状态、记忆和常用入口", size: 12, weight: .medium)
        subtitle.textColor = mutedText
        subtitle.maximumNumberOfLines = 1

        let copy = NSStackView(views: [title, subtitle])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3

        let row = NSStackView(views: [icon, copy])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: panelWidth - 32),
            row.heightAnchor.constraint(equalToConstant: 44)
        ])
        return row
    }

    private func statusSection() -> NSView {
        let top = NSStackView(views: [statusPill(), updatedLine()])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.distribution = .equalSpacing
        top.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.widthAnchor.constraint(equalToConstant: panelWidth - 62)
        ])

        workerValue.font = .systemFont(ofSize: 12, weight: .semibold)
        workerValue.textColor = darkText
        workerValue.maximumNumberOfLines = 1
        workerValue.lineBreakMode = .byTruncatingTail

        aiValue.font = .systemFont(ofSize: 11, weight: .regular)
        aiValue.textColor = mutedText
        aiValue.maximumNumberOfLines = 1
        aiValue.lineBreakMode = .byTruncatingTail

        let body = NSStackView(views: [top, workerValue, aiValue])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 6
        return sectionCard(title: "运行状态", symbol: "cpu", content: body, height: 104)
    }

    private func memorySection() -> NSView {
        let row = NSStackView(views: [
            metricTile(title: "记忆", value: memoryValue),
            metricTile(title: "会话", value: sessionValue),
            metricTile(title: "摘要", value: summaryValue)
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return sectionCard(title: "记忆概览", symbol: "externaldrive.connected.to.line.below", content: row, height: 84, highlighted: true)
    }

    private func contentSection() -> NSView {
        projectsValue.font = .systemFont(ofSize: 12, weight: .medium)
        projectsValue.textColor = mutedText
        projectsValue.maximumNumberOfLines = 1
        projectsValue.lineBreakMode = .byTruncatingTail

        latestValue.font = .systemFont(ofSize: 12, weight: .regular)
        latestValue.textColor = mutedText
        latestValue.maximumNumberOfLines = 2
        latestValue.lineBreakMode = .byTruncatingTail

        let body = NSStackView(views: [
            keyValueRow("项目", projectsValue),
            separator(),
            keyValueRow("最近", latestValue)
        ])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        return sectionCard(title: "内容", symbol: "folder", content: body, height: 94)
    }

    private func actionsSection(
        target: AnyObject,
        openSelector: Selector,
        copySelector: Selector,
        refreshSelector: Selector,
        restartSelector: Selector,
        logsSelector: Selector,
        quitSelector: Selector
    ) -> NSView {
        let row1 = actionRow([
            actionButton("在线", symbol: "arrow.up.right.square", target: target, action: openSelector),
            actionButton("复制", symbol: "link", target: target, action: copySelector),
            actionButton("刷新", symbol: "arrow.clockwise", target: target, action: refreshSelector)
        ])
        let row2 = actionRow([
            actionButton("重启", symbol: "arrow.triangle.2.circlepath", target: target, action: restartSelector),
            actionButton("日志", symbol: "doc.text", target: target, action: logsSelector),
            actionButton("退出", symbol: "power", target: target, action: quitSelector)
        ])

        let body = NSStackView(views: [row1, row2])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        return sectionCard(title: "快捷入口", symbol: "square.grid.2x2", content: body, height: 110)
    }

    private func statusPill() -> NSView {
        let pill = statusPillView
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.16).cgColor
        pill.layer?.cornerRadius = 13
        pill.layer?.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        statusDot.layer?.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        statusBadge.font = .systemFont(ofSize: 13, weight: .semibold)
        statusBadge.textColor = .systemGreen

        let row = NSStackView(views: [statusDot, statusBadge])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)

        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(equalToConstant: 84),
            pill.heightAnchor.constraint(equalToConstant: 26),
            row.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10)
        ])

        return pill
    }

    private func updatedLine() -> NSView {
        let clock = symbol("clock", pointSize: 12, weight: .regular, color: mutedText)
        let prefix = label("更新", size: 12, weight: .regular)
        prefix.textColor = mutedText
        updatedValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        updatedValue.textColor = mutedText

        let row = NSStackView(views: [clock, prefix, updatedValue])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        return row
    }

    private func sectionCard(title: String, symbol symbolName: String, content: NSView, height: CGFloat, highlighted: Bool = false) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = cardBackground.cgColor
        container.layer?.borderColor = (highlighted ? accent.withAlphaComponent(0.62) : NSColor(calibratedWhite: 0.82, alpha: 0.82)).cgColor
        container.layer?.borderWidth = highlighted ? 1.25 : 1
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = highlighted ? 0.07 : 0.055
        container.layer?.shadowRadius = highlighted ? 10 : 8
        container.layer?.shadowOffset = CGSize(width: 0, height: -3)
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = label(title, size: 12, weight: .semibold)
        titleLabel.textColor = darkText

        let titleRow = NSStackView(views: [symbol(symbolName, pointSize: 13, weight: .semibold, color: accent), titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 7

        let stack = NSStackView(views: [titleRow, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: panelWidth - 32),
            container.heightAnchor.constraint(equalToConstant: height),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func metricTile(title: String, value: NSTextField) -> NSView {
        value.font = .systemFont(ofSize: 25, weight: .bold)
        value.textColor = accent
        value.alignment = .center

        let titleLabel = label(title, size: 11, weight: .medium)
        titleLabel.textColor = mutedText
        titleLabel.alignment = .center

        let stack = NSStackView(views: [value, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 100),
            stack.heightAnchor.constraint(equalToConstant: 50)
        ])
        return stack
    }

    private func keyValueRow(_ key: String, _ value: NSTextField) -> NSView {
        let keyLabel = label(key, size: 12, weight: .semibold)
        keyLabel.textColor = darkText
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            keyLabel.widthAnchor.constraint(equalToConstant: 40)
        ])

        let row = NSStackView(views: [keyLabel, value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: panelWidth - 62)
        ])
        return row
    }

    private func actionRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        return row
    }

    private func actionButton(_ title: String, symbol symbolName: String, target: AnyObject, action: Selector) -> NSButton {
        let button = ToolbarButton(title: title, target: target, action: action)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = false
        button.contentTintColor = darkText
        button.wantsLayer = true
        button.layer?.backgroundColor = controlBackground.cgColor
        button.layer?.cornerRadius = 7
        button.layer?.cornerCurve = .continuous
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 103),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        return button
    }

    private func iconTile(symbol symbolName: String, size: CGFloat, symbolSize: CGFloat) -> NSView {
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.backgroundColor = accentSoft.cgColor
        tile.layer?.cornerRadius = 11
        tile.layer?.cornerCurve = .continuous
        tile.translatesAutoresizingMaskIntoConstraints = false

        let image = symbol(symbolName, pointSize: symbolSize, weight: .semibold, color: accent)
        image.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(image)

        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: size),
            tile.heightAnchor.constraint(equalToConstant: size),
            image.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])

        return tile
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: panelWidth - 62),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])
        return line
    }

    private func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImageView {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = color
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func formatUptime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时 \(minutes % 60) 分钟" }
        let days = hours / 24
        return "\(days) 天 \(hours % 24) 小时"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private lazy var dashboard = DashboardWindowController(
        actionTarget: self,
        openSelector: #selector(openWebUI),
        copySelector: #selector(copyWebURL),
        refreshSelector: #selector(refreshNow),
        restartSelector: #selector(restartWorker),
        logsSelector: #selector(openLogs),
        quitSelector: #selector(quit)
    )
    private var timer: Timer?
    private var lastHealth: Health?
    private var lastCounts = Counts()
    private var lastRefresh = Date()
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "ClaudeMemBar")
            button.imagePosition = .imageLeading
            button.title = " 记忆"
            button.toolTip = "ClaudeMemBar"
            button.target = self
            button.action = #selector(toggleDashboard)
        }
    }

    @objc private func openWebUI() {
        NSWorkspace.shared.open(webURL)
    }

    @objc private func toggleDashboard() {
        guard let button = statusItem.button else { return }
        dashboard.toggle(health: lastHealth, counts: lastCounts, refreshedAt: lastRefresh, relativeTo: button)
        refresh()
    }

    @objc private func copyWebURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(webURL.absoluteString, forType: .string)
        setTransientStatus("地址已复制")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.render()
        }
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(logsURL)
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func restartWorker() {
        setTransientStatus("正在重启 Worker...")
        DispatchQueue.global(qos: .utility).async {
            let uid = getuid()
            _ = Self.run("/bin/launchctl", ["kickstart", "-k", "gui/\(uid)/com.claude-mem.worker"])
            Thread.sleep(forTimeInterval: 2.0)
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let group = DispatchGroup()
        var fetchedHealth: Health?
        var fetchedCounts = Counts()

        group.enter()
        fetchHealth { health in
            fetchedHealth = health
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            fetchedCounts = self.fetchCounts()
            group.leave()
        }

        group.notify(queue: .main) {
            self.lastHealth = fetchedHealth
            self.lastCounts = fetchedCounts
            self.lastRefresh = Date()
            self.isRefreshing = false
            self.render()
        }
    }

    private func fetchHealth(completion: @escaping (Health?) -> Void) {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 3

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data else {
                completion(nil)
                return
            }
            completion(try? JSONDecoder().decode(Health.self, from: data))
        }.resume()
    }

    private func fetchCounts() -> Counts {
        var counts = Counts()
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return counts
        }

        let sql = """
        select 'observations|' || count(*) from observations;
        select 'sessions|' || count(*) from sdk_sessions;
        select 'summaries|' || count(*) from session_summaries;
        select 'project|' || project from observations group by project order by max(created_at_epoch) desc limit 5;
        select 'latest|' || coalesce(title, '(untitled)') || '|' || created_at from observations order by created_at_epoch desc limit 1;
        """

        let output = Self.run("/usr/bin/sqlite3", [databasePath, sql]).stdout
        for line in output.split(separator: "\n").map(String.init) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { continue }

            switch key {
            case "observations":
                counts.observations = Int(parts.dropFirst().first ?? "0") ?? 0
            case "sessions":
                counts.sessions = Int(parts.dropFirst().first ?? "0") ?? 0
            case "summaries":
                counts.summaries = Int(parts.dropFirst().first ?? "0") ?? 0
            case "project":
                if let project = parts.dropFirst().first, !project.isEmpty {
                    counts.projects.append(project)
                }
            case "latest":
                counts.lastTitle = parts.count > 1 ? parts[1] : nil
                counts.lastCreatedAt = parts.count > 2 ? parts[2] : nil
            default:
                continue
            }
        }

        return counts
    }

    private func render() {
        let isReady = lastHealth?.status == "ok" || lastHealth?.status == "ready"
        let statusText = isReady ? "运行中" : "离线"
        let symbolName = isReady ? "brain.head.profile" : "exclamationmark.triangle"

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: statusText)
            button.title = lastCounts.observations > 0 ? " \(lastCounts.observations)" : " 记忆"
            button.toolTip = "ClaudeMemBar: \(statusText)"
        }
        dashboard.update(health: lastHealth, counts: lastCounts, refreshedAt: lastRefresh)
    }

    private func setTransientStatus(_ title: String) {
        if let button = statusItem.button {
            button.title = " ..."
            button.toolTip = "ClaudeMemBar: \(title)"
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
