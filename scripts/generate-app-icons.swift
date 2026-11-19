#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// MARK: - PipiBot Original "Pipi Halo" Hardware-Robot Icon Generator
// Generates macOS AppIcon.icns, iOS PNGs, and PWA PNGs from the Codex-designed PipiBot hardware emblem.

func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r / 255.0, g / 255.0, b / 255.0, a])!
}

func addSquirclePath(to ctx: CGContext, rect: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
}

func buildPipiChassisPath(in rect: CGRect) -> CGPath {
    let w = rect.width
    let h = rect.height
    let x0 = rect.minX
    let y0 = rect.minY
    let x1 = rect.maxX
    let y1 = rect.maxY
    let cx = rect.midX

    let r = min(w * 0.28, h * 0.26)
    let k: CGFloat = 0.55228475
    let sq = r * (1.0 - k * 0.92)

    let notchHalfW = w * 0.175
    let notchDepth = h * 0.036

    let p = CGMutablePath()
    p.move(to: CGPoint(x: x0 + r, y: y0))

    // Top edge + subtle architectural concave crown notch
    p.addLine(to: CGPoint(x: cx - notchHalfW, y: y0))
    p.addCurve(
        to: CGPoint(x: cx, y: y0 + notchDepth),
        control1: CGPoint(x: cx - notchHalfW * 0.55, y: y0),
        control2: CGPoint(x: cx - notchHalfW * 0.38, y: y0 + notchDepth)
    )
    p.addCurve(
        to: CGPoint(x: cx + notchHalfW, y: y0),
        control1: CGPoint(x: cx + notchHalfW * 0.38, y: y0 + notchDepth),
        control2: CGPoint(x: cx + notchHalfW * 0.55, y: y0)
    )

    // Top-right corner
    p.addLine(to: CGPoint(x: x1 - r, y: y0))
    p.addCurve(
        to: CGPoint(x: x1, y: y0 + r),
        control1: CGPoint(x: x1 - sq, y: y0),
        control2: CGPoint(x: x1, y: y0 + sq)
    )

    // Right edge & bottom-right corner
    p.addLine(to: CGPoint(x: x1, y: y1 - r))
    p.addCurve(
        to: CGPoint(x: x1 - r, y: y1),
        control1: CGPoint(x: x1, y: y1 - sq),
        control2: CGPoint(x: x1 - sq, y: y1)
    )

    // Bottom edge & bottom-left corner
    p.addLine(to: CGPoint(x: x0 + r, y: y1))
    p.addCurve(
        to: CGPoint(x: x0, y: y1 - r),
        control1: CGPoint(x: x0 + sq, y: y1),
        control2: CGPoint(x: x0, y: y1 - sq)
    )

    // Left edge & top-left corner
    p.addLine(to: CGPoint(x: x0, y: y0 + r))
    p.addCurve(
        to: CGPoint(x: x0 + r, y: y0),
        control1: CGPoint(x: x0, y: y0 + sq),
        control2: CGPoint(x: x0 + sq, y: y0)
    )

    p.closeSubpath()
    return p
}

func renderPipiBotIcon(sizePx: Int, includeRoundedBackgroundMask: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: sizePx,
        pixelsHigh: sizePx,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    let s = CGFloat(sizePx)
    let scale = s / 1024.0
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Flip CoreGraphics bottom-left origin to top-left 1024x1024 artboard
    ctx.saveGState()
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: scale, y: -scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 1. Obsidian Titanium App Icon Field (#0A0C0F -> #141922)
    let bgRect: CGRect = includeRoundedBackgroundMask
        ? CGRect(x: 56, y: 56, width: 912, height: 912)
        : CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let cornerRadius: CGFloat = includeRoundedBackgroundMask ? 204 : 0

    ctx.saveGState()
    if includeRoundedBackgroundMask {
        addSquirclePath(to: ctx, rect: bgRect, radius: cornerRadius)
        ctx.clip()
    }

    let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(18, 22, 29), cgColor(10, 12, 15), cgColor(5, 6, 8)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 512, y: bgRect.minY),
        end: CGPoint(x: 512, y: bgRect.maxY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Subtle iris-cyan ambient floor glow behind chassis
    let ambientHalo = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(99, 245, 230, 0.20), cgColor(31, 184, 176, 0.08), cgColor(10, 12, 15, 0.0)] as CFArray,
        locations: [0.0, 0.52, 1.0]
    )!
    ctx.drawRadialGradient(
        ambientHalo,
        startCenter: CGPoint(x: 512, y: 504),
        startRadius: 40,
        endCenter: CGPoint(x: 512, y: 504),
        endRadius: 440,
        options: []
    )

    // Restrained Liquid Glass top specular edge on macOS squircle
    if includeRoundedBackgroundMask {
        addSquirclePath(to: ctx, rect: bgRect.insetBy(dx: 3, dy: 3), radius: cornerRadius - 3)
        ctx.setStrokeColor(cgColor(255, 255, 255, 0.14))
        ctx.setLineWidth(6)
        ctx.strokePath()
    }

    // 2. Signature "Pipi Halo" Portrait Machined Chassis (660 x 704 centered)
    let chassisW: CGFloat = 660
    let chassisH: CGFloat = 704
    let chassisRect = CGRect(
        x: 512 - chassisW * 0.5,
        y: 512 - chassisH * 0.5,
        width: chassisW,
        height: chassisH
    )
    let chassisPath = buildPipiChassisPath(in: chassisRect)

    // Grounded soft shadow beneath chassis
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 58, color: cgColor(0, 0, 0, 0.72))
    ctx.addPath(chassisPath)
    ctx.setFillColor(cgColor(26, 31, 38))
    ctx.fillPath()
    ctx.restoreGState()

    // Machined Obsidian Titanium body fill (#2A3038 -> #1A1F26 -> #0E1217)
    ctx.saveGState()
    ctx.addPath(chassisPath)
    ctx.clip()
    let chassisGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(54, 62, 74), cgColor(28, 33, 41), cgColor(14, 18, 23)] as CFArray,
        locations: [0.0, 0.54, 1.0]
    )!
    ctx.drawLinearGradient(
        chassisGrad,
        start: CGPoint(x: 512, y: chassisRect.minY),
        end: CGPoint(x: 512, y: chassisRect.maxY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Subtle upper ceramic/titanium specular sweep
    ctx.setFillColor(cgColor(255, 255, 255, 0.055))
    ctx.fillEllipse(in: CGRect(x: 240, y: 120, width: 544, height: 220))
    ctx.restoreGState()

    // Machined Titanium Rim Bevel (#4A5560 with top catchlight)
    let rimGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(255, 255, 255, 0.34), cgColor(74, 85, 96, 0.90), cgColor(31, 184, 176, 0.52)] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    ctx.saveGState()
    ctx.addPath(chassisPath)
    ctx.setLineWidth(12)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        rimGrad,
        start: CGPoint(x: chassisRect.minX, y: chassisRect.minY),
        end: CGPoint(x: chassisRect.maxX, y: chassisRect.maxY),
        options: []
    )
    ctx.restoreGState()

    // 3. Crown Precision Telemetry Indicator ("Pipi Twin-Pip": sleek machined capsule + subtle halo pip)
    if sizePx >= 48 {
        let sigilY = chassisRect.minY + chassisH * 0.195
        ctx.saveGState()
        let barW: CGFloat = 56
        let barH: CGFloat = 10
        let barRect = CGRect(x: 512 - barW * 0.5, y: sigilY - barH * 0.5, width: barW, height: barH)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barH * 0.5, cornerHeight: barH * 0.5, transform: nil)
        ctx.addPath(barPath)
        ctx.setFillColor(cgColor(74, 85, 96, 0.72))
        ctx.fillPath()
        let pipRect = CGRect(x: 512 - 14, y: sigilY - 4, width: 28, height: 8)
        let pipPath = CGPath(roundedRect: pipRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(pipPath)
        ctx.setFillColor(cgColor(99, 245, 230, 0.92))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 4. Recessed Smoked-Glass Visor Capsule (#081418 + #2E4A4E edge)
    let visorW: CGFloat = chassisW * 0.81
    let visorH: CGFloat = chassisH * 0.37
    let visorRect = CGRect(
        x: 512 - visorW * 0.5,
        y: 512 - visorH * 0.45,
        width: visorW,
        height: visorH
    )
    let visorPath = CGPath(roundedRect: visorRect, cornerWidth: visorH * 0.5, cornerHeight: visorH * 0.5, transform: nil)

    ctx.saveGState()
    ctx.addPath(visorPath)
    ctx.clip()
    let visorGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(12, 26, 32), cgColor(8, 20, 24), cgColor(5, 13, 17)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        visorGrad,
        start: CGPoint(x: 512, y: visorRect.minY),
        end: CGPoint(x: 512, y: visorRect.maxY),
        options: []
    )

    // Subtle top specular hairline on glass visor
    ctx.setStrokeColor(cgColor(255, 255, 255, 0.24))
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: visorRect.minX + visorH * 0.48, y: visorRect.minY + 14))
    ctx.addLine(to: CGPoint(x: visorRect.maxX - visorH * 0.48, y: visorRect.minY + 14))
    ctx.strokePath()
    ctx.restoreGState()

    // Visor machined edge rim
    ctx.addPath(visorPath)
    ctx.setStrokeColor(cgColor(46, 74, 78, 0.95))
    ctx.setLineWidth(8)
    ctx.strokePath()

    // 5. Twin Luminous Precision Optical Lenses (#1FB8B0 ring / #63F5E6 iris / #D8FFFB core)
    let lensOffset: CGFloat = chassisW * 0.205
    let lensW: CGFloat = chassisW * 0.215
    let lensH: CGFloat = chassisW * 0.255
    let lensY = visorRect.midY
    let lensPositions = [CGPoint(x: 512 - lensOffset, y: lensY), CGPoint(x: 512 + lensOffset, y: lensY)]

    for center in lensPositions {
        let rx = lensW * 0.5
        let ry = lensH * 0.5
        // Soft optical bloom inside smoked glass
        let aura = CGGradient(
            colorsSpace: colorSpace,
            colors: [cgColor(99, 245, 230, 0.40), cgColor(31, 184, 176, 0.12), cgColor(8, 20, 24, 0.0)] as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        ctx.drawRadialGradient(
            aura,
            startCenter: center,
            startRadius: rx * 0.3,
            endCenter: center,
            endRadius: ry * 1.65,
            options: []
        )

        let lensRect = CGRect(x: center.x - rx, y: center.y - ry, width: lensW, height: lensH)
        let lensPath = CGPath(roundedRect: lensRect, cornerWidth: rx * 0.92, cornerHeight: rx * 0.92, transform: nil)
        let lensGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [cgColor(216, 255, 251), cgColor(99, 245, 230), cgColor(26, 176, 172)] as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        ctx.saveGState()
        ctx.addPath(lensPath)
        ctx.clip()
        ctx.drawLinearGradient(
            lensGrad,
            start: CGPoint(x: center.x, y: lensRect.minY),
            end: CGPoint(x: center.x, y: lensRect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()

        // Outer crisp cyan bezel ring
        ctx.addPath(lensPath)
        ctx.setStrokeColor(cgColor(216, 255, 251, 0.55))
        ctx.setLineWidth(5)
        ctx.strokePath()

        // Bright optical specular glint
        if sizePx >= 32 {
            let glintD = lensW * 0.21
            let glintRect = CGRect(
                x: center.x - rx * 0.42 - glintD * 0.5,
                y: center.y - ry * 0.44 - glintD * 0.5,
                width: glintD,
                height: glintD
            )
            ctx.setFillColor(cgColor(255, 255, 255, 0.94))
            ctx.fillEllipse(in: glintRect)
        }
    }

    // 6. Subtle Machined Chin Micro-Vent (precision hardware detail, not a cartoon mouth)
    if sizePx >= 48 {
        let slitW: CGFloat = 76
        let slitH: CGFloat = 9
        let slitRect = CGRect(
            x: 512 - slitW * 0.5,
            y: visorRect.maxY + (chassisRect.maxY - visorRect.maxY) * 0.42,
            width: slitW,
            height: slitH
        )
        let slitPath = CGPath(roundedRect: slitRect, cornerWidth: slitH * 0.5, cornerHeight: slitH * 0.5, transform: nil)
        ctx.addPath(slitPath)
        ctx.setFillColor(cgColor(148, 163, 184, 0.36))
        ctx.fillPath()
    }

    ctx.restoreGState()
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePng(_ rep: NSBitmapImageRep, to path: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PipiIconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: path, options: .atomic)
}

let scriptUrl = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptUrl.deletingLastPathComponent().deletingLastPathComponent()
let fm = FileManager.default

// 1. macOS AppIcon.iconset -> AppIcon.icns
let iconsetDir = repoRoot.appendingPathComponent("assets/icons/AppIcon.iconset", isDirectory: true)
let icnsPath = repoRoot.appendingPathComponent("assets/icons/AppIcon.icns", isDirectory: false)
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let macSpecs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, px) in macSpecs {
    let rep = renderPipiBotIcon(sizePx: px, includeRoundedBackgroundMask: true)
    try savePng(rep, to: iconsetDir.appendingPathComponent(filename))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("Error: iconutil failed with status \(iconutil.terminationStatus)\n", stderr)
    exit(1)
}
try? fm.removeItem(at: iconsetDir)
print("Generated macOS icon: \(icnsPath.path)")

// 2. iOS AppIcon PNGs
let iosDir = repoRoot.appendingPathComponent("assets/icons/ios", isDirectory: true)
let iosSpecs: [(String, Int)] = [
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76@2x~ipad.png", 152),
    ("AppIcon83.5x83.5@2x~ipad.png", 167),
    ("AppIcon1024.png", 1024),
]

for (filename, px) in iosSpecs {
    let rep = renderPipiBotIcon(sizePx: px, includeRoundedBackgroundMask: false)
    try savePng(rep, to: iosDir.appendingPathComponent(filename))
    print("Generated iOS icon: \(iosDir.appendingPathComponent(filename).path)")
}

// 3. PWA Icons
let pwaDir = repoRoot.appendingPathComponent("apps/ios-web/icons", isDirectory: true)
let pwaSpecs: [(String, Int, Bool)] = [
    ("icon-192.png", 192, true),
    ("icon-512.png", 512, true),
    ("apple-touch-icon.png", 180, false),
]

for (filename, px, rounded) in pwaSpecs {
    let rep = renderPipiBotIcon(sizePx: px, includeRoundedBackgroundMask: rounded)
    try savePng(rep, to: pwaDir.appendingPathComponent(filename))
    print("Generated PWA icon: \(pwaDir.appendingPathComponent(filename).path)")
}
