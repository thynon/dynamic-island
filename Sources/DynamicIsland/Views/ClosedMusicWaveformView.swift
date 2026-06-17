import SwiftUI
import DynamicIslandCore

struct ClosedMusicWaveformView: View {
    let snapshot: AudioPlaybackSnapshot

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let bars = 5
                let spacing = max(0.8, size.width * 0.07)
                let width = max(1.2, (size.width - spacing * CGFloat(bars - 1)) / CGFloat(bars))
                let centerY = size.height / 2

                for index in 0..<bars {
                    let height = barHeight(index: index, date: timeline.date, maxHeight: size.height)
                    let x = CGFloat(index) * (width + spacing)
                    let rect = CGRect(
                        x: x,
                        y: centerY - (height / 2),
                        width: width,
                        height: height
                    )
                    let path = Path(roundedRect: rect, cornerRadius: width / 2)
                    context.fill(path, with: .color(.black))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(index: Int, date: Date, maxHeight: CGFloat) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate * 5.2 + Double(index) * 0.82
        let fallback = 0.48 + (sin(phase) * 0.30)
        let levels = snapshot.levels
        let sample = levels.isEmpty
            ? fallback
            : (abs(levels[(index * 2) % levels.count]) * 0.72) + (fallback * 0.28)
        return max(3, min(maxHeight, 3 + CGFloat(sample) * max(1, maxHeight - 3)))
    }
}
