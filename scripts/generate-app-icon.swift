import AppKit
import ImageIO

let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: "/tmp/Kite.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocusFlipped(false)
        guard let context = NSGraphicsContext.current?.cgContext else { fatalError("Unable to create graphics context") }
        let s = CGFloat(pixels) / 36
        context.scaleBy(x: s, y: s)
        context.translateBy(x: 0, y: 36)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(NSColor(red: 0.12, green: 0.72, blue: 0.58, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 36, height: 36), cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.fillPath()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let curve = CGMutablePath()
        curve.move(to: CGPoint(x: 6, y: 21))
        curve.addCurve(to: CGPoint(x: 29, y: 12), control1: CGPoint(x: 12, y: 8), control2: CGPoint(x: 22, y: 28))
        context.addPath(curve)
        context.strokePath()
        context.move(to: CGPoint(x: 29, y: 12)); context.addLine(to: CGPoint(x: 24, y: 12))
        context.move(to: CGPoint(x: 29, y: 12)); context.addLine(to: CGPoint(x: 28, y: 17))
        context.strokePath()
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: 8, y: 8, width: 4, height: 4))
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png") as CFURL, "public.png" as CFString, 1, nil) else { fatalError("Unable to write icon") }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Unable to finalize icon") }
    }
}
