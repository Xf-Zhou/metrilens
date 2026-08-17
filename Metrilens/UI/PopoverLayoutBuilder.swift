import AppKit

struct PopoverLayoutActions {
    let openAbout: Selector
    let openPreferences: Selector
    let resetSessionMaximum: Selector
    let quitApplication: Selector
}

enum PopoverLayoutBuilder {
    static func makeContentController(
        for owner: PopoverController,
        target: AnyObject,
        actions: PopoverLayoutActions
    ) -> NSViewController {
        let controller = NSViewController()
        let root = NSView()
        controller.view = root
        let document = PopoverFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false

        owner.contentScrollView.drawsBackground = false
        owner.contentScrollView.hasVerticalScroller = true
        owner.contentScrollView.autohidesScrollers = true
        owner.contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        owner.contentScrollView.documentView = document
        root.addSubview(owner.contentScrollView)

        owner.titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        configureButton(
            owner.aboutButton,
            symbol: "info.circle",
            target: target,
            action: actions.openAbout,
            keyEquivalent: "i",
            modifiers: .command
        )
        configureButton(
            owner.settingsButton,
            symbol: "gearshape",
            target: target,
            action: actions.openPreferences,
            keyEquivalent: ",",
            modifiers: .command
        )

        let header = NSStackView(
            views: [owner.titleLabel, NSView(), owner.aboutButton, owner.settingsButton]
        )
        header.orientation = .horizontal
        header.alignment = .centerY

        let cpuRow = makeRow(title: owner.cpuTitle, value: owner.cpuValue)
        configureSummary(owner.cpuSummaryValue)
        configureSparkline(owner.cpuSparkline)
        configureSection(
            owner.cpuSection,
            views: [cpuRow, owner.cpuSummaryValue, owner.cpuSparkline]
        )

        let memoryRow = makeRow(title: owner.memoryTitle, value: owner.memoryValue)
        configureSummary(owner.memorySummaryValue)
        configureSparkline(owner.memorySparkline)
        configureSection(
            owner.memorySection,
            views: [memoryRow, owner.memorySummaryValue, owner.memorySparkline]
        )

        let batteryLevelRow = makeRow(
            title: owner.batteryLevelTitle,
            value: owner.batteryLevelValue
        )
        let batteryStateRow = makeRow(
            title: owner.batteryStateTitle,
            value: owner.batteryStateValue
        )
        let batteryCyclesRow = makeRow(
            title: owner.batteryCyclesTitle,
            value: owner.batteryCyclesValue
        )
        configureRow(
            owner.batteryHealthRow,
            title: owner.batteryHealthTitle,
            value: owner.batteryHealthValue
        )
        configureRow(
            owner.batteryRow,
            title: owner.batteryTitle,
            value: owner.batteryValue
        )
        owner.resetSessionMaximumButton.target = target
        owner.resetSessionMaximumButton.action = actions.resetSessionMaximum
        owner.resetSessionMaximumButton.isBordered = false
        owner.resetSessionMaximumButton.font = .systemFont(ofSize: 10)
        configureRow(
            owner.batterySessionMaximumRow,
            title: owner.batterySessionMaximumTitle,
            value: owner.batterySessionMaximumValue,
            trailing: owner.resetSessionMaximumButton
        )
        configureRow(
            owner.batteryMaximumRow,
            title: owner.batteryMaximumTitle,
            value: owner.batteryMaximumValue
        )
        configureSection(
            owner.batterySection,
            views: [
                owner.batterySectionTitle,
                batteryLevelRow,
                batteryStateRow,
                batteryCyclesRow,
                owner.batteryHealthRow,
                owner.batteryRow,
                owner.batterySessionMaximumRow,
                owner.batteryMaximumRow
            ]
        )

        let networkDownloadRow = makeRow(
            title: owner.networkDownloadTitle,
            value: owner.networkDownloadValue
        )
        let networkUploadRow = makeRow(
            title: owner.networkUploadTitle,
            value: owner.networkUploadValue
        )
        configureSection(
            owner.networkSection,
            views: [owner.networkSectionTitle, networkDownloadRow, networkUploadRow]
        )
        let diskUsageRow = makeRow(
            title: owner.diskUsageTitle,
            value: owner.diskUsageValue
        )
        let diskFreeRow = makeRow(
            title: owner.diskFreeTitle,
            value: owner.diskFreeValue
        )
        configureSection(
            owner.diskSection,
            views: [owner.diskSectionTitle, diskUsageRow, diskFreeRow]
        )

        for title in [
            owner.batterySectionTitle,
            owner.networkSectionTitle,
            owner.diskSectionTitle
        ] {
            configureSectionTitle(title)
        }

        owner.metricSectionsStack.orientation = .vertical
        owner.metricSectionsStack.alignment = .width
        owner.metricSectionsStack.spacing = 12
        let metricSections = [
            owner.cpuSection,
            owner.memorySection,
            owner.batterySection,
            owner.networkSection,
            owner.diskSection
        ]
        owner.metricSectionsStack.setViews(metricSections, in: .top)
        for section in metricSections {
            section.widthAnchor.constraint(
                equalTo: owner.metricSectionsStack.widthAnchor
            ).isActive = true
        }
        let thermalRow = makeRow(title: owner.thermalTitle, value: owner.thermalValue)
        owner.heatDiagnosisTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        owner.heatDiagnosisValue.textColor = .secondaryLabelColor
        owner.heatDiagnosisValue.font = .systemFont(ofSize: 11)

        owner.updatedValue.textColor = .secondaryLabelColor
        owner.updatedValue.font = .systemFont(ofSize: 11)
        owner.quitButton.target = target
        owner.quitButton.action = actions.quitApplication
        owner.quitButton.isBordered = false
        owner.quitButton.font = .systemFont(ofSize: 11)
        owner.quitButton.keyEquivalent = "q"
        owner.quitButton.keyEquivalentModifierMask = .command
        let footer = NSStackView(views: [owner.updatedValue, NSView(), owner.quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let rows = [
            header,
            separator(),
            owner.metricSectionsStack,
            separator(),
            thermalRow,
            owner.heatDiagnosisTitle,
            owner.heatDiagnosisValue,
            separator(),
            footer
        ]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        owner.contentStack = stack

        NSLayoutConstraint.activate([
            owner.contentScrollView.leadingAnchor.constraint(
                equalTo: root.safeAreaLayoutGuide.leadingAnchor
            ),
            owner.contentScrollView.trailingAnchor.constraint(
                equalTo: root.safeAreaLayoutGuide.trailingAnchor
            ),
            owner.contentScrollView.topAnchor.constraint(
                equalTo: root.safeAreaLayoutGuide.topAnchor
            ),
            owner.contentScrollView.bottomAnchor.constraint(
                equalTo: root.safeAreaLayoutGuide.bottomAnchor
            ),
            document.leadingAnchor.constraint(
                equalTo: owner.contentScrollView.contentView.leadingAnchor
            ),
            document.topAnchor.constraint(
                equalTo: owner.contentScrollView.contentView.topAnchor
            ),
            document.widthAnchor.constraint(
                equalTo: owner.contentScrollView.contentView.widthAnchor
            ),
            stack.leadingAnchor.constraint(
                equalTo: document.leadingAnchor,
                constant: 24
            ),
            stack.trailingAnchor.constraint(
                equalTo: document.trailingAnchor,
                constant: -24
            ),
            stack.topAnchor.constraint(
                equalTo: document.topAnchor,
                constant: 16
            ),
            stack.bottomAnchor.constraint(
                equalTo: document.bottomAnchor,
                constant: -14
            )
        ])
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        owner.aboutButton.setAccessibilityIdentifier("metrilens.popover.about")
        owner.settingsButton.setAccessibilityIdentifier("metrilens.popover.settings")
        owner.quitButton.setAccessibilityIdentifier("metrilens.popover.quit")
        root.setAccessibilityIdentifier("metrilens.popover.content")
        return controller
    }

    private static func configureButton(
        _ button: NSButton,
        symbol: String,
        target: AnyObject,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )
        button.target = target
        button.action = action
        button.isBordered = false
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = modifiers
    }

    private static func configureSection(
        _ section: NSStackView,
        views: [NSView]
    ) {
        section.setViews(views, in: .top)
        section.orientation = .vertical
        section.alignment = .width
        section.spacing = 6
    }

    private static func makeRow(
        title: NSTextField,
        value: NSTextField
    ) -> NSStackView {
        let row = NSStackView()
        configureRow(row, title: title, value: value)
        return row
    }

    private static func configureRow(
        _ row: NSStackView,
        title: NSTextField,
        value: NSTextField,
        trailing: NSView? = nil
    ) {
        title.textColor = .secondaryLabelColor
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        var views: [NSView] = [title, NSView(), value]
        if let trailing { views.append(trailing) }
        row.setViews(views, in: .leading)
        row.orientation = .horizontal
        row.alignment = .centerY
    }

    private static func configureSummary(_ field: NSTextField) {
        field.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.alignment = .right
    }

    private static func configureSectionTitle(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 10, weight: .semibold)
        field.textColor = .tertiaryLabelColor
    }

    private static func configureSparkline(_ view: SparklineView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

private final class PopoverFlippedView: NSView {
    override var isFlipped: Bool { true }
}
