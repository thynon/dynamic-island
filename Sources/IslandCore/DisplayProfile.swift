import CoreGraphics
import Foundation

public struct DisplaySignature: Codable, Equatable, Sendable {
    public let frameWidth: Double
    public let frameHeight: Double
    public let safeAreaTopInset: Double
    public let auxiliaryTopLeftWidth: Double?
    public let auxiliaryTopRightWidth: Double?
    public let backingScaleFactor: Double

    public init(
        frameWidth: Double,
        frameHeight: Double,
        safeAreaTopInset: Double,
        auxiliaryTopLeftWidth: Double?,
        auxiliaryTopRightWidth: Double?,
        backingScaleFactor: Double
    ) {
        self.frameWidth = frameWidth.rounded()
        self.frameHeight = frameHeight.rounded()
        self.safeAreaTopInset = safeAreaTopInset.rounded()
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth?.rounded()
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth?.rounded()
        self.backingScaleFactor = backingScaleFactor
    }
}

public enum DisplayProfileKind: String, Codable, Equatable, Sendable {
    case notchedCompact
    case notchedLarge
    case standardDisplay
}

public struct DisplayProfile: Codable, Equatable, Sendable {
    public let signature: DisplaySignature
    public let measuredAt: Date
    public let displayKind: DisplayProfileKind
    public let cameraHousingWidth: Double
    public let closedHeight: Double
    public let closedShellWidth: Double
    public let openWidth: Double
    public let openHeight: Double

    public var metrics: NotchMetrics {
        NotchMetrics(
            cameraHousingWidth: CGFloat(cameraHousingWidth),
            closedHeight: CGFloat(closedHeight),
            openWidth: CGFloat(openWidth),
            openHeight: CGFloat(openHeight)
        )
    }

    public init(signature: DisplaySignature, measuredAt: Date = Date()) {
        let metrics = NotchMetrics.fromDisplay(
            frameWidth: CGFloat(signature.frameWidth),
            frameHeight: CGFloat(signature.frameHeight),
            auxiliaryTopLeftWidth: signature.auxiliaryTopLeftWidth.map { CGFloat($0) },
            auxiliaryTopRightWidth: signature.auxiliaryTopRightWidth.map { CGFloat($0) },
            safeAreaTopInset: CGFloat(signature.safeAreaTopInset)
        )

        self.signature = signature
        self.measuredAt = measuredAt
        self.displayKind = Self.kind(for: signature)
        self.cameraHousingWidth = Double(metrics.cameraHousingWidth)
        self.closedHeight = Double(metrics.closedHeight)
        self.closedShellWidth = Double(metrics.closedShellWidth)
        self.openWidth = Double(metrics.openWidth)
        self.openHeight = Double(metrics.openHeight)
    }

    public func matches(_ signature: DisplaySignature) -> Bool {
        self.signature == signature
    }

    private static func kind(for signature: DisplaySignature) -> DisplayProfileKind {
        let hasCameraHousing = signature.safeAreaTopInset > 0
            && signature.auxiliaryTopLeftWidth != nil
            && signature.auxiliaryTopRightWidth != nil

        guard hasCameraHousing else {
            return .standardDisplay
        }

        return signature.frameWidth > Double(NotchMetrics.compactNotchedReferenceWidth)
            ? .notchedLarge
            : .notchedCompact
    }
}
