import AppKit

final class AboutController: NSWindowController {
    private let build: AppBuildInformation
    private let diagnosticProvider: () -> String
    private let copyButton = NSButton()

    init(
        build: AppBuildInformation = .current(),
        diagnosticProvider: @escaping () -> String
    ) {
        self.build = build
        self.diagnosticProvider = diagnosticProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 Metrilens"
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityLabel("Metrilens App 图标")

        let name = NSTextField(labelWithString: "Metrilens")
        name.font = .systemFont(ofSize: 24, weight: .semibold)
        name.alignment = .center

        let version = NSTextField(
            labelWithString: "版本 \(build.version)（\(build.build)）"
        )
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let summary = NSTextField(
            wrappingLabelWithString:
                "轻量、隐私优先的 Apple Silicon 菜单栏系统状态查看器。"
        )
        summary.alignment = .center
        summary.textColor = .secondaryLabelColor

        let privacy = NSTextField(
            wrappingLabelWithString: DiagnosticReport.privacyDisclosure
        )
        privacy.alignment = .center
        privacy.textColor = .secondaryLabelColor

        copyButton.title = "复制诊断信息"
        copyButton.target = self
        copyButton.action = #selector(copyDiagnostics)
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command, .shift]
        copyButton.setAccessibilityHelp("复制不含个人标识的诊断摘要")

        let done = NSButton(title: "完成", target: self, action: #selector(closeWindow))
        done.keyEquivalent = "\r"

        let buttons = NSStackView(views: [copyButton, done])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [icon, name, version, summary, privacy, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88),
            summary.widthAnchor.constraint(equalToConstant: 380),
            privacy.widthAnchor.constraint(equalToConstant: 380)
        ])
        window?.initialFirstResponder = copyButton
    }

    @objc private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticProvider(), forType: .string)
        copyButton.title = "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "复制诊断信息"
        }
    }

    @objc private func closeWindow() {
        close()
    }
}
