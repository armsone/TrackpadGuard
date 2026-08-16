import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
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
            return true
        }
        return image
    }()
}
