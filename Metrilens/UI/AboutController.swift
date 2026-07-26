import AppKit
import UniformTypeIdentifiers

final class AboutController: NSWindowController {
    private let build: AppBuildInformation
    private let diagnosticProvider: () -> String
    private var language: AppLanguage

    private let icon = NSImageView(image: NSApp.applicationIconImage)
    private let nameLabel = NSTextField(labelWithString: "Metrilens")
    private let versionLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let privacyLabel = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton()
    private let saveButton = NSButton()
    private let doneButton = NSButton()

    init(
        build: AppBuildInformation = .current(),
        language: AppLanguage = .system,
        diagnosticProvider: @escaping () -> String
    ) {
        self.build = build
        self.language = language
        self.diagnosticProvider = diagnosticProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        super.init(window: window)
        buildContent()
        applyLocalization()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        applyLocalization()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        nameLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        summaryLabel.alignment = .center
        summaryLabel.textColor = .secondaryLabelColor
        privacyLabel.alignment = .center
        privacyLabel.textColor = .secondaryLabelColor

        copyButton.target = self
        copyButton.action = #selector(copyDiagnostics)
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command, .shift]
        saveButton.target = self
        saveButton.action = #selector(saveDiagnostics)
        doneButton.target = self
        doneButton.action = #selector(closeWindow)
        doneButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [copyButton, saveButton, doneButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(
            views: [
                icon,
                nameLabel,
                versionLabel,
                summaryLabel,
                privacyLabel,
                buttons
            ]
        )
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
            summaryLabel.widthAnchor.constraint(equalToConstant: 430),
            privacyLabel.widthAnchor.constraint(equalToConstant: 430)
        ])
        window?.initialFirstResponder = copyButton
    }

    private func applyLocalization() {
        window?.title = language.text("关于 Metrilens", "About Metrilens")
        icon.setAccessibilityLabel(
            language.text("Metrilens App 图标", "Metrilens App Icon")
        )
        versionLabel.stringValue = language.text(
            "版本 \(build.version)（\(build.build)）",
            "Version \(build.version) (\(build.build))"
        )
        summaryLabel.stringValue = language.text(
            "轻量、隐私优先的 Apple Silicon 菜单栏系统状态查看器。",
            "A lightweight, privacy-first Apple Silicon menu bar system monitor."
        )
        privacyLabel.stringValue = DiagnosticReport.privacyDisclosure(
            language: language
        )
        copyButton.title = language.text("复制诊断信息", "Copy Diagnostics")
        copyButton.setAccessibilityHelp(
            language.text(
                "复制不含个人标识的诊断摘要",
                "Copy a diagnostic summary without personal identifiers"
            )
        )
        saveButton.title = language.text("保存诊断报告…", "Save Diagnostic Report…")
        saveButton.setAccessibilityHelp(
            language.text(
                "将隐私安全的诊断摘要保存为文本文件",
                "Save the privacy-safe diagnostic summary as a text file"
            )
        )
        doneButton.title = language.text("完成", "Done")
    }

    @objc private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticProvider(), forType: .string)
        copyButton.title = language.text("已复制", "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.copyButton.title = self.language.text(
                "复制诊断信息",
                "Copy Diagnostics"
            )
        }
    }

    @objc private func saveDiagnostics() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = Self.diagnosticFilename()
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                try self.diagnosticProvider().write(
                    to: url,
                    atomically: true,
                    encoding: .utf8
                )
            } catch {
                let alert = NSAlert()
                alert.messageText = self.language.text(
                    "无法保存诊断报告",
                    "Could Not Save Diagnostic Report"
                )
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window)
            }
        }
    }

    @objc private func closeWindow() {
        close()
    }

    static func diagnosticFilename(date: Date = Date()) -> String {
        "Metrilens-Diagnostics-\(filenameDateFormatter.string(from: date)).txt"
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
