// Renders Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

// macOS squircle: superellipse |x/a|^n + |y/b|^n = 1, n ~= 5
func squirclePath(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let path = CGMutablePath()
    let steps = 512
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * pow(abs(c), 2 / n) * (c >= 0 ? 1 : -1)
        let y = cy + b * pow(abs(s), 2 / n) * (s >= 0 ? 1 : -1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(_ ctx: CGContext) {
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squirclePath(in: iconRect)

    // background gradient
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let top = CGColor(red: 0.463, green: 0.412, blue: 0.965, alpha: 1)     // #7669F6
    let bottom = CGColor(red: 0.278, green: 0.220, blue: 0.780, alpha: 1)  // #4738C7
    let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                           end: CGPoint(x: iconRect.midX, y: iconRect.minY),
                           options: [])
    ctx.restoreGState()

    // subtle top sheen
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let sheenTop = CGColor(gray: 1, alpha: 0.14)
    let sheenClear = CGColor(gray: 1, alpha: 0)
    let sheen = CGGradient(colorsSpace: space, colors: [sheenTop, sheenClear] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                           end: CGPoint(x: iconRect.midX, y: iconRect.maxY - 500),
                           options: [])
    ctx.restoreGState()

    // chart glyph: x-axis baseline + 3 ascending bars (chart.bar.xaxis)
    let glyph = CGColor(gray: 1, alpha: 0.96)
    ctx.setFillColor(glyph)

    let barWidth: CGFloat = 118
    let gap: CGFloat = 62
    let baselineY: CGFloat = 330
    let axisHeight: CGFloat = 30
    let barGapAboveAxis: CGFloat = 26
    let corner: CGFloat = 16

    // x axis
    let axisRect = CGRect(x: 282, y: baselineY, width: 460, height: axisHeight)
    ctx.addPath(CGPath(roundedRect: axisRect, cornerWidth: axisHeight / 2,
                       cornerHeight: axisHeight / 2, transform: nil))
    ctx.fillPath()

    // bars
    let heights: [CGFloat] = [150, 240, 330]
    let totalWidth = 3 * barWidth + 2 * gap
    var x = (canvas - totalWidth) / 2
    for h in heights {
        let r = CGRect(x: x, y: baselineY + axisHeight + barGapAboveAxis,
                       width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner,
                           transform: nil))
        ctx.fillPath()
        x += barWidth + gap
    }
}

func renderPNG(size: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.scaleBy(x: size / canvas, y: size / canvas)
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        drawIcon(ctx)
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for spec in specs {
    renderPNG(size: spec.px, to: iconset.appendingPathComponent(spec.name).path)
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
print("Wrote \(out.path)")
