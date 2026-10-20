import AppKit

@MainActor enum MacAppIcons {
    // Ask macOS for the installed app's icon, including any Finder customisation.
    // Retain a single 60 px thumbnail for the 30 pt row, not the source image.
    static func thumbnail(for bundleID: String) -> NSImage? {
        autoreleasepool {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 60,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSWorkspace.shared.icon(forFile: url.path).draw(
                in: NSRect(x: 0, y: 0, width: 60, height: 60),
                from: .zero, operation: .copy, fraction: 1)
            guard let image = bitmap.cgImage else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: 30, height: 30))
        }
    }
}
