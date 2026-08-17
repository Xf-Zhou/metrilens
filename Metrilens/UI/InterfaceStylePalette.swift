import AppKit

struct InterfaceStylePalette {
    let background: NSColor
    let surface: NSColor
    let primary: NSColor
    let secondary: NSColor
    let tertiary: NSColor
    let accent: NSColor
    let divider: NSColor
    let appearance: NSAppearance.Name?

    init(_ style: InterfaceStyle) {
        switch style {
        case .system:
            background = .windowBackgroundColor
            surface = .controlBackgroundColor
            primary = .labelColor
            secondary = .secondaryLabelColor
            tertiary = .tertiaryLabelColor
            accent = .controlAccentColor
            divider = .separatorColor
            appearance = nil
        case .deepSea:
            background = NSColor(hex: 0x0B1825)
            surface = NSColor(hex: 0x12283A)
            primary = NSColor(hex: 0xE8F3F8)
            secondary = NSColor(hex: 0x92ABB7)
            tertiary = NSColor(hex: 0x668391)
            accent = NSColor(hex: 0x42C7D9)
            divider = NSColor(hex: 0x274557)
            appearance = .darkAqua
        case .engineAmber:
            background = NSColor(hex: 0x191711)
            surface = NSColor(hex: 0x282218)
            primary = NSColor(hex: 0xF6ECD8)
            secondary = NSColor(hex: 0xC7B58E)
            tertiary = NSColor(hex: 0x8F8061)
            accent = NSColor(hex: 0xF1B84B)
            divider = NSColor(hex: 0x51452D)
            appearance = .darkAqua
        }
    }
}

final class InterfaceStylePreviewView: NSView {
    var style: InterfaceStyle = .system {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 492, height: 54)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let palette = InterfaceStylePalette(style)
        let card = bounds.insetBy(dx: 1, dy: 1)
        palette.background.setFill()
        NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8).fill()
        palette.divider.setStroke()
        let border = NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        palette.primary.setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 34, width: 74, height: 6), xRadius: 3, yRadius: 3).fill()
        palette.secondary.setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 21, width: 126, height: 4), xRadius: 2, yRadius: 2).fill()

        let wave = NSBezierPath()
        wave.lineWidth = 2
        wave.move(to: NSPoint(x: 166, y: 17))
        for index in 0...24 {
            let x = 166 + CGFloat(index) * 12
            let y = 20 + sin(CGFloat(index) * 0.7) * 9
            wave.line(to: NSPoint(x: x, y: y))
        }
        palette.accent.setStroke()
        wave.stroke()
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
