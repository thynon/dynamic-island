import SwiftUI
import IslandCore

struct AudioWaveformView: View {
    let snapshot: AudioPlaybackSnapshot
    let phaseOffset: TimeInterval

    init(snapshot: AudioPlaybackSnapshot = .idle, phaseOffset: TimeInterval = 0) {
        self.snapshot = snapshot
        self.phaseOffset = phaseOffset
    }

    var body: some View {
        Group {
            switch snapshot.presentationMode {
            case .audioLevels where snapshot.isWaveformActive:
                audioLevelsWaveform
            default:
                staticWaveform
            }
        }
        .accessibilityHidden(true)
    }

    private var staticWaveform: some View {
        waveformCanvas(
            levels: [0],
            dynamicPhase: 0,
            traceOpacity: 0.30,
            addsShimmer: false
        )
    }

    private var audioLevelsWaveform: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            waveformCanvas(
                levels: snapshot.levels,
                dynamicPhase: timeline.date.timeIntervalSinceReferenceDate + phaseOffset,
                traceOpacity: 0.82,
                addsShimmer: true
            )
        }
    }

    private func waveformCanvas(
        levels: [Double],
        dynamicPhase: TimeInterval,
        traceOpacity: Double,
        addsShimmer: Bool
    ) -> some View {
        Canvas { canvas, size in
            let baseline = size.height * 0.52
            let insetX: CGFloat = 1.5
            let usableWidth = max(1, size.width - (insetX * 2))

            var basePath = Path()
            basePath.move(to: CGPoint(x: insetX, y: baseline))
            basePath.addLine(to: CGPoint(x: size.width - insetX, y: baseline))
            canvas.stroke(
                basePath,
                with: .color(Color.white.opacity(0.34)),
                lineWidth: 0.68
            )

            let samples = levels.isEmpty ? [0.0] : levels
            let pointCount = max(16, samples.count * 4)
            var trace = Path()

            for index in 0..<pointCount {
                let progress = CGFloat(index) / CGFloat(max(1, pointCount - 1))
                let x = insetX + (usableWidth * progress)
                let sample = sampleLevel(
                    at: progress,
                    from: samples,
                    phase: dynamicPhase,
                    addsShimmer: addsShimmer
                )
                let y = baseline - (sample * max(4, size.height * 0.40))

                if index == 0 {
                    trace.move(to: CGPoint(x: x, y: y))
                } else {
                    trace.addLine(to: CGPoint(x: x, y: y))
                }
            }

            canvas.stroke(
                trace,
                with: .color(Color.white.opacity(traceOpacity)),
                style: StrokeStyle(lineWidth: 0.88, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sampleLevel(
        at progress: CGFloat,
        from levels: [Double],
        phase: TimeInterval,
        addsShimmer: Bool
    ) -> CGFloat {
        guard !levels.isEmpty else { return 0 }
        if levels.count == 1 {
            return CGFloat(levels[0])
        }

        let scaled = progress * CGFloat(levels.count - 1)
        let leftIndex = Int(floor(scaled))
        let rightIndex = min(levels.count - 1, leftIndex + 1)
        let t = scaled - CGFloat(leftIndex)
        let left = CGFloat(levels[leftIndex])
        let right = CGFloat(levels[rightIndex])
        let interpolated = left + ((right - left) * t)
        guard addsShimmer else {
            return max(-1, min(1, interpolated))
        }

        let travel = CGFloat(phase.truncatingRemainder(dividingBy: 8.0) / 8.0)
        let waveA = sin((Double(progress + travel) * 12.0) + phase * 2.4) * 0.055
        let waveB = sin((Double(progress) * 31.0) - phase * 3.8) * 0.018
        let shimmer = waveA + waveB

        return max(-1, min(1, interpolated + CGFloat(shimmer)))
    }
}
