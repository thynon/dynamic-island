import AppKit
import SwiftUI

struct ClosedMusicAvatarView: View {
    let artworkData: Data?

    var body: some View {
        let cornerRadius: CGFloat = 4

        Group {
            if let artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackDisc
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var artworkImage: NSImage? {
        artworkData.flatMap(NSImage.init(data:))
    }

    private var fallbackDisc: some View {
        GeometryReader { proxy in
            let dot = min(proxy.size.width, proxy.size.height) * 0.35
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                Circle()
                    .fill(Color.black)
                    .frame(width: dot, height: dot)
            }
        }
    }
}
