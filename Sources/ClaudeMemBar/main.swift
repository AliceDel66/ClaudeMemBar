import AppKit
import Foundation

private let appName = "ClaudeMemBar"
private let webURL = URL(string: "http://127.0.0.1:37701")!
private let healthURL = URL(string: "http://127.0.0.1:37701/api/health")!
private let databasePath = NSString(string: "~/.claude-mem/claude-mem.db").expandingTildeInPath
private let logsURL = URL(fileURLWithPath: NSString(string: "~/.claude-mem/logs").expandingTildeInPath)

// MARK: - Data

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

// MARK: - Theme

enum Theme {
    static let accent = dynamic(
        light: NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.88, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.66, green: 0.58, blue: 1.0, alpha: 1.0)
    )
    static let accentSoft = dynamic(
        light: NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.88, alpha: 0.12),
        dark: NSColor(calibratedRed: 0.66, green: 0.58, blue: 1.0, alpha: 0.18)
    )
    static let cardFill = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.06)
    )
    static let cardBorder = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.07),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )
    static let controlFill = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.045),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )
    static let controlHover = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.085),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.16)
    )
    static let online = NSColor.systemGreen
    static let offline = NSColor.systemRed
    static let warning = NSColor.systemOrange

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    static func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }
}

// MARK: - Action tile

final class ActionTile: NSView {
    private weak var target: AnyObject?
    private let action: Selector
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isHovered = false

    init(title: String, symbol: String, tint: NSColor, target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Theme.controlFill.cgColor

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = tint
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentHuggingPriority(.required, for: .vertical)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = tint
        titleLabel.alignment = .center

        let stack = NSStackView(views: [iconView, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 50),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isHovered ? Theme.controlHover : Theme.controlFill).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackground()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

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
        isHovered = true
        applyBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyBackground()
    }

    override func mouseDown(with event: NSEvent) {
        isHovered = true
        applyBackground()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isHovered = inside
        applyBackground()
        if inside, let target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

// MARK: - Dashboard

final class DashboardWindowController: NSWindowController {
    private let panelWidth: CGFloat = 360
    private var contentWidth: CGFloat { panelWidth - 32 }
    private var cardInnerWidth: CGFloat { panelWidth - 32 - 24 }

    private let statusDot = NSView()
    private let statusBadge = NSTextField(labelWithString: "检查中")
    private let statusPillView = NSView()

    private let memoryValue = NSTextField(labelWithString: "0")
    private let sessionValue = NSTextField(labelWithString: "0")
    private let summaryValue = NSTextField(labelWithString: "0")

    private let versionValue = NSTextField(labelWithString: "--")
    private let pidValue = NSTextField(labelWithString: "--")
    private let uptimeValue = NSTextField(labelWithString: "--")
    private let mcpValue = NSTextField(labelWithString: "--")
    private let modelValue = NSTextField(labelWithString: "--")

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
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 520),
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

        let root = buildContent(
            actionTarget: actionTarget,
            openSelector: openSelector,
            copySelector: copySelector,
            refreshSelector: refreshSelector,
            restartSelector: restartSelector,
            logsSelector: logsSelector,
            quitSelector: quitSelector
        )
        panel.contentView = root
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(root.fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        let statusColor = ready ? Theme.online : Theme.offline
        statusBadge.stringValue = ready ? "运行中" : "离线"
        statusBadge.textColor = statusColor
        statusDot.layer?.backgroundColor = statusColor.cgColor
        statusPillView.layer?.backgroundColor = statusColor.withAlphaComponent(0.16).cgColor

        if let health {
            versionValue.stringValue = "v\(health.version ?? "未知")"
            pidValue.stringValue = health.pid.map(String.init) ?? "--"
            uptimeValue.stringValue = formatUptime(health.uptime ?? 0)
            let mcpReady = health.mcpReady == true
            mcpValue.stringValue = mcpReady ? "就绪" : "未就绪"
            mcpValue.textColor = mcpReady ? Theme.online : Theme.warning
            if let provider = health.ai?.provider, !provider.isEmpty {
                if let auth = health.ai?.authMethod, !auth.isEmpty {
                    modelValue.stringValue = "\(provider) · \(auth)"
                } else {
                    modelValue.stringValue = provider
                }
            } else {
                modelValue.stringValue = "未检测到模型"
            }
        } else {
            versionValue.stringValue = "--"
            pidValue.stringValue = "--"
            uptimeValue.stringValue = "--"
            mcpValue.stringValue = "未连接"
            mcpValue.textColor = Theme.offline
            modelValue.stringValue = "无法连接 127.0.0.1:37701"
        }

        memoryValue.stringValue = "\(counts.observations)"
        sessionValue.stringValue = "\(counts.sessions)"
        summaryValue.stringValue = "\(counts.summaries)"
        projectsValue.stringValue = counts.projects.isEmpty
            ? "暂无项目记忆"
            : counts.projects.prefix(2).joined(separator: "、")

        if let title = counts.lastTitle, !title.isEmpty {
            latestValue.stringValue = title
        } else {
            latestValue.stringValue = "暂无记忆，请确认 Claude Code 已登录"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        updatedValue.stringValue = "更新于 \(formatter.string(from: refreshedAt))"
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

    // MARK: Build

    private func buildContent(
        actionTarget: AnyObject,
        openSelector: Selector,
        copySelector: Selector,
        refreshSelector: Selector,
        restartSelector: Selector,
        logsSelector: Selector,
        quitSelector: Selector
    ) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderColor = Theme.cardBorder.cgColor
        container.layer?.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blur)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: panelWidth),
            blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blur.topAnchor.constraint(equalTo: container.topAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(statsCard())
        stack.addArrangedSubview(runtimeCard())
        stack.addArrangedSubview(activityCard())
        stack.addArrangedSubview(actionsCard(
            target: actionTarget,
            openSelector: openSelector,
            copySelector: copySelector,
            refreshSelector: refreshSelector,
            restartSelector: restartSelector,
            logsSelector: logsSelector,
            quitSelector: quitSelector
        ))
        stack.addArrangedSubview(footer())

        return container
    }

    private func header() -> NSView {
        let icon = iconTile(symbol: "brain.head.profile", size: 38, symbolSize: 21)

        let title = label("ClaudeMem", size: 16, weight: .bold)
        title.textColor = .labelColor
        let subtitle = label("记忆监控面板", size: 11.5, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let copy = NSStackView(views: [title, subtitle])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 1

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, copy, spacer, headerStatusPill()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        return row
    }

    private func headerStatusPill() -> NSView {
        let pill = statusPillView
        pill.wantsLayer = true
        pill.layer?.backgroundColor = Theme.online.withAlphaComponent(0.16).cgColor
        pill.layer?.cornerRadius = 12
        pill.layer?.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = Theme.online.cgColor
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        statusBadge.font = .systemFont(ofSize: 12, weight: .semibold)
        statusBadge.textColor = Theme.online

        let row = NSStackView(views: [statusDot, statusBadge])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)

        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 24),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        return pill
    }

    private func statsCard() -> NSView {
        let memory = statTile(memoryValue, "记忆")
        let session = statTile(sessionValue, "会话")
        let summary = statTile(summaryValue, "摘要")

        let row = NSStackView(views: [memory, divider(), session, divider(), summary])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            session.widthAnchor.constraint(equalTo: memory.widthAnchor),
            summary.widthAnchor.constraint(equalTo: memory.widthAnchor)
        ])

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = Theme.accentSoft.cgColor
        container.layer?.borderColor = Theme.accent.withAlphaComponent(0.22).cgColor
        container.layer?.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentWidth),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        return container
    }

    private func runtimeCard() -> NSView {
        configureValue(versionValue, weight: .semibold)
        configureValue(pidValue, weight: .semibold)
        configureValue(uptimeValue, weight: .semibold)
        configureValue(mcpValue, weight: .semibold)
        configureValue(modelValue, weight: .medium)
        modelValue.textColor = .secondaryLabelColor

        let rows = NSStackView(views: [
            infoRow(infoCell("版本", versionValue), infoCell("PID", pidValue)),
            infoRow(infoCell("运行", uptimeValue), infoCell("MCP", mcpValue)),
            infoCell("模型", modelValue)
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        return card(title: "运行状态", symbol: "cpu", content: rows)
    }

    private func activityCard() -> NSView {
        configureValue(projectsValue, weight: .medium)
        projectsValue.textColor = .secondaryLabelColor
        configureValue(latestValue, weight: .medium)
        latestValue.textColor = .secondaryLabelColor

        let rows = NSStackView(views: [
            infoCell("项目", projectsValue),
            infoCell("最近", latestValue)
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        return card(title: "最近活动", symbol: "clock.arrow.circlepath", content: rows)
    }

    private func actionsCard(
        target: AnyObject,
        openSelector: Selector,
        copySelector: Selector,
        refreshSelector: Selector,
        restartSelector: Selector,
        logsSelector: Selector,
        quitSelector: Selector
    ) -> NSView {
        let row1 = tileRow([
            ActionTile(title: "在线", symbol: "safari", tint: Theme.accent, target: target, action: openSelector),
            ActionTile(title: "复制", symbol: "link", tint: .labelColor, target: target, action: copySelector),
            ActionTile(title: "刷新", symbol: "arrow.clockwise", tint: .labelColor, target: target, action: refreshSelector)
        ])
        let row2 = tileRow([
            ActionTile(title: "重启", symbol: "arrow.triangle.2.circlepath", tint: Theme.warning, target: target, action: restartSelector),
            ActionTile(title: "日志", symbol: "doc.text", tint: .labelColor, target: target, action: logsSelector),
            ActionTile(title: "退出", symbol: "power", tint: Theme.offline, target: target, action: quitSelector)
        ])
        let rows = NSStackView(views: [row1, row2])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        return card(title: "快捷操作", symbol: "square.grid.2x2", content: rows)
    }

    private func footer() -> NSView {
        let clock = symbol("clock", pointSize: 11, weight: .regular, color: .tertiaryLabelColor)
        updatedValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        updatedValue.textColor = .tertiaryLabelColor

        let row = NSStackView(views: [clock, updatedValue])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        return row
    }

    // MARK: Components

    private func card(title: String, symbol symbolName: String, content: NSView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = Theme.cardFill.cgColor
        container.layer?.borderColor = Theme.cardBorder.cgColor
        container.layer?.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = label(title, size: 11.5, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        let titleRow = NSStackView(views: [
            symbol(symbolName, pointSize: 12, weight: .semibold, color: Theme.accent),
            titleLabel
        ])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6

        let stack = NSStackView(views: [titleRow, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func statTile(_ value: NSTextField, _ title: String) -> NSView {
        value.font = Theme.roundedFont(26, .bold)
        value.textColor = Theme.accent
        value.alignment = .center

        let titleLabel = label(title, size: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center

        let stack = NSStackView(views: [value, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        return stack
    }

    private func infoCell(_ key: String, _ value: NSTextField) -> NSView {
        let keyLabel = label(key, size: 12, weight: .medium)
        keyLabel.textColor = .tertiaryLabelColor
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            keyLabel.widthAnchor.constraint(equalToConstant: 34)
        ])

        let row = NSStackView(views: [keyLabel, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func infoRow(_ left: NSView, _ right: NSView) -> NSView {
        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: cardInnerWidth)
        ])
        return row
    }

    private func tileRow(_ tiles: [ActionTile]) -> NSView {
        let row = NSStackView(views: tiles)
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: cardInnerWidth)
        ])
        return row
    }

    private func configureValue(_ field: NSTextField, weight: NSFont.Weight) {
        field.font = .systemFont(ofSize: 12.5, weight: weight)
        field.textColor = .labelColor
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func iconTile(symbol symbolName: String, size: CGFloat, symbolSize: CGFloat) -> NSView {
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.backgroundColor = Theme.accentSoft.cgColor
        tile.layer?.cornerRadius = 10
        tile.layer?.cornerCurve = .continuous
        tile.translatesAutoresizingMaskIntoConstraints = false

        let image = symbol(symbolName, pointSize: symbolSize, weight: .semibold, color: Theme.accent)
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

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.cardBorder.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 30)
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
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func formatUptime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时" }
        let days = hours / 24
        return "\(days) 天 \(hours % 24) 小时"
    }
}

// MARK: - App

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
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: appName)
            button.imagePosition = .imageLeading
            button.title = " 记忆"
            button.toolTip = appName
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
            button.toolTip = "\(appName): \(statusText)"
        }
        dashboard.update(health: lastHealth, counts: lastCounts, refreshedAt: lastRefresh)
    }

    private func setTransientStatus(_ title: String) {
        if let button = statusItem.button {
            button.title = " ..."
            button.toolTip = "\(appName): \(title)"
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
