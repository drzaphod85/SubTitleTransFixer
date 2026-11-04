import AppKit
import AVFoundation
import AVKit

/// Creates the AppKit video view (AVPlayerView, as in QuickTime Player).
///
/// This file deliberately does NOT import SwiftUI: importing AVKit and SwiftUI in
/// the same file pulls in the `_AVKit_SwiftUI` overlay, whose `VideoPlayer`
/// crashes at launch of the view (getSuperclassMetadata) when the app is built
/// with Swift Package Manager. The SwiftUI side only sees a plain NSView.
enum PlayerSurface {
    static func makeView(player: AVPlayer) -> NSView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        return view
    }

    static func update(_ view: NSView, player: AVPlayer) {
        guard let view = view as? AVPlayerView, view.player !== player else { return }
        view.player = player
    }
}
