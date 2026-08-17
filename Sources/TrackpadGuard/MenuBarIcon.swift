import AppKit

enum MenuBarIcon {
    static let image = makeImage(overlayColor: nil)
    static let lockedImage = makeImage(overlayColor: .systemRed.withAlphaComponent(0.72))

    private static func makeImage(overlayColor: NSColor?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        guard let source = NSApplication.shared.applicationIconImage else {
            return NSImage(size: size)
        }
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(
                in: rect,
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1
            )
            if let overlayColor {
                overlayColor.setFill()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        return image
    }
}
