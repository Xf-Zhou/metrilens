import AppKit

final class ThemedPopoverPanel: NSPanel {
    private let backgroundView = ThemedPopoverBackgroundView()
    private weak var hostedView: NSView?
    private weak var anchorWindow: NSWindow?
    private var hostedConstraints: [NSLayoutConstraint] = []
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    var onDismiss: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.transient, .moveToActiveSpace]
        contentView = backgroundView
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    deinit {
        stopMonitoringOutsideClicks()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(
        hosting view: NSView,
        bodySize: NSSize,
        color: NSColor,
        relativeTo button: NSStatusBarButton
    ) {
        attach(view, bodySize: bodySize)
        backgroundView.fillColor = color
        anchorWindow = button.window
        let panelSize = NSSize(
            width: bodySize.width,
            height: bodySize.height + ThemedPopoverBackgroundView.arrowHeight
        )
        setContentSize(panelSize)
        let placement = placement(for: panelSize, relativeTo: button)
        backgroundView.arrowX = placement.arrowX
        setFrameOrigin(placement.origin)
        makeKeyAndOrderFront(nil)
        startMonitoringOutsideClicks()
    }

    func update(bodySize: NSSize, color: NSColor) {
        backgroundView.fillColor = color
        guard isVisible else { return }
        let panelSize = NSSize(
            width: bodySize.width,
            height: bodySize.height + ThemedPopoverBackgroundView.arrowHeight
        )
        setContentSize(panelSize)
        hostedConstraints.last?.constant = bodySize.height
        contentView?.layoutSubtreeIfNeeded()
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        stopMonitoringOutsideClicks()
        onDismiss?()
    }

    func detachHostedView() {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints.removeAll()
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    private func attach(_ view: NSView, bodySize: NSSize) {
        if hostedView !== view {
            detachHostedView()
            hostedView = view
            view.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(view)
            hostedConstraints = [
                view.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
                view.heightAnchor.constraint(equalToConstant: bodySize.height)
            ]
            NSLayoutConstraint.activate(hostedConstraints)
        } else {
            hostedConstraints.last?.constant = bodySize.height
        }
    }

    private func placement(
        for panelSize: NSSize,
        relativeTo button: NSStatusBarButton
    ) -> (origin: NSPoint, arrowX: CGFloat) {
        guard let anchorWindow = button.window else {
            return (origin: .zero, arrowX: panelSize.width / 2)
        }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = anchorWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return Self.placement(panelSize: panelSize, anchor: anchor, visibleFrame: visible)
    }

    static func placement(
        panelSize: NSSize,
        anchor: NSRect,
        visibleFrame: NSRect
    ) -> (origin: NSPoint, arrowX: CGFloat) {
        let idealX = anchor.midX - panelSize.width / 2
        let clampedX = min(
            max(idealX, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let arrowInset = ThemedPopoverBackgroundView.cornerRadius
            + ThemedPopoverBackgroundView.arrowHalfWidth
        let arrowX = min(
            max(anchor.midX - clampedX, arrowInset),
            panelSize.width - arrowInset
        )
        return (
            origin: NSPoint(x: clampedX, y: anchor.minY - panelSize.height + 1),
            arrowX: arrowX
        )
    }

    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window !== self && event.window !== self.anchorWindow {
                DispatchQueue.main.async {
                    self.dismiss()
                }
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismiss()
            }
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}

private final class ThemedPopoverBackgroundView: NSView {
    static let arrowHeight: CGFloat = 10
    static let arrowHalfWidth: CGFloat = 9
    static let cornerRadius: CGFloat = 12
    var fillColor = NSColor.windowBackgroundColor {
        didSet { needsDisplay = true }
    }
    var arrowX: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height - Self.arrowHeight
        )
        let shape = NSBezierPath(
            roundedRect: body,
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )
        let center = arrowX == 0 ? bounds.midX : arrowX
        shape.move(to: NSPoint(x: center - Self.arrowHalfWidth, y: body.maxY - 1))
        shape.line(to: NSPoint(x: center, y: bounds.maxY))
        shape.line(to: NSPoint(x: center + Self.arrowHalfWidth, y: body.maxY - 1))
        shape.close()
        fillColor.setFill()
        shape.fill()
    }
}
