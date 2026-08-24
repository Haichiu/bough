import AppKit

// Generates MindFlow app icon at every required size.
let outDir = CommandLine.arguments[1]
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let rounded = NSBezierPath(roundedRect: rect, xRadius: 184, yRadius: 184)
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.30, alpha: 1),
    NSColor(calibratedRed: 0.26, green: 0.40, blue: 0.76, alpha: 1),
])!.draw(in: rounded, angle: -90)

func dot(_ point: NSPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius,
                                width: radius * 2, height: radius * 2)).fill()
}

let center = NSPoint(x: 470, y: 500)
let satellites: [(NSPoint, NSColor)] = [
    (NSPoint(x: 740, y: 690), NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.35, alpha: 1)),
    (NSPoint(x: 775, y: 430), NSColor(calibratedRed: 0.35, green: 0.75, blue: 0.55, alpha: 1)),
    (NSPoint(x: 700, y: 230), NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.30, alpha: 1)),
]
for (point, _) in satellites {
    let line = NSBezierPath()
    line.move(to: center)
    line.line(to: point)
    line.lineWidth = 28
    line.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke()
    line.stroke()
}
dot(center, radius: 82, color: .white)
for (point, color) in satellites {
    dot(point, radius: 56, color: color)
}

image.unlockFocus()

for pixelSize in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(pixelSize)x\(pixelSize).png"))
}
print("icons generated")
