import AppKit
import CoreGraphics

/// Tiles frames into a grid with a label under each (e.g. clock times).
enum ContactSheet {
    static func make(frames: [CGImage], labels: [String], columns: Int, gap: Int = 16, labelHeight: Int = 40) throws -> CGImage {
        guard let first = frames.first else { throw FrameRenderer.Error.imageCreationFailed }
        let w = first.width, h = first.height
        let rows = (frames.count + columns - 1) / columns
        let width = columns * w + (columns + 1) * gap
        let height = rows * (h + labelHeight) + (rows + 1) * gap
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw FrameRenderer.Error.imageCreationFailed
        }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor(white: 0.85, alpha: 1),
        ]
        for (i, frame) in frames.enumerated() {
            let col = i % columns, row = i / columns
            let x = gap + col * (w + gap)
            // CG origin is bottom-left: row 0 at the top.
            let yTop = height - gap - row * (h + labelHeight + gap)
            ctx.draw(frame, in: CGRect(x: x, y: yTop - h, width: w, height: h))
            if i < labels.count {
                NSAttributedString(string: labels[i], attributes: attrs)
                    .draw(at: NSPoint(x: x, y: yTop - h - labelHeight + 8))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { throw FrameRenderer.Error.imageCreationFailed }
        return image
    }
}
