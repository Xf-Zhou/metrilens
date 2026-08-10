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
        window?.title = language.localized("About Metrilens")
        icon.setAccessibilityLabel(
            language.localized("Metrilens App Icon")
        )
        versionLabel.stringValue = Self.versionText(build: build, language: language)
        summaryLabel.stringValue = language.localized("A lightweight, privacy-first Apple Silicon menu bar system monitor.")
        privacyLabel.stringValue = DiagnosticReport.privacyDisclosure(
            language: language
        )
        copyButton.title = language.localized("Copy Diagnostics")
        copyButton.setAccessibilityHelp(
            language.localized("Copy a diagnostic summary without personal identifiers")
        )
        saveButton.title = language.localized("Save Diagnostic Report…")
        saveButton.setAccessibilityHelp(
            language.localized("Save the privacy-safe diagnostic summary as a text file")
        )
        doneButton.title = language.localized("Done")
    }

    @objc private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticProvider(), forType: .string)
        copyButton.title = language.localized("Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.copyButton.title = self.language.localized("Copy Diagnostics")
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
                alert.messageText = self.language.localized("Could Not Save Diagnostic Report")
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

    static func versionText(
        build: AppBuildInformation,
        language: AppLanguage
    ) -> String {
        language.localized(
            "about.version",
            arguments: build.version ?? language.localized("Unknown"),
            build.build ?? language.localized("Unknown")
        )
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
