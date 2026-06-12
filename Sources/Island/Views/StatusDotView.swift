import AppKit
import QuartzCore
import SwiftUI
import IslandCore

struct StatusDotView: NSViewRepresentable {
    let activity: TaskActivityState
    let haloDiameter: CGFloat
    let style: StatusDotSoftGlowStyle

    init(
        activity: TaskActivityState,
        haloDiameter: CGFloat,
        style: StatusDotSoftGlowStyle? = nil
    ) {
        self.activity = activity
        self.haloDiameter = haloDiameter
        self.style = style ?? .previousSoftGlow(haloDiameter: haloDiameter)
    }

    func makeNSView(context: Context) -> StatusDotLayerView {
        let view = StatusDotLayerView()
        view.update(activity: activity, haloDiameter: haloDiameter, style: style)
        return view
    }

    func updateNSView(_ nsView: StatusDotLayerView, context: Context) {
        nsView.update(activity: activity, haloDiameter: haloDiameter, style: style)
    }
}

@MainActor
final class StatusDotLayerView: NSView {
    private let glowLayer = CAGradientLayer()
    private let rimLayer = CAShapeLayer()
    private var currentActivity: TaskActivityState?
    private var currentHaloDiameter: CGFloat = 0
    private var currentStyle: StatusDotSoftGlowStyle?
    private var currentProfile: StatusDotBreathingProfile?

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: currentHaloDiameter, height: currentHaloDiameter)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    func update(
        activity: TaskActivityState,
        haloDiameter: CGFloat,
        style: StatusDotSoftGlowStyle
    ) {
        let sanitizedDiameter = max(1, haloDiameter.rounded())
        let needsAnimationUpdate = currentActivity != activity
            || currentProfile != activity.breathingProfile
            || currentStyle != style
            || abs(currentHaloDiameter - sanitizedDiameter) > 0.25

        currentActivity = activity
        currentHaloDiameter = sanitizedDiameter
        currentStyle = style
        currentProfile = activity.breathingProfile
        setAccessibilityLabel(activity.accessibilityLabel)
        invalidateIntrinsicContentSize()
        updateLayerAppearance()
        updateLayerGeometry()

        if needsAnimationUpdate {
            applyAnimation(for: activity)
        }
    }

    private func configureLayers() {
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = true
        layer = rootLayer

        glowLayer.type = .radial
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        glowLayer.locations = [0, 0.36, 0.72, 1]
        glowLayer.drawsAsynchronously = true
        glowLayer.shouldRasterize = true
        rootLayer.addSublayer(glowLayer)

        rimLayer.fillColor = NSColor.clear.cgColor
        rimLayer.lineCap = .round
        rimLayer.lineJoin = .round
        rimLayer.shouldRasterize = true
        rootLayer.addSublayer(rimLayer)
    }

    private func updateLayerAppearance() {
        guard let activity = currentActivity else { return }
        let color = activity.nsColor
        let accent = activity.accentNSColor
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.withDisabledActions {
            glowLayer.rasterizationScale = backingScale
            rimLayer.rasterizationScale = backingScale
            glowLayer.colors = [
                color.withAlphaComponent(0.96).cgColor,
                color.withAlphaComponent(0.58).cgColor,
                color.withAlphaComponent(0.20).cgColor,
                color.withAlphaComponent(0.0).cgColor
            ]
            rimLayer.strokeColor = accent.withAlphaComponent(activity.statusDotAnimationKind == .fastPulse ? 0.72 : 0.46).cgColor
            rimLayer.shadowColor = color.cgColor
            rimLayer.shadowOpacity = activity.statusDotAnimationKind == .fastPulse ? 0.42 : 0.24
        }
    }

    private func updateLayerGeometry() {
        guard let rootLayer = layer, let style = currentStyle else { return }
        let diameter = max(1, min(bounds.width, bounds.height, currentHaloDiameter))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let sourceDiameter = min(diameter, max(1, style.outerSourceDiameter))
        let rimDiameter = min(diameter - 0.5, max(1, style.ringDiameter))
        let rimRect = CGRect(
            x: center.x - (rimDiameter / 2),
            y: center.y - (rimDiameter / 2),
            width: rimDiameter,
            height: rimDiameter
        )

        CATransaction.withDisabledActions {
            rootLayer.cornerRadius = diameter / 2

            glowLayer.bounds = CGRect(x: 0, y: 0, width: sourceDiameter, height: sourceDiameter)
            glowLayer.position = center
            glowLayer.cornerRadius = sourceDiameter / 2

            rimLayer.frame = bounds
            rimLayer.path = CGPath(ellipseIn: rimRect, transform: nil)
            rimLayer.lineWidth = min(style.ringLineWidth, max(0.35, rimDiameter * 0.11))
            rimLayer.shadowRadius = max(0.35, style.ringBlurRadius * 0.65)
            rimLayer.shadowOffset = .zero
        }
    }

    private func applyAnimation(for activity: TaskActivityState) {
        let profile = activity.breathingProfile
        glowLayer.removeAllAnimations()
        rimLayer.removeAllAnimations()

        guard profile.isActive else {
            CATransaction.withDisabledActions {
                glowLayer.isHidden = true
                rimLayer.isHidden = true
                glowLayer.opacity = 0
                rimLayer.opacity = 0
                glowLayer.transform = CATransform3DIdentity
                rimLayer.transform = CATransform3DIdentity
            }
            return
        }

        CATransaction.withDisabledActions {
            glowLayer.isHidden = false
            rimLayer.isHidden = false
            glowLayer.opacity = Float(profile.minOpacity)
            rimLayer.opacity = Float(profile.minOpacity)
            glowLayer.transform = CATransform3DMakeScale(profile.minScale, profile.minScale, 1)
            rimLayer.transform = CATransform3DMakeScale(profile.minScale, profile.minScale, 1)
        }

        let cycleDuration = max(0.2, profile.duration * 2)
        let opacityValues = [
            NSNumber(value: profile.minOpacity),
            NSNumber(value: profile.maxOpacity),
            NSNumber(value: profile.minOpacity)
        ]
        let rimOpacityValues = [
            NSNumber(value: profile.minOpacity),
            NSNumber(value: profile.maxOpacity * 0.78),
            NSNumber(value: profile.minOpacity)
        ]

        glowLayer.add(
            makeKeyframeAnimation(
                keyPath: "opacity",
                values: opacityValues,
                duration: cycleDuration
            ),
            forKey: AnimationKey.opacity
        )
        rimLayer.add(
            makeKeyframeAnimation(
                keyPath: "opacity",
                values: rimOpacityValues,
                duration: cycleDuration
            ),
            forKey: AnimationKey.opacity
        )

        guard profile.minScale != profile.maxScale else { return }
        let scaleValues = [
            NSNumber(value: Double(profile.minScale)),
            NSNumber(value: Double(profile.maxScale)),
            NSNumber(value: Double(profile.minScale))
        ]
        glowLayer.add(
            makeKeyframeAnimation(
                keyPath: "transform.scale",
                values: scaleValues,
                duration: cycleDuration
            ),
            forKey: AnimationKey.scale
        )
        rimLayer.add(
            makeKeyframeAnimation(
                keyPath: "transform.scale",
                values: scaleValues,
                duration: cycleDuration
            ),
            forKey: AnimationKey.scale
        )
    }

    private func makeKeyframeAnimation(
        keyPath: String,
        values: [NSNumber],
        duration: CFTimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = [0, 0.5, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}

private enum AnimationKey {
    static let opacity = "statusDotOpacity"
    static let scale = "statusDotScale"
}

private extension CATransaction {
    static func withDisabledActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}

private extension TaskActivityState {
    var nsColor: NSColor {
        switch self {
        case .idle, .thinking, .running, .compacting:
            return NSColor(displayP3Red: 0.08, green: 1.0, blue: 0.34, alpha: 1.0)
        case .warning:
            return NSColor(displayP3Red: 1.0, green: 0.82, blue: 0.02, alpha: 1.0)
        case .error:
            return NSColor(displayP3Red: 1.0, green: 0.08, blue: 0.06, alpha: 1.0)
        }
    }

    var accentNSColor: NSColor {
        switch self {
        case .idle, .thinking, .running, .compacting:
            return NSColor(displayP3Red: 0.38, green: 1.0, blue: 0.54, alpha: 1.0)
        case .warning:
            return NSColor(displayP3Red: 1.0, green: 0.94, blue: 0.16, alpha: 1.0)
        case .error:
            return NSColor(displayP3Red: 1.0, green: 0.34, blue: 0.28, alpha: 1.0)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle:
            return "Idle"
        case .thinking:
            return "Thinking"
        case .running:
            return "Running"
        case .compacting:
            return "Compacting"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }
}
