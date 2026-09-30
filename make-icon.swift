import AppKit

// Native vector artwork rasterized at every ICNS size; no external image assets.
func drawIcon(size: Int, destination: URL) throws {
    let pixels = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = pixels / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.29, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.27, green: 0.32, blue: 0.59, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.23, alpha: 1))!.draw(in: tile, angle: -65)
    NSColor.white.withAlphaComponent(0.15).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    let cream = NSColor(calibratedRed: 1, green: 0.95, blue: 0.75, alpha: 1)
    let coffee = NSColor(calibratedRed: 0.20, green: 0.11, blue: 0.10, alpha: 1)

    // Handle is drawn first so it naturally tucks behind the cup.
    let handle = NSBezierPath(ovalIn: NSRect(x: 620, y: 320, width: 210, height: 215))
    cream.setStroke()
    handle.lineWidth = 52
    handle.stroke()

    let cup = NSBezierPath()
    cup.move(to: NSPoint(x: 245, y: 530))
    cup.line(to: NSPoint(x: 690, y: 530))
    cup.line(to: NSPoint(x: 655, y: 315))
    cup.curve(to: NSPoint(x: 530, y: 235), controlPoint1: NSPoint(x: 640, y: 255), controlPoint2: NSPoint(x: 585, y: 235))
    cup.line(to: NSPoint(x: 405, y: 235))
    cup.curve(to: NSPoint(x: 280, y: 315), controlPoint1: NSPoint(x: 350, y: 235), controlPoint2: NSPoint(x: 295, y: 255))
    cup.close()
    NSGradient(starting: cream, ending: NSColor(calibratedRed: 0.88, green: 0.75, blue: 0.43, alpha: 1))!.draw(in: cup, angle: -90)

    let rim = NSBezierPath(ovalIn: NSRect(x: 240, y: 475, width: 455, height: 120))
    cream.setFill()
    rim.fill()
    let drink = NSBezierPath(ovalIn: NSRect(x: 272, y: 505, width: 391, height: 67))
    coffee.setFill()
    drink.fill()
    let shine = NSBezierPath(ovalIn: NSRect(x: 330, y: 537, width: 230, height: 14))
    NSColor.white.withAlphaComponent(0.28).setFill()
    shine.fill()

    let saucer = NSBezierPath(ovalIn: NSRect(x: 180, y: 168, width: 650, height: 128))
    NSGradient(starting: cream, ending: NSColor(calibratedRed: 0.80, green: 0.65, blue: 0.34, alpha: 1))!.draw(in: saucer, angle: -90)

    // Three geometric Z marks double as steam and stay recognisable without text rendering.
    func drawZ(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, line: CGFloat) {
        let z = NSBezierPath()
        z.move(to: NSPoint(x: x, y: y + height))
        z.line(to: NSPoint(x: x + width, y: y + height))
        z.line(to: NSPoint(x: x, y: y))
        z.line(to: NSPoint(x: x + width, y: y))
        z.lineWidth = line
        z.lineCapStyle = .round
        z.lineJoinStyle = .round
        cream.setStroke()
        z.stroke()
    }
    drawZ(x: 350, y: 660, width: 100, height: 100, line: 27)
    drawZ(x: 485, y: 710, width: 125, height: 125, line: 31)
    drawZ(x: 645, y: 765, width: 145, height: 145, line: 34)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: destination)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size, destination: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2, destination: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
