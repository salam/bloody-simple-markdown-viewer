import AppKit

// Builds a macOS iconset from a free-form source image.
//
// The source is padded onto a square, transparent canvas rather than stretched,
// and inset so the flames do not touch the edge: the Dock and Finder draw the
// icon at its full bounds, and artwork bleeding to the border reads as clipped.
let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]) else {
    print("usage: makeicon <source.png> <out.iconset>"); exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
let content: CGFloat = 912          // ~89% of the canvas, Apple's free-form range

func render(at pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let scale = CGFloat(pixels) / canvas
    let natural = source.size
    let fit = min(content / natural.width, content / natural.height)
    let drawn = NSSize(width: natural.width * fit * scale, height: natural.height * fit * scale)
    let origin = NSPoint(x: (CGFloat(pixels) - drawn.width) / 2,
                         y: (CGFloat(pixels) - drawn.height) / 2)
    source.draw(in: NSRect(origin: origin, size: drawn),
                from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// The exact names iconutil expects; anything else is silently left out.
let wanted: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in wanted {
    let data = render(at: pixels).representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent("\(name).png"))
    print("\(name).png  \(pixels)px  \(data.count) bytes")
}
