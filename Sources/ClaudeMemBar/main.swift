import AppKit
import Foundation

private let appName = "ClaudeMemBar"
private let webURL = URL(string: "http://127.0.0.1:37701")!
private let healthURL = URL(string: "http://127.0.0.1:37701/api/health")!
private let databasePath = NSString(string: "~/.claude-mem/claude-mem.db").expandingTildeInPath
private let settingsPath = NSString(string: "~/.claude-mem/settings.json").expandingTildeInPath
private let pluginMarkerPath = NSString(string: "~/.claude/plugins/marketplaces/thedotmack").expandingTildeInPath
private let logsURL = URL(fileURLWithPath: NSString(string: "~/.claude-mem/logs").expandingTildeInPath)
private let claudeMemRepoURL = URL(string: "https://github.com/thedotmack/claude-mem")!
private let nodeDownloadURL = URL(string: "https://nodejs.org/zh-cn/download")!
private let workerLabel = "com.claude-mem.worker"

// GitHub 热更新：版本/源码均来自用户自己的 public 仓库（HTTPS，固定指向）
private let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
private let rawVersionURL = URL(string: "https://raw.githubusercontent.com/AliceDel66/ClaudeMemBar/main/VERSION")!
private let tarballURL = URL(string: "https://github.com/AliceDel66/ClaudeMemBar/archive/refs/heads/main.tar.gz")!
private let repoWebURL = URL(string: "https://github.com/AliceDel66/ClaudeMemBar")!
private let ignoredVersionKey = "ignoredUpdateVersion"
private let languageDefaultAppliedKey = "cmb.languageDefaultApplied"

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

struct SystemStats {
    var cpuTemperature: String = "不可用"
    var gpuTemperature: String = "不可用"
    var memoryUsage: String = "--"
    var memoryDetail: String = "等待刷新"
    var loadAverage: String = "--"
}

struct TokenStats {
    var totalTokens: Int = 0
    var readTokens: Int = 0
    var savedTokens: Int = 0
    var sourceBreakdown: String = "暂无数据"

    var savingsRate: Int {
        guard totalTokens > 0 else { return 0 }
        return max(0, min(99, Int((Double(savedTokens) / Double(totalTokens) * 100.0).rounded())))
    }
}

// 详情列表条目（由 `sqlite3 -json` 解码，字段名对应表列名）
struct MemoryItem: Decodable {
    let id: Int
    let title: String?
    let subtitle: String?
    let project: String?
    let type: String?
    let narrative: String?
    let facts: String?
    let concepts: String?
    let files_read: String?
    let files_modified: String?
    let text: String?
    let created_at_epoch: Int?
}

struct SummaryItem: Decodable {
    let id: Int
    let project: String?
    let request: String?
    let investigated: String?
    let learned: String?
    let completed: String?
    let next_steps: String?
    let created_at_epoch: Int?
}

enum DetailKind {
    case memories
    case summaries

    var title: String { self == .memories ? "记忆" : "摘要" }
    var symbol: String { self == .memories ? "brain.head.profile" : "doc.text.magnifyingglass" }
}

enum Language: Int {
    case chinese = 0
    case english = 1
}

enum UpdateUIState {
    case available(String)
    case downloading
    case building
    case installing
    case failed
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

    // 整块磁贴作为单一点击目标，避免图标/文字子视图吞掉点击
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

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

// MARK: - Clickable view

final class ClickableView: NSView {
    var onClick: (() -> Void)?
    var normalFill: NSColor?
    var hoverFill: NSColor?
    private var isHovered = false

    func styled(corner: CGFloat, fill: NSColor?, hover: NSColor?) {
        wantsLayer = true
        layer?.cornerRadius = corner
        layer?.cornerCurve = .continuous
        normalFill = fill
        hoverFill = hover
        applyFill()
    }

    // 整块作为单一点击目标（仅用于纯展示内容的可点视图）
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    private func applyFill() {
        guard let normalFill else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isHovered ? (hoverFill ?? normalFill) : normalFill).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyFill()
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
        applyFill()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyFill()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isHovered = inside
        applyFill()
        if inside { onClick?() }
    }
}

final class PagingHostView: NSView {
    var onHorizontalPageRequest: (() -> Void)?
    private var accumulatedX: CGFloat = 0
    private var lastTrigger = Date.distantPast

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) * 1.2, abs(dx) > 1 else {
            accumulatedX = 0
            super.scrollWheel(with: event)
            return
        }

        accumulatedX += dx
        let now = Date()
        if abs(accumulatedX) > 42, now.timeIntervalSince(lastTrigger) > 0.35 {
            lastTrigger = now
            accumulatedX = 0
            onHorizontalPageRequest?()
        }
    }

    override func swipe(with event: NSEvent) {
        guard abs(event.deltaX) > abs(event.deltaY), abs(event.deltaX) > 0.2 else {
            super.swipe(with: event)
            return
        }
        onHorizontalPageRequest?()
    }
}

final class FlippedStack: NSStackView {
    override var isFlipped: Bool { true }
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
    private let systemUpdatedValue = NSTextField(labelWithString: "--")

    private let cpuTempValue = NSTextField(labelWithString: "不可用")
    private let gpuTempValue = NSTextField(labelWithString: "不可用")
    private let memoryUsageValue = NSTextField(labelWithString: "--")
    private let memoryDetailValue = NSTextField(labelWithString: "等待刷新")
    private let loadAverageValue = NSTextField(labelWithString: "--")

    private let tokenTotalValue = NSTextField(labelWithString: "0")
    private let tokenSavedValue = NSTextField(labelWithString: "0")
    private let tokenReadValue = NSTextField(labelWithString: "0")
    private let tokenSavingsRateValue = NSTextField(labelWithString: "0%")
    private let tokenSourceValue = NSTextField(labelWithString: "暂无数据")

    private let languageSegment = NSSegmentedControl(
        labels: ["中文", "English"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    // 内容切换（看板 ⇄ 列表 ⇄ 单条详情 ⇄ 安装引导）
    private let container = PagingHostView()
    private let blurView = NSVisualEffectView()
    private var dashboardView: NSView!
    private var systemView: NSView!
    private var dashboardPage = 0
    private var currentContent: NSView?
    private weak var anchorButton: NSStatusBarButton?
    private let detailHeight: CGFloat = 480
    private var detailContentWidth: CGFloat { panelWidth - 40 }

    // 列表异步加载状态
    private var currentListKind: DetailKind?
    private var listToken = 0

    // 安装引导视图（按需构建一次，进度原地更新）
    private var setupView: NSView?
    private let setupMessageLabel = NSTextField(wrappingLabelWithString: "")
    private let setupSpinner = NSProgressIndicator()
    private let setupRetryButton = NSButton()
    private let setupManualButton = NSButton()

    // 数据与回调（由 AppDelegate 注入）
    var memoriesProvider: (@escaping ([MemoryItem]) -> Void) -> Void = { $0([]) }
    var summariesProvider: (@escaping ([SummaryItem]) -> Void) -> Void = { $0([]) }
    var onOpenWeb: () -> Void = {}
    var onStartUpdate: () -> Void = {}
    var onDismissUpdate: () -> Void = {}
    var onRetryInstall: () -> Void = {}
    var languageProvider: () -> Int = { 0 }
    var onSelectLanguage: (Int) -> Void = { _ in }

    // 更新横幅（普通容器：内部按钮需要独立接收点击）
    private let updateBanner = NSView()
    private let updateBannerLabel = NSTextField(labelWithString: "")
    private let updateActionButton = NSButton()
    private let updateDismissButton = NSButton()

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

        buildContainer()
        dashboardView = buildDashboard(
            actionTarget: actionTarget,
            openSelector: openSelector,
            copySelector: copySelector,
            refreshSelector: refreshSelector,
            restartSelector: restartSelector,
            logsSelector: logsSelector,
            quitSelector: quitSelector
        )
        systemView = buildSystemDashboard()
        container.onHorizontalPageRequest = { [weak self] in
            self?.toggleDashboardPage()
        }
        panel.contentView = container
        showDashboard()
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
        anchorButton = button
        update(health: health, counts: counts, refreshedAt: refreshedAt)
        dashboardPage = 0
        showDashboard()
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

        languageSegment.selectedSegment = languageProvider()

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        updatedValue.stringValue = "更新于 \(formatter.string(from: refreshedAt))"
    }

    func updateSystem(system: SystemStats, tokens: TokenStats, refreshedAt: Date) {
        cpuTempValue.stringValue = system.cpuTemperature
        gpuTempValue.stringValue = system.gpuTemperature
        memoryUsageValue.stringValue = system.memoryUsage
        memoryDetailValue.stringValue = system.memoryDetail
        loadAverageValue.stringValue = system.loadAverage

        tokenTotalValue.stringValue = formatTokenCount(tokens.totalTokens)
        tokenSavedValue.stringValue = formatTokenCount(tokens.savedTokens)
        tokenReadValue.stringValue = formatTokenCount(tokens.readTokens)
        tokenSavingsRateValue.stringValue = "\(tokens.savingsRate)%"
        tokenSourceValue.stringValue = tokens.sourceBreakdown

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        systemUpdatedValue.stringValue = "更新于 \(formatter.string(from: refreshedAt))"
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

    private func buildContainer() {
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderColor = Theme.cardBorder.cgColor
        container.layer?.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false

        blurView.material = .popover
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blurView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: panelWidth),
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func buildDashboard(
        actionTarget: AnyObject,
        openSelector: Selector,
        copySelector: Selector,
        refreshSelector: Selector,
        restartSelector: Selector,
        logsSelector: Selector,
        quitSelector: Selector
    ) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(buildUpdateBanner())
        stack.addArrangedSubview(statsCard())
        stack.addArrangedSubview(runtimeCard())
        stack.addArrangedSubview(activityCard())
        stack.addArrangedSubview(languageCard())
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
        return stack
    }

    private func buildSystemDashboard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(systemHeader())
        stack.addArrangedSubview(systemMetricsCard())
        stack.addArrangedSubview(tokenOverviewCard())
        stack.addArrangedSubview(systemFooter())
        return stack
    }

    // MARK: Navigation

    func showDashboard() {
        let target = dashboardPage == 0 ? dashboardView! : systemView!
        if currentContent === target {
            relayout()
        } else {
            swapContent(target)
        }
    }

    private func toggleDashboardPage() {
        guard currentContent === dashboardView || currentContent === systemView else { return }
        dashboardPage = dashboardPage == 0 ? 1 : 0
        swapContent(dashboardPage == 0 ? dashboardView : systemView)
    }

    private func swapContent(_ view: NSView) {
        currentContent?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        currentContent = view
        relayout()
    }

    private func relayout() {
        container.layoutSubtreeIfNeeded()
        if let size = container.fittingSize as NSSize?, size.height > 0 {
            window?.setContentSize(size)
        }
        if let anchorButton {
            position(relativeTo: anchorButton)
        }
    }

    // MARK: Setup / install flow

    /// 显示安装引导（首次或缺失 claude-mem 时）。进度更新调用 updateSetup。
    func showSetup(message: String, isError: Bool, relativeTo button: NSStatusBarButton? = nil) {
        if let button { anchorButton = button }
        if setupView == nil { setupView = buildSetup() }
        applySetup(message: message, isError: isError)
        if currentContent !== setupView { swapContent(setupView!) } else { relayout() }
        if button != nil { window?.orderFrontRegardless() }
    }

    func updateSetup(message: String, isError: Bool) {
        guard setupView != nil else { return }
        applySetup(message: message, isError: isError)
        if currentContent === setupView { relayout() }
    }

    private func applySetup(message: String, isError: Bool) {
        setupMessageLabel.stringValue = message
        setupMessageLabel.textColor = isError ? Theme.offline : .secondaryLabelColor
        if isError {
            setupSpinner.stopAnimation(nil)
            setupSpinner.isHidden = true
            setupRetryButton.isHidden = false
            setupManualButton.isHidden = false
        } else {
            setupSpinner.isHidden = false
            setupSpinner.startAnimation(nil)
            setupRetryButton.isHidden = true
            setupManualButton.isHidden = true
        }
    }

    private func buildSetup() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false

        let icon = iconTile(symbol: "shippingbox", size: 52, symbolSize: 28)

        let title = label("设置 claude-mem", size: 16, weight: .bold)
        title.textColor = .labelColor
        title.alignment = .center

        setupMessageLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        setupMessageLabel.textColor = .secondaryLabelColor
        setupMessageLabel.alignment = .center
        setupMessageLabel.maximumNumberOfLines = 0
        setupMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        setupMessageLabel.preferredMaxLayoutWidth = detailContentWidth
        setupMessageLabel.widthAnchor.constraint(equalToConstant: detailContentWidth).isActive = true

        setupSpinner.style = .spinning
        setupSpinner.controlSize = .regular
        setupSpinner.isIndeterminate = true
        setupSpinner.translatesAutoresizingMaskIntoConstraints = false

        configurePillButton(setupRetryButton, title: "重试", action: #selector(retryTapped))
        setupRetryButton.isHidden = true

        setupManualButton.isBordered = false
        setupManualButton.target = self
        setupManualButton.action = #selector(manualInstallTapped)
        setupManualButton.translatesAutoresizingMaskIntoConstraints = false
        setupManualButton.isHidden = true
        let manualParagraph = NSMutableParagraphStyle()
        manualParagraph.alignment = .center
        setupManualButton.attributedTitle = NSAttributedString(string: "查看手动安装文档", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: Theme.accent,
            .paragraphStyle: manualParagraph
        ])

        let stack = NSStackView(views: [icon, title, setupSpinner, setupMessageLabel, setupRetryButton, setupManualButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(14, after: setupMessageLabel)
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 20, bottom: 32, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)

        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalToConstant: panelWidth),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            stack.topAnchor.constraint(equalTo: host.topAnchor),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }

    @objc private func retryTapped() { onRetryInstall() }
    @objc private func manualInstallTapped() { NSWorkspace.shared.open(claudeMemRepoURL) }

    // MARK: Update banner

    private func buildUpdateBanner() -> NSView {
        updateBanner.wantsLayer = true
        updateBanner.layer?.cornerRadius = 11
        updateBanner.layer?.cornerCurve = .continuous
        updateBanner.layer?.backgroundColor = Theme.accentSoft.cgColor
        updateBanner.layer?.borderColor = Theme.accent.withAlphaComponent(0.30).cgColor
        updateBanner.layer?.borderWidth = 1
        updateBanner.translatesAutoresizingMaskIntoConstraints = false
        updateBanner.isHidden = true

        let icon = symbol("arrow.down.circle.fill", pointSize: 14, weight: .semibold, color: Theme.accent)

        updateBannerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        updateBannerLabel.textColor = .labelColor
        updateBannerLabel.maximumNumberOfLines = 1
        updateBannerLabel.lineBreakMode = .byTruncatingTail
        updateBannerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configurePillButton(updateActionButton, title: "更新", action: #selector(bannerUpdateTapped))
        configureIconButton(updateDismissButton, symbol: "xmark", action: #selector(bannerDismissTapped))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, updateBannerLabel, spacer, updateActionButton, updateDismissButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        updateBanner.addSubview(row)

        NSLayoutConstraint.activate([
            updateBanner.widthAnchor.constraint(equalToConstant: contentWidth),
            updateBanner.heightAnchor.constraint(equalToConstant: 38),
            row.leadingAnchor.constraint(equalTo: updateBanner.leadingAnchor, constant: 11),
            row.trailingAnchor.constraint(equalTo: updateBanner.trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: updateBanner.centerYAnchor)
        ])
        return updateBanner
    }

    func setUpdateState(_ state: UpdateUIState?) {
        guard let state else {
            updateBanner.isHidden = true
            if currentContent === dashboardView { relayout() }
            return
        }
        updateBanner.isHidden = false
        let busy: Bool
        switch state {
        case .available(let v):
            updateBannerLabel.stringValue = "发现新版本 v\(v)"
            setPillTitle(updateActionButton, "更新")
            busy = false
        case .downloading:
            updateBannerLabel.stringValue = "正在下载新版本…"
            busy = true
        case .building:
            updateBannerLabel.stringValue = "正在编译…"
            busy = true
        case .installing:
            updateBannerLabel.stringValue = "正在安装，即将重启…"
            busy = true
        case .failed:
            updateBannerLabel.stringValue = "更新失败，已打开仓库页面"
            setPillTitle(updateActionButton, "重试")
            busy = false
        }
        updateActionButton.isHidden = busy
        updateDismissButton.isHidden = busy
        if currentContent === dashboardView { relayout() }
    }

    @objc private func bannerUpdateTapped() { onStartUpdate() }
    @objc private func bannerDismissTapped() { onDismissUpdate() }

    private func configurePillButton(_ button: NSButton, title: String, action: Selector) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = Theme.accent.cgColor
        button.layer?.cornerRadius = 7
        button.layer?.cornerCurve = .continuous
        button.target = self
        button.action = action
        setPillTitle(button, title)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 24),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])
    }

    private func setPillTitle(_ button: NSButton, _ title: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
    }

    private func configureIconButton(_ button: NSButton, symbol symbolName: String, action: Selector) {
        button.isBordered = false
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "忽略")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    // MARK: Detail list (async)

    private var detailRowWidth: CGFloat { panelWidth - 24 }

    func showDetail(_ kind: DetailKind) {
        currentListKind = kind
        listToken += 1
        let token = listToken

        let shell = buildListShell(kind)
        let host = shell.host
        let stack = shell.stack
        let countLabel = shell.countLabel
        swapContent(host)

        // 加载占位
        stack.addArrangedSubview(loadingRow())
        relayout()

        let apply: ([NSView], Int) -> Void = { [weak self] rows, count in
            guard let self, token == self.listToken, self.currentContent === host else { return }
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            if rows.isEmpty {
                stack.addArrangedSubview(self.emptyRow(kind))
            } else {
                rows.forEach { stack.addArrangedSubview($0) }
            }
            countLabel.stringValue = count > 0 ? "\(count) 条" : "暂无"
            self.relayout()
        }

        switch kind {
        case .memories:
            memoriesProvider { [weak self] items in
                guard let self else { return }
                apply(items.map { self.memoryRow($0) }, items.count)
            }
        case .summaries:
            summariesProvider { [weak self] items in
                guard let self else { return }
                apply(items.map { self.summaryRow($0) }, items.count)
            }
        }
    }

    private func buildListShell(_ kind: DetailKind) -> (host: NSView, stack: FlippedStack, countLabel: NSTextField) {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false

        let titleIcon = symbol(kind.symbol, pointSize: 13, weight: .semibold, color: Theme.accent)
        let titleLabel = label(kind.title, size: 14, weight: .bold)
        titleLabel.textColor = .labelColor

        let countLabel = label("", size: 11.5, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let backButton = makeBackButton { [weak self] in self?.showDashboard() }
        let topRow = NSStackView(views: [backButton, titleIcon, titleLabel, spacer, countLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            topRow.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])

        let listStack = FlippedStack()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 10, right: 12)
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = listStack
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            listStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        let footerButton = makeFooterButton("在浏览器中查看全部", symbol: "arrow.up.right.square") { [weak self] in self?.onOpenWeb() }
        let footerBar = NSView()
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(footerButton)
        NSLayoutConstraint.activate([
            footerButton.centerXAnchor.constraint(equalTo: footerBar.centerXAnchor),
            footerButton.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor)
        ])

        let topSep = hairline()
        let botSep = hairline()
        host.addSubview(topBar)
        host.addSubview(topSep)
        host.addSubview(scroll)
        host.addSubview(botSep)
        host.addSubview(footerBar)

        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalToConstant: panelWidth),
            host.heightAnchor.constraint(equalToConstant: detailHeight),

            topBar.topAnchor.constraint(equalTo: host.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 46),

            topSep.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSep.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: host.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: topSep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: botSep.topAnchor),

            botSep.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            botSep.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            botSep.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: 44)
        ])
        return (host, listStack, countLabel)
    }

    private func loadingRow() -> NSView {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let text = label("加载中…", size: 12.5, weight: .medium)
        text.textColor = .secondaryLabelColor

        let row = NSStackView(views: [spinner, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: detailRowWidth),
            view.heightAnchor.constraint(equalToConstant: 80),
            row.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func makeBackButton(_ action: @escaping () -> Void) -> NSView {
        let chevron = symbol("chevron.left", pointSize: 12, weight: .semibold, color: Theme.accent)
        let text = label("返回", size: 12.5, weight: .semibold)
        text.textColor = Theme.accent
        let row = NSStackView(views: [chevron, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false

        let view = ClickableView()
        view.styled(corner: 7, fill: .clear, hover: Theme.controlFill)
        view.onClick = action
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -7),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
        return view
    }

    private func makeFooterButton(_ title: String, symbol symbolName: String, action: @escaping () -> Void) -> NSView {
        let icon = symbol(symbolName, pointSize: 12, weight: .semibold, color: Theme.accent)
        let text = label(title, size: 12.5, weight: .semibold)
        text.textColor = Theme.accent
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let view = ClickableView()
        view.styled(corner: 8, fill: .clear, hover: Theme.controlFill)
        view.onClick = action
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 7),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -7)
        ])
        return view
    }

    private func memoryRow(_ item: MemoryItem) -> NSView {
        let title = nonEmpty(item.title) ?? "(无标题)"
        let snippet = cleanSnippet(nonEmpty(item.subtitle) ?? nonEmpty(item.narrative) ?? jsonArray(item.facts).first ?? item.text)
        return listRow(title: title, snippet: snippet, meta: metaLine(project: item.project, epoch: item.created_at_epoch)) {
            [weak self] in self?.showMemoryDetail(item)
        }
    }

    private func summaryRow(_ item: SummaryItem) -> NSView {
        let title = nonEmpty(item.request) ?? "(无标题)"
        let snippet = cleanSnippet(nonEmpty(item.completed) ?? nonEmpty(item.learned) ?? item.investigated)
        return listRow(title: title, snippet: snippet, meta: metaLine(project: item.project, epoch: item.created_at_epoch)) {
            [weak self] in self?.showSummaryDetail(item)
        }
    }

    private func listRow(title: String, snippet: String, meta: String, onClick: @escaping () -> Void) -> NSView {
        // 文本宽度 = 行宽 - 左内边距(12) - 右雪佛龙占位(28)
        let inner = detailRowWidth - 12 - 28

        let titleLabel = label(title, size: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: inner).isActive = true

        var views: [NSView] = [titleLabel]
        if !snippet.isEmpty {
            let snippetLabel = NSTextField(wrappingLabelWithString: snippet)
            snippetLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
            snippetLabel.textColor = .secondaryLabelColor
            snippetLabel.maximumNumberOfLines = 2
            snippetLabel.lineBreakMode = .byTruncatingTail
            snippetLabel.isSelectable = false
            snippetLabel.translatesAutoresizingMaskIntoConstraints = false
            snippetLabel.widthAnchor.constraint(equalToConstant: inner).isActive = true
            views.append(snippetLabel)
        }
        let metaLabel = label(meta, size: 10.5, weight: .medium)
        metaLabel.textColor = .tertiaryLabelColor
        views.append(metaLabel)

        // 右侧雪佛龙提示可点开详情
        let chevron = symbol("chevron.right", pointSize: 11, weight: .semibold, color: .tertiaryLabelColor)

        let vstack = NSStackView(views: views)
        vstack.orientation = .vertical
        vstack.alignment = .leading
        vstack.spacing = 3
        vstack.translatesAutoresizingMaskIntoConstraints = false

        let row = ClickableView()
        row.styled(corner: 10, fill: Theme.cardFill, hover: Theme.controlHover)
        row.layer?.borderColor = Theme.cardBorder.cgColor
        row.layer?.borderWidth = 1
        row.onClick = onClick
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(vstack)
        row.addSubview(chevron)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: detailRowWidth),
            vstack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            vstack.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            vstack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            chevron.leadingAnchor.constraint(equalTo: vstack.trailingAnchor, constant: 6),
            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func emptyRow(_ kind: DetailKind) -> NSView {
        let text = label(kind == .memories ? "暂无记忆" : "暂无摘要", size: 12.5, weight: .medium)
        text.textColor = .secondaryLabelColor
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: detailRowWidth),
            view.heightAnchor.constraint(equalToConstant: 64),
            text.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            text.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    // MARK: Single item detail (in-app, viewer 无单条深链)

    private enum DetailSection {
        case text(String, String)
        case bullets(String, [String])
    }

    private func showMemoryDetail(_ item: MemoryItem) {
        let title = nonEmpty(item.title) ?? "(无标题)"
        var meta = metaLine(project: item.project, epoch: item.created_at_epoch)
        if let type = nonEmpty(item.type) {
            meta = meta.isEmpty ? type : "\(type) · \(meta)"
        }

        var sections: [DetailSection] = []
        if let s = nonEmpty(item.subtitle) { sections.append(.text("摘要", s)) }
        if let n = nonEmpty(item.narrative) { sections.append(.text("概述", n)) }
        let facts = jsonArray(item.facts)
        if !facts.isEmpty { sections.append(.bullets("要点", facts)) }
        let concepts = jsonArray(item.concepts)
        if !concepts.isEmpty { sections.append(.text("概念", concepts.joined(separator: "、"))) }
        let files = Array(NSOrderedSet(array: jsonArray(item.files_modified) + jsonArray(item.files_read)).array as? [String] ?? [])
        if !files.isEmpty { sections.append(.bullets("涉及文件", files)) }
        if sections.isEmpty, let t = nonEmpty(item.text) { sections.append(.text("内容", t)) }

        swapContent(buildItemDetail(kind: .memories, headerTitle: title, meta: meta, sections: sections))
    }

    private func showSummaryDetail(_ item: SummaryItem) {
        let title = nonEmpty(item.request) ?? "(无标题)"
        let meta = metaLine(project: item.project, epoch: item.created_at_epoch)

        var sections: [DetailSection] = []
        if let v = nonEmpty(item.investigated) { sections.append(.text("调查", v)) }
        if let v = nonEmpty(item.learned) { sections.append(.text("收获", v)) }
        if let v = nonEmpty(item.completed) { sections.append(.text("完成", v)) }
        if let v = nonEmpty(item.next_steps) { sections.append(.text("下一步", v)) }

        swapContent(buildItemDetail(kind: .summaries, headerTitle: title, meta: meta, sections: sections))
    }

    private func buildItemDetail(kind: DetailKind, headerTitle: String, meta: String, sections: [DetailSection]) -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false

        let titleIcon = symbol(kind.symbol, pointSize: 13, weight: .semibold, color: Theme.accent)
        let titleLabel = label(kind.title + "详情", size: 14, weight: .bold)
        titleLabel.textColor = .labelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 返回到对应列表
        let backButton = makeBackButton { [weak self] in self?.showDetail(kind) }
        let topRow = NSStackView(views: [backButton, titleIcon, titleLabel, spacer])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            topRow.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])

        // 内容
        let content = FlippedStack()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 18, right: 20)
        content.translatesAutoresizingMaskIntoConstraints = false

        let bigTitle = NSTextField(wrappingLabelWithString: headerTitle)
        bigTitle.font = .systemFont(ofSize: 15, weight: .bold)
        bigTitle.textColor = .labelColor
        bigTitle.isSelectable = true
        bigTitle.translatesAutoresizingMaskIntoConstraints = false
        bigTitle.preferredMaxLayoutWidth = detailContentWidth
        bigTitle.widthAnchor.constraint(equalToConstant: detailContentWidth).isActive = true
        content.addArrangedSubview(bigTitle)

        if !meta.isEmpty {
            let metaLabel = label(meta, size: 11, weight: .medium)
            metaLabel.textColor = .tertiaryLabelColor
            content.addArrangedSubview(metaLabel)
        }

        if sections.isEmpty {
            let empty = label("暂无更多内容", size: 12.5, weight: .medium)
            empty.textColor = .secondaryLabelColor
            content.addArrangedSubview(empty)
        } else {
            for section in sections {
                content.addArrangedSubview(sectionView(section))
            }
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = content
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        let footerButton = makeFooterButton("在浏览器中打开", symbol: "arrow.up.right.square") { [weak self] in self?.onOpenWeb() }
        let footerBar = NSView()
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(footerButton)
        NSLayoutConstraint.activate([
            footerButton.centerXAnchor.constraint(equalTo: footerBar.centerXAnchor),
            footerButton.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor)
        ])

        let topSep = hairline()
        let botSep = hairline()
        host.addSubview(topBar)
        host.addSubview(topSep)
        host.addSubview(scroll)
        host.addSubview(botSep)
        host.addSubview(footerBar)

        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalToConstant: panelWidth),
            host.heightAnchor.constraint(equalToConstant: detailHeight),

            topBar.topAnchor.constraint(equalTo: host.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 46),

            topSep.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSep.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            topSep.trailingAnchor.constraint(equalTo: host.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: topSep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: botSep.topAnchor),

            botSep.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            botSep.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            botSep.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: 44)
        ])
        return host
    }

    private func sectionView(_ section: DetailSection) -> NSView {
        let header: String
        let body: NSView
        switch section {
        case .text(let h, let value):
            header = h
            let text = NSTextField(wrappingLabelWithString: value)
            text.font = .systemFont(ofSize: 12.5, weight: .regular)
            text.textColor = .labelColor
            text.isSelectable = true
            text.translatesAutoresizingMaskIntoConstraints = false
            text.preferredMaxLayoutWidth = detailContentWidth
            text.widthAnchor.constraint(equalToConstant: detailContentWidth).isActive = true
            body = text
        case .bullets(let h, let items):
            header = h
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 5
            stack.translatesAutoresizingMaskIntoConstraints = false
            for item in items {
                stack.addArrangedSubview(bulletRow(item))
            }
            body = stack
        }

        let headerLabel = label(header, size: 11, weight: .semibold)
        headerLabel.textColor = Theme.accent

        let wrapper = NSStackView(views: [headerLabel, body])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 6
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        return wrapper
    }

    private func bulletRow(_ text: String) -> NSView {
        let dot = label("•", size: 12.5, weight: .bold)
        dot.textColor = Theme.accent
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.setContentHuggingPriority(.required, for: .horizontal)

        let bodyWidth = detailContentWidth - 16
        let text = NSTextField(wrappingLabelWithString: text)
        text.font = .systemFont(ofSize: 12.5, weight: .regular)
        text.textColor = .labelColor
        text.isSelectable = true
        text.translatesAutoresizingMaskIntoConstraints = false
        text.preferredMaxLayoutWidth = bodyWidth
        text.widthAnchor.constraint(equalToConstant: bodyWidth).isActive = true

        let row = NSStackView(views: [dot, text])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func hairline() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.cardBorder.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func metaLine(project: String?, epoch: Int?) -> String {
        var parts: [String] = []
        if let project, !project.isEmpty { parts.append(project) }
        if let epoch { parts.append(relativeTime(epoch)) }
        return parts.joined(separator: " · ")
    }

    private func relativeTime(_ epoch: Int) -> String {
        // claude-mem 时间戳为毫秒；兼容秒级
        let seconds = epoch > 4_000_000_000 ? epoch / 1000 : epoch
        let diff = max(0, Int(Date().timeIntervalSince1970) - seconds)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(diff / 60) 分钟前" }
        if diff < 86400 { return "\(diff / 3600) 小时前" }
        if diff < 86400 * 7 { return "\(diff / 86400) 天前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    private func jsonArray(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr.compactMap { nonEmpty($0) }
        }
        return []
    }

    private func cleanSnippet(_ raw: String?) -> String {
        guard var s = raw, !s.isEmpty else { return "" }
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = s.replacingOccurrences(of: "\t", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 140 { s = String(s.prefix(140)) + "…" }
        return s
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
        let memory = clickableStat(memoryValue, "记忆", kind: .memories)
        let session = statTile(sessionValue, "会话")
        let summary = clickableStat(summaryValue, "摘要", kind: .summaries)

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

    private func languageCard() -> NSView {
        languageSegment.segmentDistribution = .fillEqually
        languageSegment.target = self
        languageSegment.action = #selector(languageChanged)
        languageSegment.selectedSegment = languageProvider()
        languageSegment.translatesAutoresizingMaskIntoConstraints = false
        languageSegment.widthAnchor.constraint(equalToConstant: cardInnerWidth).isActive = true

        let hint = label("切换记忆生成语言（保存后将重启服务）", size: 10.5, weight: .medium)
        hint.textColor = .tertiaryLabelColor

        let rows = NSStackView(views: [languageSegment, hint])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 7
        return card(title: "记忆语言", symbol: "character.bubble", content: rows)
    }

    @objc private func languageChanged() {
        onSelectLanguage(languageSegment.selectedSegment)
    }

    private func systemHeader() -> NSView {
        let icon = iconTile(symbol: "desktopcomputer", size: 38, symbolSize: 20)

        let title = label("系统与 Token", size: 16, weight: .bold)
        title.textColor = .labelColor
        let subtitle = label("本机状态与全平台消耗", size: 11.5, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let copy = NSStackView(views: [title, subtitle])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 1

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, copy, spacer, pageDots(active: 1)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        return row
    }

    private func systemMetricsCard() -> NSView {
        configureMetric(cpuTempValue)
        configureMetric(gpuTempValue)
        configureMetric(memoryUsageValue)
        configureMetric(loadAverageValue)
        memoryDetailValue.font = .systemFont(ofSize: 10.5, weight: .medium)
        memoryDetailValue.textColor = .tertiaryLabelColor
        memoryDetailValue.maximumNumberOfLines = 1
        memoryDetailValue.lineBreakMode = .byTruncatingTail
        memoryDetailValue.widthAnchor.constraint(equalToConstant: cardInnerWidth).isActive = true

        let tileWidth = (cardInnerWidth - 8) / 2
        let rows = NSStackView(views: [
            metricRow([
                metricTile(title: "CPU 温度", value: cpuTempValue, width: tileWidth),
                metricTile(title: "GPU 温度", value: gpuTempValue, width: tileWidth)
            ]),
            metricRow([
                metricTile(title: "内存占用", value: memoryUsageValue, width: tileWidth),
                metricTile(title: "系统负载", value: loadAverageValue, width: tileWidth)
            ]),
            memoryDetailValue
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        return card(title: "电脑状态", symbol: "gauge.with.dots.needle", content: rows)
    }

    private func tokenOverviewCard() -> NSView {
        tokenTotalValue.font = Theme.roundedFont(25, .bold)
        tokenTotalValue.textColor = Theme.accent
        tokenSavedValue.font = Theme.roundedFont(25, .bold)
        tokenSavedValue.textColor = Theme.online
        configureValue(tokenReadValue, weight: .semibold)
        configureValue(tokenSavingsRateValue, weight: .semibold)
        configureValue(tokenSourceValue, weight: .medium)
        tokenSourceValue.textColor = .secondaryLabelColor

        let total = tokenFigure(title: "总 Token", value: tokenTotalValue, color: Theme.accent)
        let saved = tokenFigure(title: "已节省", value: tokenSavedValue, color: Theme.online)
        let topRow = NSStackView(views: [total, saved])
        topRow.orientation = .horizontal
        topRow.distribution = .fillEqually
        topRow.alignment = .centerY
        topRow.spacing = 10
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.widthAnchor.constraint(equalToConstant: cardInnerWidth).isActive = true

        let rows = NSStackView(views: [
            topRow,
            infoRow(infoCell("读取", tokenReadValue), infoCell("节省", tokenSavingsRateValue)),
            infoCell("来源", tokenSourceValue)
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 9
        return card(title: "Token 汇总", symbol: "sum", content: rows)
    }

    private func configureMetric(_ field: NSTextField) {
        field.font = Theme.roundedFont(16, .bold)
        field.textColor = .labelColor
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.alignment = .left
    }

    private func metricRow(_ tiles: [NSView]) -> NSView {
        let row = NSStackView(views: tiles)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: cardInnerWidth).isActive = true
        return row
    }

    private func metricTile(title: String, value: NSTextField, width: CGFloat) -> NSView {
        let titleLabel = label(title, size: 10.5, weight: .semibold)
        titleLabel.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [titleLabel, value])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.controlFill.cgColor
        view.layer?.cornerRadius = 10
        view.layer?.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return view
    }

    private func tokenFigure(title: String, value: NSTextField, color: NSColor) -> NSView {
        let titleLabel = label(title, size: 10.5, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        value.alignment = .center

        let stack = NSStackView(views: [value, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
        view.layer?.cornerRadius = 11
        view.layer?.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 68),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -6)
        ])
        return view
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

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [clock, updatedValue, spacer, pageDots(active: 0)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: contentWidth)
        ])
        return row
    }

    private func systemFooter() -> NSView {
        let clock = symbol("clock", pointSize: 11, weight: .regular, color: .tertiaryLabelColor)
        systemUpdatedValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        systemUpdatedValue.textColor = .tertiaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [clock, systemUpdatedValue, spacer, pageDots(active: 1)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return row
    }

    private func pageDots(active: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        for index in 0..<2 {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = (index == active ? Theme.accent : NSColor.tertiaryLabelColor).cgColor
            dot.layer?.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: index == active ? 14 : 6),
                dot.heightAnchor.constraint(equalToConstant: 6)
            ])
            row.addArrangedSubview(dot)
        }
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

    private func clickableStat(_ value: NSTextField, _ title: String, kind: DetailKind) -> NSView {
        let content = statTile(value, title)
        content.translatesAutoresizingMaskIntoConstraints = false

        let view = ClickableView()
        view.styled(corner: 9, fill: .clear, hover: Theme.controlFill)
        view.onClick = { [weak self] in self?.showDetail(kind) }
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
            content.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 2),
            content.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -2)
        ])
        return view
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

    private func formatTokenCount(_ value: Int) -> String {
        if value >= 100_000_000 {
            return String(format: "%.1f亿", Double(value) / 100_000_000.0)
        }
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000.0)
        }
        return "\(value)"
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
    private var updateTimer: Timer?
    private var lastHealth: Health?
    private var lastCounts = Counts()
    private var lastSystemStats = SystemStats()
    private var lastTokenStats = TokenStats()
    private var lastRefresh = Date()
    private var isRefreshing = false

    // 详情数据缓存（避免重复 sqlite 调用造成卡顿）
    private var cachedMemories: [MemoryItem]?
    private var cachedSummaries: [SummaryItem]?

    // 安装引导状态
    private var isReady = false
    private var isInstalling = false
    private var setupMessage = "正在检测 claude-mem…"
    private var setupIsError = false

    // 热更新状态
    private var availableVersion: String?
    private var lastUpdateCheck: Date?
    private var isUpdating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        wireDashboard()
        buildStatusItem()

        if isClaudeMemInstalled() {
            markReady()
        } else {
            beginInstallFlow(auto: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        updateTimer?.invalidate()
    }

    private func wireDashboard() {
        dashboard.memoriesProvider = { [weak self] completion in self?.loadMemories(completion) }
        dashboard.summariesProvider = { [weak self] completion in self?.loadSummaries(completion) }
        dashboard.onOpenWeb = { NSWorkspace.shared.open(webURL) }
        dashboard.onStartUpdate = { [weak self] in self?.startUpdate() }
        dashboard.onDismissUpdate = { [weak self] in self?.dismissUpdate() }
        dashboard.onRetryInstall = { [weak self] in self?.beginInstallFlow(auto: false) }
        dashboard.languageProvider = { [weak self] in (self?.currentLanguage() ?? .chinese).rawValue }
        dashboard.onSelectLanguage = { [weak self] index in
            self?.setLanguage(Language(rawValue: index) ?? .chinese)
        }
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

    private func startTimers() {
        timer?.invalidate()
        updateTimer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdate(force: true)
        }
    }

    // MARK: Install flow (Req3)

    private func isClaudeMemInstalled() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: pluginMarkerPath) || fm.fileExists(atPath: databasePath)
    }

    private func markReady() {
        guard !isReady else { return }
        isReady = true
        applyChineseDefaultIfNeeded()
        refresh()
        checkForUpdate(force: true)
        startTimers()
    }

    private func beginInstallFlow(auto: Bool) {
        guard !isInstalling else { return }
        isInstalling = true
        setupIsError = false
        setupMessage = "检测到尚未安装 claude-mem，正在自动安装…"
        if let button = statusItem.button {
            dashboard.showSetup(message: setupMessage, isError: false, relativeTo: button)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.performInstall(progress: { message in
                DispatchQueue.main.async {
                    self.setupMessage = message
                    self.dashboard.updateSetup(message: message, isError: false)
                }
            }, done: { ok, errorMessage in
                DispatchQueue.main.async {
                    self.isInstalling = false
                    if ok {
                        self.markReady()
                        if let button = self.statusItem.button {
                            self.dashboard.show(health: self.lastHealth, counts: self.lastCounts, refreshedAt: self.lastRefresh, relativeTo: button)
                        }
                    } else {
                        self.setupIsError = true
                        self.setupMessage = errorMessage
                        self.dashboard.updateSetup(message: errorMessage, isError: true)
                    }
                }
            })
        }
    }

    /// 检测 node/npx → 运行 `npx claude-mem@latest install` → 配置中文 → 启动 worker。
    private func performInstall(progress: @escaping (String) -> Void, done: @escaping (Bool, String) -> Void) {
        progress("正在检测 Node.js 环境…")
        guard let node = findNodeBinary() else {
            done(false, "未检测到 Node.js / npx。请先安装 Node.js（nodejs.org）后点击重试。")
            return
        }

        var env = ProcessInfo.processInfo.environment
        let extraPaths = [node.binDir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (extraPaths + [env["PATH"] ?? ""]).joined(separator: ":")

        progress("正在安装 claude-mem（首次安装可能需要几分钟）…")
        let install = Self.run(node.npx, ["-y", "claude-mem@latest", "install"], env: env)
        if install.status != 0 {
            let detail = install.stderr.isEmpty ? install.stdout : install.stderr
            let tail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            done(false, "安装失败：\(tail.isEmpty ? "未知错误" : String(tail.suffix(160)))")
            return
        }

        progress("正在配置默认中文输出…")
        _ = writeLanguageMode(.chinese)

        progress("正在启动后台服务…")
        _ = Self.run(node.npx, ["-y", "claude-mem@latest", "start"], env: env)

        done(true, "")
    }

    /// 在常见安装位置查找 npx（launchd 环境 PATH 极简，which 不可用）。
    private func findNodeBinary() -> (npx: String, binDir: String)? {
        let fm = FileManager.default
        var candidates: [String] = []

        // nvm：选择版本号最大的
        let nvmRoot = NSString(string: "~/.nvm/versions/node").expandingTildeInPath
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            let sorted = versions.sorted { lhs, rhs in
                Self.versionKey(lhs).lexicographicallyPrecedes(Self.versionKey(rhs))
            }
            for version in sorted.reversed() {
                candidates.append(nvmRoot + "/" + version + "/bin/npx")
            }
        }
        // 其他常见位置
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
            NSString(string: "~/.volta/bin/npx").expandingTildeInPath,
            "/opt/homebrew/opt/node/bin/npx",
            "/usr/bin/npx"
        ])

        for path in candidates where fm.isExecutableFile(atPath: path) {
            return (path, (path as NSString).deletingLastPathComponent)
        }
        return nil
    }

    private static func versionKey(_ s: String) -> [Int] {
        s.replacingOccurrences(of: "v", with: "")
            .split(separator: ".")
            .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }

    // MARK: Language (Req4)

    private func readSettings() -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    @discardableResult
    private func writeSettings(_ dict: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (try? data.write(to: URL(fileURLWithPath: settingsPath))) != nil
    }

    private func currentMode() -> String {
        (readSettings()["CLAUDE_MEM_MODE"] as? String) ?? "code"
    }

    private func currentLanguage() -> Language {
        currentMode().contains("zh") ? .chinese : .english
    }

    /// 仅写入设置（不重启 worker）。中文=<base>--zh，英文=<base>。
    @discardableResult
    private func writeLanguageMode(_ language: Language) -> Bool {
        var settings = readSettings()
        let mode = (settings["CLAUDE_MEM_MODE"] as? String) ?? "code"
        let base = mode.components(separatedBy: "--").first ?? "code"
        settings["CLAUDE_MEM_MODE"] = language == .chinese ? base + "--zh" : base
        return writeSettings(settings)
    }

    /// 切换语言：写入设置 + 重启 worker + 失效缓存。
    private func setLanguage(_ language: Language) {
        guard currentLanguage() != language else { return }
        _ = writeLanguageMode(language)
        cachedMemories = nil
        cachedSummaries = nil
        setTransientStatus(language == .chinese ? "正在切换为中文并重启…" : "Switching to English…")
        kickstartWorker()
    }

    /// 首次运行应用时，将默认语言设为中文（仅一次，尊重后续手动选择）。
    private func applyChineseDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: languageDefaultAppliedKey) else { return }
        defaults.set(true, forKey: languageDefaultAppliedKey)
        if currentLanguage() != .chinese {
            setLanguage(.chinese)
        }
    }

    private func kickstartWorker() {
        DispatchQueue.global(qos: .utility).async {
            let uid = getuid()
            _ = Self.run("/bin/launchctl", ["kickstart", "-k", "gui/\(uid)/\(workerLabel)"])
            Thread.sleep(forTimeInterval: 2.0)
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    // MARK: Actions

    @objc private func openWebUI() {
        NSWorkspace.shared.open(webURL)
    }

    @objc private func toggleDashboard() {
        guard let button = statusItem.button else { return }
        if !isReady {
            if dashboard.window?.isVisible == true {
                dashboard.window?.orderOut(nil)
            } else {
                dashboard.showSetup(message: setupMessage, isError: setupIsError, relativeTo: button)
            }
            return
        }
        dashboard.toggle(health: lastHealth, counts: lastCounts, refreshedAt: lastRefresh, relativeTo: button)
        refresh()
        checkForUpdate()
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
        cachedMemories = nil
        cachedSummaries = nil
        refresh()
    }

    @objc private func restartWorker() {
        setTransientStatus("正在重启 Worker...")
        kickstartWorker()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: Refresh

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let group = DispatchGroup()
        var fetchedHealth: Health?
        var fetchedCounts = Counts()
        var fetchedSystemStats = SystemStats()
        var fetchedTokenStats = TokenStats()

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

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            fetchedSystemStats = self.fetchSystemStats()
            fetchedTokenStats = self.fetchTokenStats()
            group.leave()
        }

        group.notify(queue: .main) {
            self.lastHealth = fetchedHealth
            self.lastCounts = fetchedCounts
            self.lastSystemStats = fetchedSystemStats
            self.lastTokenStats = fetchedTokenStats
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

    private func fetchSystemStats() -> SystemStats {
        var stats = SystemStats()
        if let memory = readMemoryUsage() {
            stats.memoryUsage = memory.percent
            stats.memoryDetail = memory.detail
        }
        stats.loadAverage = readLoadAverage() ?? "--"
        stats.cpuTemperature = readTemperature(kind: .cpu) ?? "不可用"
        stats.gpuTemperature = readTemperature(kind: .gpu) ?? "不可用"
        return stats
    }

    private enum TemperatureKind {
        case cpu
        case gpu
    }

    private func readMemoryUsage() -> (percent: String, detail: String)? {
        let totalOutput = Self.run("/usr/sbin/sysctl", ["-n", "hw.memsize"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let total = Int64(totalOutput), total > 0 else { return nil }

        let vmOutput = Self.run("/usr/bin/vm_stat", []).stdout
        guard !vmOutput.isEmpty else { return nil }

        var pageSize: Int64 = 4096
        var pages: [String: Int64] = [:]
        for line in vmOutput.split(separator: "\n").map(String.init) {
            if line.contains("page size of"),
               let range = line.range(of: #"page size of\s+([0-9]+)"#, options: .regularExpression) {
                let fragment = String(line[range])
                if let value = fragment.split(separator: " ").last.flatMap({ Int64($0) }) {
                    pageSize = value
                }
                continue
            }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let digits = parts[1].filter { $0.isNumber }
            if let value = Int64(String(digits)) {
                pages[key] = value
            }
        }

        let activePages = pages["Pages active"] ?? 0
        let wiredPages = pages["Pages wired down"] ?? 0
        let compressedPages = pages["Pages occupied by compressor"] ?? 0
        var used = (activePages + wiredPages + compressedPages) * pageSize
        if used <= 0 {
            let freePages = (pages["Pages free"] ?? 0) + (pages["Pages speculative"] ?? 0)
            used = total - (freePages * pageSize)
        }
        used = max(0, min(total, used))
        let percent = Int((Double(used) / Double(total) * 100.0).rounded())
        return ("\(percent)%", "\(formatBytes(used)) / \(formatBytes(total))")
    }

    private func readLoadAverage() -> String? {
        let output = Self.run("/usr/sbin/sysctl", ["-n", "vm.loadavg"]).stdout
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let values = output.split(separator: " ").prefix(3).map(String.init)
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }

    private func readTemperature(kind: TemperatureKind) -> String? {
        switch kind {
        case .cpu:
            if let path = findExecutable(named: "osx-cpu-temp") {
                return parseTemperature(Self.run(path, []).stdout)
            }
            if let path = findExecutable(named: "istats") {
                return parseTemperature(Self.run(path, ["cpu", "temp"]).stdout)
            }
        case .gpu:
            if let path = findExecutable(named: "istats") {
                return parseTemperature(Self.run(path, ["gpu", "temp"]).stdout)
                    ?? parseTemperature(Self.run(path, ["scan"]).stdout)
            }
        }
        return nil
    }

    private func parseTemperature(_ text: String) -> String? {
        guard let range = text.range(of: #"[-+]?[0-9]+(\.[0-9]+)?"#, options: .regularExpression),
              let value = Double(text[range]) else {
            return nil
        }
        if value <= 0 { return nil }
        return value.rounded() == value ? "\(Int(value))°C" : String(format: "%.1f°C", value)
    }

    private func findExecutable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func formatBytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: value)
    }

    private func fetchTokenStats() -> TokenStats {
        var stats = TokenStats()
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return stats
        }

        let sql = """
        select 'work|' || (
            (select coalesce(sum(discovery_tokens), 0) from observations) +
            (select coalesce(sum(discovery_tokens), 0) from session_summaries)
        );
        select 'chars|' || (
            (select coalesce(sum(
                length(coalesce(title, '')) +
                length(coalesce(subtitle, '')) +
                length(coalesce(facts, '')) +
                length(coalesce(narrative, '')) +
                length(coalesce(concepts, '')) +
                length(coalesce(text, ''))
            ), 0) from observations) +
            (select coalesce(sum(
                length(coalesce(request, '')) +
                length(coalesce(investigated, '')) +
                length(coalesce(learned, '')) +
                length(coalesce(completed, '')) +
                length(coalesce(next_steps, '')) +
                length(coalesce(notes, ''))
            ), 0) from session_summaries)
        );
        select 'source|' || coalesce(s.platform_source, 'unknown') || '|' || coalesce(sum(t.tokens), 0)
        from (
            select memory_session_id, discovery_tokens as tokens from observations
            union all
            select memory_session_id, discovery_tokens as tokens from session_summaries
        ) t
        left join sdk_sessions s on s.memory_session_id = t.memory_session_id
        group by coalesce(s.platform_source, 'unknown')
        order by sum(t.tokens) desc;
        """

        var sources: [(String, Int)] = []
        let output = Self.run("/usr/bin/sqlite3", [databasePath, sql]).stdout
        for line in output.split(separator: "\n").map(String.init) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { continue }
            switch key {
            case "work":
                stats.totalTokens = Int(parts.dropFirst().first ?? "0") ?? 0
            case "chars":
                let chars = Int(parts.dropFirst().first ?? "0") ?? 0
                stats.readTokens = max(0, chars / 4)
            case "source":
                guard parts.count >= 3 else { continue }
                sources.append((parts[1], Int(parts[2]) ?? 0))
            default:
                continue
            }
        }
        stats.savedTokens = max(0, stats.totalTokens - stats.readTokens)
        stats.sourceBreakdown = sources
            .filter { $0.1 > 0 }
            .prefix(4)
            .map { "\(displayPlatform($0.0)) \(compactNumber($0.1))" }
            .joined(separator: " · ")
        if stats.sourceBreakdown.isEmpty, stats.totalTokens > 0 {
            stats.sourceBreakdown = "全平台汇总"
        }
        return stats
    }

    private func displayPlatform(_ source: String) -> String {
        switch source.lowercased() {
        case "codex":
            return "Codex"
        case "claude":
            return "Claude"
        case "unknown":
            return "历史"
        default:
            return source.isEmpty ? "未知" : source
        }
    }

    private func compactNumber(_ value: Int) -> String {
        if value >= 100_000_000 {
            return String(format: "%.1f亿", Double(value) / 100_000_000.0)
        }
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000.0)
        }
        return "\(value)"
    }

    // MARK: Detail data (Req2: 异步加载 + 缓存)

    /// 立即返回缓存（如有），同时后台刷新一次。回调始终在主线程。
    private func loadMemories(_ completion: @escaping ([MemoryItem]) -> Void) {
        if let cache = cachedMemories {
            completion(cache)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = self.fetchObservations(limit: 40)
            DispatchQueue.main.async {
                self.cachedMemories = items
                completion(items)
            }
        }
    }

    private func loadSummaries(_ completion: @escaping ([SummaryItem]) -> Void) {
        if let cache = cachedSummaries {
            completion(cache)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = self.fetchSummaries(limit: 40)
            DispatchQueue.main.async {
                self.cachedSummaries = items
                completion(items)
            }
        }
    }

    private func fetchObservations(limit: Int) -> [MemoryItem] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        let sql = "select id, title, subtitle, project, type, narrative, facts, concepts, files_read, files_modified, text, created_at_epoch " +
            "from observations order by created_at_epoch desc limit \(limit);"
        let output = Self.run("/usr/bin/sqlite3", ["-json", databasePath, sql]).stdout
        guard let data = output.data(using: .utf8), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([MemoryItem].self, from: data)) ?? []
    }

    private func fetchSummaries(limit: Int) -> [SummaryItem] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        let sql = "select id, project, request, investigated, learned, completed, next_steps, created_at_epoch " +
            "from session_summaries order by created_at_epoch desc limit \(limit);"
        let output = Self.run("/usr/bin/sqlite3", ["-json", databasePath, sql]).stdout
        guard let data = output.data(using: .utf8), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([SummaryItem].self, from: data)) ?? []
    }

    // MARK: Update

    private func checkForUpdate(force: Bool = false) {
        if !force, let last = lastUpdateCheck, Date().timeIntervalSince(last) < 3600 { return }
        lastUpdateCheck = Date()

        var request = URLRequest(url: rawVersionURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 4
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let raw = String(data: data, encoding: .utf8) else { return }
            let remote = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remote.isEmpty, Self.semverGreater(remote, than: appVersion) else {
                DispatchQueue.main.async {
                    if !self.isUpdating { self.availableVersion = nil; self.dashboard.setUpdateState(nil) }
                }
                return
            }
            let ignored = UserDefaults.standard.string(forKey: ignoredVersionKey)
            DispatchQueue.main.async {
                guard !self.isUpdating else { return }
                self.availableVersion = remote
                self.dashboard.setUpdateState(remote == ignored ? nil : .available(remote))
            }
        }.resume()
    }

    private static func semverGreater(_ lhs: String, than rhs: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let a = parts(lhs), b = parts(rhs)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func startUpdate() {
        guard availableVersion != nil, !isUpdating else { return }
        isUpdating = true
        dashboard.setUpdateState(.downloading)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = self.performUpdate { state in
                DispatchQueue.main.async { self.dashboard.setUpdateState(state) }
            }
            // 成功时 install.sh 会经 launchctl kickstart 重启本进程，下面通常不会执行到
            if !ok {
                NSWorkspace.shared.open(repoWebURL)
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.dashboard.setUpdateState(.failed)
                }
            }
        }
    }

    private func dismissUpdate() {
        if let version = availableVersion {
            UserDefaults.standard.set(version, forKey: ignoredVersionKey)
        }
        dashboard.setUpdateState(nil)
    }

    /// 下载最新源码 → 本地编译 → 安装 → 重启。任一步失败返回 false。
    private func performUpdate(progress: @escaping (UpdateUIState) -> Void) -> Bool {
        let path = "/usr/bin:/bin:/usr/sbin:/sbin"
        let tmp = NSTemporaryDirectory() + "claudemembar-update-\(UUID().uuidString)"
        let tarPath = tmp + "/src.tar.gz"
        guard (try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)) != nil else {
            return false
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let download = Self.run("/usr/bin/curl",
                                ["-fsSL", "-o", tarPath, tarballURL.absoluteString],
                                env: ["PATH": path])
        if download.status != 0 { return false }

        progress(.building)
        let extract = Self.run("/usr/bin/tar", ["-xzf", tarPath, "-C", tmp], env: ["PATH": path])
        if extract.status != 0 { return false }

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: tmp),
              let repoDir = entries.first(where: { $0.hasPrefix("ClaudeMemBar-") }) else { return false }
        let installScript = tmp + "/" + repoDir + "/scripts/install.sh"
        guard FileManager.default.fileExists(atPath: installScript) else { return false }

        progress(.installing)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        let install = Self.run("/bin/bash", [installScript], env: env)
        return install.status == 0
    }

    private func render() {
        let isReadyStatus = lastHealth?.status == "ok" || lastHealth?.status == "ready"
        let statusText = isReadyStatus ? "运行中" : "离线"
        let symbolName = isReadyStatus ? "brain.head.profile" : "exclamationmark.triangle"

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: statusText)
            button.title = lastCounts.observations > 0 ? " \(lastCounts.observations)" : " 记忆"
            button.toolTip = "\(appName): \(statusText)"
        }
        dashboard.update(health: lastHealth, counts: lastCounts, refreshedAt: lastRefresh)
        dashboard.updateSystem(system: lastSystemStats, tokens: lastTokenStats, refreshedAt: lastRefresh)
    }

    private func setTransientStatus(_ title: String) {
        if let button = statusItem.button {
            button.title = " ..."
            button.toolTip = "\(appName): \(title)"
        }
    }

    private static func run(_ executable: String, _ arguments: [String], env: [String: String]? = nil) -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env { process.environment = env }

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
