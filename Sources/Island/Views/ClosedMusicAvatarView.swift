import AppKit
import SwiftUI

struct ClosedMusicAvatarView: View {
    let artworkData: Data?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 7.5) / 7.5 * 360

            ZStack {
                if let artworkImage {
                    Image(nsImage: artworkImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    fallbackDisc
                }

                Circle()
                    .stroke(Color.black.opacity(0.22), lineWidth: 0.8)
            }
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 0)
        }
        .accessibilityHidden(true)
    }

    private var artworkImage: NSImage? {
        artworkData.flatMap(NSImage.init(data:))
    }

    private var fallbackDisc: some View {
        ZStack {
            Circle()
                .fill(Color.black)
            Circle()
                .fill(Color.white)
                .frame(width: 4.2, height: 4.2)
        }
    }
}
