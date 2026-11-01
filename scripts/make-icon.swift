// Draws the app icon (1024×1024 PNG). Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let background = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedWhite: 0.20, alpha: 1), NSColor(calibratedWhite: 0.07, alpha: 1)])!
    .draw(in: background, angle: -90)

// The "screen" edge with a notch-shaped island hanging from it.
let island = NSRect(x: size / 2 - 230, y: body.maxY - 250, width: 460, height: 150)
NSColor.black.setFill()
NSBezierPath(roundedRect: island, xRadius: 75, yRadius: 75).fill()
NSBezierPath(rect: NSRect(x: island.minX, y: island.midY, width: island.width, height: body.maxY - island.midY)).fill()

// Little music bars inside the island.
NSColor.white.setFill()
let heights: [CGFloat] = [40, 70, 52, 82]
for (i, h) in heights.enumerated() {
    let x = island.maxX - 150 + CGFloat(i) * 26
    NSBezierPath(roundedRect: NSRect(x: x, y: island.midY - h / 2, width: 14, height: h), xRadius: 7, yRadius: 7).fill()
}
NSColor.systemOrange.setFill()
NSBezierPath(ovalIn: NSRect(x: island.minX + 50, y: island.midY - 32, width: 64, height: 64)).fill()

// Shelf tray below.
NSColor(calibratedWhite: 1, alpha: 0.85).setStroke()
let tray = NSBezierPath()
tray.lineWidth = 34
tray.lineCapStyle = .round
tray.lineJoinStyle = .round
tray.move(to: NSPoint(x: 300, y: 470))
tray.line(to: NSPoint(x: 300, y: 330))
tray.line(to: NSPoint(x: 724, y: 330))
tray.line(to: NSPoint(x: 724, y: 470))
tray.stroke()
let arrow = NSBezierPath()
arrow.lineWidth = 34
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 512, y: 600))
arrow.line(to: NSPoint(x: 512, y: 400))
arrow.move(to: NSPoint(x: 440, y: 470))
arrow.line(to: NSPoint(x: 512, y: 400))
arrow.line(to: NSPoint(x: 584, y: 470))
arrow.stroke()

image.unlockFocus()

let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
