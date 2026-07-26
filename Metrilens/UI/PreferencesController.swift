import AppKit

final class PreferencesController: NSWindowController {
    static let sourceInformation =
        "温度说明：V1 只读取 AppleSmartBattery 提供的电池温度，并显示 macOS 系统热状态。CPU/GPU 精确温度不在 V1 范围内。\n\n"
        + "内存说明：“Metrilens 占用”由 internal、wired 与 compressor 内存组成；这是稳定的产品口径，不承诺与活动监视器完全一致。"

    private let preferences: AppPreferences
    private let loginItemController: LoginItemController
    private let metricPopup = NSPopUpButton()
    private let intervalPopup = NSPopUpButton()
    private let loginCheckbox = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private let sparklineCheckbox = NSButton(checkboxWithTitle: "显示 CPU 微型折线", target: nil, action: nil)

    init(preferences: AppPreferences, loginItemController: LoginItemController) {
        self.preferences = preferences
        self.loginItemController = loginItemController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Metrilens 设置"
        window.center()
        super.init(window: window)
        buildContent()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        metricPopup.addItems(withTitles: PrimaryMetric.allCases.map(\.menuTitle))
        metricPopup.target = self
        metricPopup.action = #selector(metricChanged)

        intervalPopup.addItems(withTitles: ["1 秒", "2 秒", "5 秒"])
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)

        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)
        sparklineCheckbox.target = self
        sparklineCheckbox.action = #selector(sparklineChanged)

        let sourceInfo = NSTextField(wrappingLabelWithString:
            Self.sourceInformation
        )
        sourceInfo.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            settingRow("菜单栏主指标", control: metricPopup),
            settingRow("CPU/内存刷新", control: intervalPopup),
            loginCheckbox,
            sparklineCheckbox,
            separator(),
            sourceInfo
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            sourceInfo.widthAnchor.constraint(equalToConstant: 372)
        ])
    }

    private func settingRow(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        let spacer = NSView()
        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 372).isActive = true
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 372).isActive = true
        return box
    }

    private func refresh() {
        let snapshot = preferences.snapshot
        metricPopup.selectItem(at: PrimaryMetric.allCases.firstIndex(of: snapshot.primaryMetric) ?? 0)
        intervalPopup.selectItem(at: [1.0, 2.0, 5.0].firstIndex(of: snapshot.refreshInterval) ?? 0)
        loginCheckbox.state = loginItemController.isEnabled ? .on : .off
        sparklineCheckbox.state = snapshot.showsSparkline ? .on : .off
    }

    @objc private func metricChanged() {
        let index = max(0, metricPopup.indexOfSelectedItem)
        preferences.setPrimaryMetric(PrimaryMetric.allCases[index])
    }

    @objc private func intervalChanged() {
        let intervals = [1.0, 2.0, 5.0]
        preferences.setRefreshInterval(intervals[max(0, intervalPopup.indexOfSelectedItem)])
    }

    @objc private func loginChanged() {
        let enabled = loginCheckbox.state == .on
        switch loginItemController.setEnabled(enabled) {
        case .enabled:
            preferences.setLaunchAtLogin(true)
        case .disabled:
            preferences.setLaunchAtLogin(false)
        case .requiresApproval:
            preferences.setLaunchAtLogin(true)
            presentMessage(
                title: "需要用户批准",
                message: "请在“系统设置 → 通用 → 登录项”中允许 Metrilens。"
            )
        case let .failed(error):
            loginCheckbox.state = enabled ? .off : .on
            presentMessage(title: "无法更新登录项", message: error.localizedDescription)
        }
    }

    @objc private func sparklineChanged() {
        preferences.setShowsSparkline(sparklineCheckbox.state == .on)
    }

    private func presentMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let window {
            alert.beginSheetModal(for: window)
        }
    }
}
