import CoreGraphics
import Foundation

struct DebugMusicSignal: Equatable, Sendable {
    let isPlaying: Bool
    let title: String
    let artist: String
    let feedbackDirection: MusicSkipDirection?
    let progress: CGFloat

    var clampedProgress: CGFloat {
        min(1, max(0, progress))
    }

    static func read(from url: URL) -> DebugMusicSignal? {
        guard
            let data = try? Data(contentsOf: url),
            !data.isEmpty,
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }

        return DebugMusicSignal(
            isPlaying: payload.isPlaying,
            title: payload.title ?? "Debug Track",
            artist: payload.artist ?? "Signal Preview",
            feedbackDirection: payload.direction.flatMap(MusicSkipDirection.init(debugRawValue:)),
            progress: CGFloat(payload.progress ?? 0)
        )
    }

    private struct Payload: Decodable {
        let isPlaying: Bool
        let title: String?
        let artist: String?
        let direction: String?
        let progress: Double?
    }
}

private extension MusicSkipDirection {
    init?(debugRawValue: String) {
        switch debugRawValue.lowercased() {
        case "previous":
            self = .previous
        case "next":
            self = .next
        default:
            return nil
        }
    }
}
