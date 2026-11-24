import AppKit
import CoreGraphics
import Foundation
import WallpaperCore

/// `--icon DIR [--icon-variant NAME]`: renders the app icon with the app's own gradient engine.
///
/// Without a variant it writes a review sheet of all variants; with one it also writes the
/// 1024 px master, a complete `.iconset` and `AppIcon.icns` (via `iconutil`).
///
/// Shape: macOS icon grid, an 824 pt continuous-corner squircle centered on a 1024 canvas with
/// a soft drop shadow, so it sits correctly next to system icons.
@MainActor
enum IconCommand {
    struct Variant {
        let name: String
        let render: (RenderContext, Int) throws -> CGImage
    }

    static let variants: [Variant] = [
        Variant(name: "daynight") { ctx, size in try dayNight(ctx, size, night: Preset.seasons[0], day: Preset.vibes[1]) },
        Variant(name: "orb") { ctx, size in try orb(ctx, size, preset: Preset.vibes[1]) },
        Variant(name: "aurora") { ctx, size in try still(ctx, size, preset: Preset.vibes[0], seed: 4, time: 40) },
        Variant(name: "dreamy") { ctx, size in try still(ctx, size, preset: Preset.moods[3], seed: 41, time: 15) },
    ]

    static func run(directory: String, variant: String?, context: RenderContext) throws {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let masters = try variants.map { ($0.name, try makeMaster(context: context, variant: $0)) }
        let sheet = try reviewSheet(masters)
        try write(sheet, to: dir.appendingPathComponent("icon-variants.png"))
        print("wrote \(dir.appendingPathComponent("icon-variants.png").path)")

        guard let variant else { return }
        guard let master = masters.first(where: { $0.0 == variant })?.1 else {
            print("unknown variant '\(variant)' (\(variants.map(\.name).joined(separator: ", ")))")
            return
        }
        try write(master, to: dir.appendingPathComponent("AppIcon-1024.png"))
        let iconset = dir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            try write(resized(master, to: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
            try write(resized(master, to: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
        let icns = dir.appendingPathComponent("AppIcon.icns")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
        try p.run()
        p.waitUntilExit()
        print(p.terminationStatus == 0 ? "wrote \(icns.path)" : "iconutil failed (\(p.terminationStatus))")
    }

    // MARK: - Artwork

    private static func look(_ preset: Preset, seed: UInt32? = nil, time: Double? = nil) -> Look {
        var l = preset.look
        l.parameters.grain = 0            // grain turns to noise at small icon sizes
        l.parameters.complexity = min(l.parameters.complexity, 0.4)
        if let seed { l.seed = seed }
        if let time { l.time = time }
        return l
    }

    private static func still(_ ctx: RenderContext, _ size: Int, preset: Preset, seed: UInt32, time: Double) throws -> CGImage {
        let l = look(preset, seed: seed, time: time)
        return try FrameRenderer(context: ctx, size: ExportSize(width: size, height: size))
            .render(WallpaperExporter(context: ctx).scene(for: l), seed: 1)
    }

    /// A warm gradient with a soft glowing sun in the upper right.
    private static func orb(_ ctx: RenderContext, _ size: Int, preset: Preset) throws -> CGImage {
        let base = try still(ctx, size, preset: preset, seed: 12, time: 30)
        let c = canvas(size)
        let s = CGFloat(size)
        c.draw(base, in: CGRect(x: 0, y: 0, width: s, height: s))
        let center = CGPoint(x: s * 0.66, y: s * 0.68)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let glow = CGGradient(colorsSpace: space,
                              colors: [CGColor(red: 1, green: 0.93, blue: 0.8, alpha: 0.55),
                                       CGColor(red: 1, green: 0.85, blue: 0.7, alpha: 0)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: s * 0.5, options: [])
        let disc = CGGradient(colorsSpace: space,
                              colors: [CGColor(red: 1, green: 0.98, blue: 0.92, alpha: 1),
                                       CGColor(red: 1, green: 0.9, blue: 0.75, alpha: 0.95),
                                       CGColor(red: 1, green: 0.85, blue: 0.7, alpha: 0)] as CFArray,
                              locations: [0, 0.75, 1])!
        c.drawRadialGradient(disc, startCenter: center, startRadius: 0, endCenter: center, endRadius: s * 0.15, options: [])
        return c.makeImage()!
    }

    /// One preset's night in the top-left corner flowing into another's midday in the
    /// bottom-right: "changes through the day".
    private static func dayNight(_ ctx: RenderContext, _ size: Int, night nightPreset: Preset, day dayPreset: Preset) throws -> CGImage {
        let r = try FrameRenderer(context: ctx, size: ExportSize(width: size, height: size))
        let exporter = WallpaperExporter(context: ctx)
        var nightLook = look(nightPreset)
        nightLook.seed = look(dayPreset).seed     // same shapes, so the two halves flow together
        let night = try r.render(exporter.scene(for: nightLook, dayFraction: 0.02), seed: 1)
        let day = try r.render(exporter.scene(for: look(dayPreset), dayFraction: 0.5), seed: 1)
        let c = canvas(size)
        c.draw(day, in: CGRect(x: 0, y: 0, width: size, height: size))
        // Mask the night frame with a soft diagonal ramp.
        guard let maskCtx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw FrameRenderer.Error.imageCreationFailed
        }
        let ramp = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                              colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray,
                              locations: [0, 0.3, 0.85])!
        maskCtx.drawLinearGradient(ramp, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
        let masked = night.masking(maskCtx.makeImage()!)!
        c.draw(masked, in: CGRect(x: 0, y: 0, width: size, height: size))
        return c.makeImage()!
    }

    private static func makeMaster(context: RenderContext, variant: Variant) throws -> CGImage {
        let canvasSize = 1024, body = 824
        let art = try variant.render(context, body)
        let c = canvas(canvasSize)
        let rect = CGRect(x: 100, y: 100, width: body, height: body)
        let shape = squircle(in: rect)

        // Drop shadow under the body.
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
        c.addPath(shape); c.setFillColor(CGColor(gray: 0.1, alpha: 1)); c.fillPath()
        c.restoreGState()

        // Artwork clipped to the squircle.
        c.saveGState()
        c.addPath(shape); c.clip()
        c.draw(art, in: rect)
        // Soft top highlight, like light falling on glass.
        let highlight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray,
                                   locations: [0, 1])!
        c.drawLinearGradient(highlight, start: CGPoint(x: rect.midX, y: rect.maxY),
                             end: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.48), options: [])
        c.restoreGState()

        // Hairline inner edge.
        c.saveGState()
        c.addPath(squircle(in: rect.insetBy(dx: 1.5, dy: 1.5)))
        c.setStrokeColor(CGColor(gray: 1, alpha: 0.14)); c.setLineWidth(3); c.strokePath()
        c.restoreGState()
        return c.makeImage()!
    }

    /// Continuous-corner rounded square (superellipse, n ≈ 5), the shape of macOS app icons.
    private static func squircle(in r: CGRect, n: Double = 5) -> CGPath {
        let path = CGMutablePath()
        let steps = 720
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = r.midX + r.width / 2 * CGFloat(copysign(pow(abs(c), 2 / n), c))
            let y = r.midY + r.height / 2 * CGFloat(copysign(pow(abs(s), 2 / n), s))
            i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Helpers

    private static func canvas(_ size: Int) -> CGContext {
        let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .high
        return c
    }

    private static func resized(_ image: CGImage, to size: Int) -> CGImage {
        let c = canvas(size)
        c.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return c.makeImage()!
    }

    /// Each variant large, plus 128/64/32/16 px to judge how it reads in the Dock and Finder.
    private static func reviewSheet(_ masters: [(String, CGImage)]) throws -> CGImage {
        let cell = 300, small = [128, 64, 32, 16], rowH = cell + 60
        let width = 40 + masters.count * (cell + 40)
        let c = canvas(width)
        _ = c
        let ctx = CGContext(data: nil, width: width, height: rowH + 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 0.93, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: rowH + 200))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .medium),
                                                    .foregroundColor: NSColor(white: 0.2, alpha: 1)]
        for (i, (name, img)) in masters.enumerated() {
            let x = 40 + i * (cell + 40)
            ctx.draw(img, in: CGRect(x: x, y: 200, width: cell, height: cell))
            NSAttributedString(string: name, attributes: attrs).draw(at: NSPoint(x: x + 8, y: 200 + cell + 14))
            var sx = x
            for s in small {
                ctx.draw(resized(img, to: s), in: CGRect(x: sx, y: 40 + (128 - s) / 2, width: s, height: s))
                sx += s + 12
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(d, image, nil)
        guard CGImageDestinationFinalize(d) else { throw CocoaError(.fileWriteUnknown) }
    }
}
