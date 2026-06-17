import SwiftUI

struct IslandShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var bottomEdgeDrop: CGFloat = 0
    var baseHeight: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(topCornerRadius, bottomCornerRadius),
                AnimatablePair(bottomEdgeDrop, baseHeight)
            )
        }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            bottomEdgeDrop = newValue.second.first
            baseHeight = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let resolvedBaseHeight = baseHeight > 0 ? min(baseHeight, rect.height) : rect.height
        let top = min(topCornerRadius, rect.width / 4, resolvedBaseHeight / 2)
        let bottom = min(bottomCornerRadius, rect.width / 4, resolvedBaseHeight / 2)
        let restBottomY = rect.minY + resolvedBaseHeight
        let bottomY = restBottomY + max(0, bottomEdgeDrop)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.minY + top),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: bottomY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top - bottom, y: bottomY),
            control: CGPoint(x: rect.maxX - top, y: bottomY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top + bottom, y: bottomY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: bottomY - bottom),
            control: CGPoint(x: rect.minX + top, y: bottomY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
