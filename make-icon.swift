// Draws AppIcon.icns from icon.svg, or from icon-local.svg when present (a personal, git-ignored icon).
// macOS applies its own rounded mask and glass edge.
// Run: swift make-icon.swift && iconutil -c icns AppIcon.iconset && rm -r AppIcon.iconset
import AppKit
let svg = NSImage(contentsOfFile: FileManager.default.fileExists(atPath: "icon-local.svg") ? "icon-local.svg" : "icon.svg")!
try? FileManager.default.createDirectory(atPath: "AppIcon.iconset", withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.current = nil
        try! rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "AppIcon.iconset/icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
    }
}
