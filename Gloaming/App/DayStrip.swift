import SwiftUI
import WallpaperCore

/// Six frames of what a Dynamic (time-of-day) export of the current look shows through the
/// day. Rendered with the exporter's own scenes; refreshed 200 ms after edits settle.
struct DayStrip: View {
    let model: EditorModel
    /// The export target's aspect ratio, so frames match what the export shows.
    let aspect: Double
    private let images = State<[CGImage]>(initialValue: [])
    private static let hours = [0, 4, 8, 12, 16, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(Self.hours.enumerated()), id: \.offset) { index, hour in
                    VStack(spacing: 2) {
                        Group {
                            if index < images.wrappedValue.count {
                                Image(decorative: images.wrappedValue[index], scale: 2).resizable()
                            } else {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .aspectRatio(aspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        Text(String(format: "%02d", hour))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: TaskKey(look: model.look, aspect: aspect)) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            images.wrappedValue = Self.hours.compactMap {
                model.thumbnails.image(for: model.look, dayFraction: Double($0) / 24,
                                       size: ThumbnailRenderer.size(aspect: aspect))
            }
        }
        .accessibilityLabel("Preview of the wallpaper through the day")
    }
}

private struct TaskKey: Equatable { var look: Look; var aspect: Double }
