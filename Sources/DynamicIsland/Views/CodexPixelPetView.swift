import SwiftUI
import DynamicIslandCore

struct CodexPixelPetView: View {
    let state: CodexCompanionState

    private enum PixelRole {
        case fur
        case shadow
        case graphite
        case mint
        case blue
    }

    private struct Pixel {
        let x: Int
        let y: Int
        let role: PixelRole
    }

    private let gridSize = 16
    private let pixelScale: CGFloat = 2

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            for pixel in pixels {
                let rect = CGRect(
                    x: CGFloat(pixel.x) * pixelScale,
                    y: CGFloat(pixel.y) * pixelScale,
                    width: pixelScale,
                    height: pixelScale
                )
                context.fill(Path(rect), with: .color(color(for: pixel.role)))
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var pixels: [Pixel] {
        basePixels + statePixels
    }

    private var basePixels: [Pixel] {
        var result: [Pixel] = []
        result += rectanglePixels(x: 3...12, y: 3...9, role: .fur)
        result += rectanglePixels(x: 2...4, y: 1...4, role: .fur)
        result += rectanglePixels(x: 11...13, y: 1...4, role: .fur)
        result += rectanglePixels(x: 5...10, y: 9...13, role: .fur)
        result += rectanglePixels(x: 4...6, y: 13...15, role: .fur)
        result += rectanglePixels(x: 9...11, y: 13...15, role: .fur)
        result += [
            Pixel(x: 3, y: 2, role: .shadow),
            Pixel(x: 12, y: 2, role: .shadow),
            Pixel(x: 3, y: 8, role: .shadow),
            Pixel(x: 4, y: 9, role: .shadow),
            Pixel(x: 5, y: 12, role: .shadow),
            Pixel(x: 10, y: 12, role: .shadow),
            Pixel(x: 5, y: 15, role: .shadow),
            Pixel(x: 10, y: 15, role: .shadow),
            Pixel(x: 5, y: 6, role: .mint),
            Pixel(x: 6, y: 6, role: .mint),
            Pixel(x: 9, y: 6, role: .mint),
            Pixel(x: 10, y: 6, role: .mint),
            Pixel(x: 7, y: 8, role: .graphite),
            Pixel(x: 8, y: 8, role: .graphite),
            Pixel(x: 12, y: 10, role: .fur),
            Pixel(x: 13, y: 10, role: .fur),
            Pixel(x: 14, y: 11, role: .fur),
            Pixel(x: 14, y: 12, role: .fur),
            Pixel(x: 13, y: 13, role: .fur),
            Pixel(x: 12, y: 13, role: .shadow),
        ]
        return result
    }

    private var statePixels: [Pixel] {
        switch state {
        case .idle:
            []
        case .thinking:
            [
                Pixel(x: 13, y: 5, role: .mint),
                Pixel(x: 15, y: 5, role: .mint),
                Pixel(x: 14, y: 7, role: .mint),
            ]
        case .tool:
            rectanglePixels(x: 2...10, y: 10...15, role: .shadow)
                + rectanglePixels(x: 3...9, y: 11...14, role: .graphite)
                + [
                    Pixel(x: 4, y: 12, role: .mint),
                    Pixel(x: 5, y: 13, role: .mint),
                    Pixel(x: 6, y: 13, role: .mint),
                    Pixel(x: 8, y: 13, role: .blue),
                ]
        case .done:
            [
                Pixel(x: 14, y: 1, role: .mint),
                Pixel(x: 13, y: 2, role: .mint),
                Pixel(x: 14, y: 2, role: .mint),
                Pixel(x: 15, y: 2, role: .mint),
                Pixel(x: 14, y: 3, role: .mint),
            ]
        }
    }

    private func rectanglePixels(
        x: ClosedRange<Int>,
        y: ClosedRange<Int>,
        role: PixelRole
    ) -> [Pixel] {
        y.flatMap { row in
            x.map { column in
                Pixel(x: column, y: row, role: role)
            }
        }
    }

    private func color(for role: PixelRole) -> Color {
        switch role {
        case .fur:
            Color(red: 0.93, green: 0.95, blue: 0.96)
        case .shadow:
            Color(red: 0.54, green: 0.59, blue: 0.63)
        case .graphite:
            Color(red: 0.12, green: 0.14, blue: 0.16)
        case .mint:
            Color(red: 0.34, green: 0.92, blue: 0.76)
        case .blue:
            Color(red: 0.28, green: 0.56, blue: 0.98)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:
            "Codex 宠物，空闲"
        case .thinking:
            "Codex 宠物，思考中"
        case .tool:
            "Codex 宠物，正在运行工具"
        case .done:
            "Codex 宠物，已完成"
        }
    }
}
