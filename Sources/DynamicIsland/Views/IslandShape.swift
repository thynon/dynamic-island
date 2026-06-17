import SwiftUI

struct IslandShape: Shape {
    var topCornerRadius: CGFloat
    var concaveTopRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var bottomEdgeDrop: CGFloat = 0
    var baseHeight: CGFloat = 0

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(topCornerRadius, bottomCornerRadius),
                AnimatablePair(concaveTopRadius, AnimatablePair(bottomEdgeDrop, baseHeight))
            )
        }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            concaveTopRadius = newValue.second.first
            bottomEdgeDrop = newValue.second.second.first
            baseHeight = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let resolvedBaseHeight = baseHeight > 0 ? min(baseHeight, rect.height) : rect.height
        let maxRadius = min(rect.width / 4, resolvedBaseHeight)
        let top = min(max(0, topCornerRadius), maxRadius)
        let concaveTop = min(max(0, concaveTopRadius), maxRadius)
        let bottom = min(max(0, bottomCornerRadius), maxRadius)
        let restBottomY = rect.minY + resolvedBaseHeight
        let bottomY = restBottomY + max(0, bottomEdgeDrop)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.minY + concaveTop),
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
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY + concaveTop))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
