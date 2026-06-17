import AppKit
import SwiftUI
import DynamicIslandCore

struct ClosedMusicWaveformView: NSViewRepresentable {
    let snapshot: AudioPlaybackSnapshot

    func makeNSView(context: Context) -> WaveformBarsView {
        WaveformBarsView()
    }

    func updateNSView(_ nsView: WaveformBarsView, context: Context) {
        nsView.update(levels: snapshot.levels)
    }
}

final class WaveformBarsView: NSView {
    private let barCount = 5
    private let bars: [CALayer]

    override init(frame frameRect: NSRect) {
        bars = (0..<barCount).map { _ in
            let layer = CALayer()
            layer.backgroundColor = NSColor.black.cgColor
            layer.cornerRadius = 1.1
            return layer
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        bars.forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layoutBars()
    }

    func update(levels: [Double]) {
        for index in bars.indices {
            let scale = scale(for: index, levels: levels)
            animate(bar: bars[index], index: index, scale: scale)
        }
        layoutBars()
    }

    private func layoutBars() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let spacing: CGFloat = max(0.8, bounds.width * 0.07)
        let barWidth: CGFloat = max(1.2, (bounds.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
        let barHeight: CGFloat = min(14, bounds.height)
        let startX = (bounds.width - ((barWidth * CGFloat(barCount)) + spacing * CGFloat(barCount - 1))) / 2
        let centerY = bounds.midY

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.frame = CGRect(
                x: startX + CGFloat(index) * (barWidth + spacing),
                y: centerY - (barHeight / 2),
                width: barWidth,
                height: barHeight
            )
            bar.cornerRadius = barWidth / 2
        }
        CATransaction.commit()
    }

    private func animate(bar: CALayer, index: Int, scale: CGFloat) {
        guard bar.animation(forKey: "waveform-scale") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = max(0.28, scale * 0.72)
        animation.toValue = min(1, max(0.42, scale))
        animation.duration = 0.68 + (Double(index) * 0.05)
        animation.beginTime = CACurrentMediaTime() + (Double(index) * 0.08)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bar.add(animation, forKey: "waveform-scale")
    }

    private func scale(for index: Int, levels: [Double]) -> CGFloat {
        let fallback: [CGFloat] = [0.78, 0.42, 0.88, 0.52, 0.82]
        guard !levels.isEmpty else { return fallback[index % fallback.count] }
        return max(0.28, min(1, CGFloat(abs(levels[(index * 2) % levels.count]))))
    }
}
