import AVFoundation
import SwiftUI
// No `import AVKit` here – see PlayerSurface.swift for why.

/// The video that belongs to the reviewed file: shown under the review header.
struct MediaRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let review = model.review
        let media = review.media
        HStack(spacing: 8) {
            Image(systemName: "film").foregroundStyle(media.hasVideo ? Color.accentColor : Color.secondary)
            if let video = media.videoURL {
                Text(L("Video:")).foregroundStyle(.secondary)
                Text(video.lastPathComponent).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                if media.needsFFmpeg {
                    Label(L("Needs ffmpeg to play .{0} – install it with: brew install ffmpeg", video.pathExtension),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else if review.isCheckingAudio {
                    ProgressView().controlSize(.small)
                    Text(L("Analysing the audio…")).foregroundStyle(.secondary)
                } else {
                    Button(L("Check timecodes against the audio")) { review.checkTimingAgainstAudio() }
                        .buttonStyle(.link)
                        .help(L("Suggests new times where the speech seems to start or end at another time than the subtitle"))
                }
                Button(L("Change…")) { review.chooseVideoPanel() }.buttonStyle(.link)
                Button(L("Remove")) { review.clearVideo() }.buttonStyle(.link)
            } else {
                Text(L("No video found next to the file – with a video you can play every subtitle and fix its timing."))
                    .foregroundStyle(.secondary)
                Button(L("Choose video…")) { review.chooseVideoPanel() }.buttonStyle(.link)
            }
            Spacer()
        }
        .font(.callout)
    }
}

/// Plays a subtitle from 5 seconds before to 5 seconds after, with a loudness
/// curve, and lets the user adjust its start and end time.
struct MediaPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let seq: Int

    @State private var player = ClipPlayer()
    @State private var loading = true
    @State private var errorText: String?
    @State private var info: String?
    @State private var envelope: [Float] = []
    @State private var windowStart: Double = 0
    @State private var windowEnd: Double = 0
    @State private var originalStart: Double = 0
    @State private var originalEnd: Double = 0
    @State private var startDraft: Double = 0
    @State private var endDraft: Double = 0

    private static let margin = 5.0

    private var cue: ReviewCue? { model.review.cues.first { $0.seq == seq } }

    /// Neighbouring subtitles (time span and text) inside the window.
    private var neighbours: [(start: Double, end: Double, text: String)] {
        model.review.cues.compactMap { c -> (start: Double, end: Double, text: String)? in
            guard c.seq != seq, let t = SRT.times(of: c.timecode) else { return nil }
            let s = Double(t.start) / 1000, e = Double(t.end) / 1000
            return e > windowStart && s < windowEnd ? (s, e, c.text) : nil
        }
    }

    private var prevEnd: Double? { neighbours.filter { $0.end <= originalStart + 0.01 }.map(\.end).max() }
    private var nextStart: Double? { neighbours.filter { $0.start >= originalEnd - 0.01 }.map(\.start).min() }

    /// The subtitle text to show over the video at the current time.
    private var overlayText: String? {
        let t = player.currentTime
        if t >= startDraft && t <= endDraft { return cue?.text }
        return neighbours.first { t >= $0.start && t <= $0.end }?.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Subtitle {0}", cue?.number ?? "")).font(.headline)
                Text(verbatim: SRT.format(ms: ms(originalStart)) + " → " + SRT.format(ms: ms(originalEnd)))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: model.review.media.videoURL?.lastPathComponent ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            ZStack {
                PlayerSurfaceView(player: player.player)
                // The subtitle over the picture, above the player's own controls.
                VStack {
                    Spacer()
                    if let text = overlayText {
                        Text(SubtitleChecker.stripTags(text))
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 2)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.bottom, 56)
                    }
                }
                .allowsHitTesting(false)
                if loading {
                    ProgressView(L("Preparing the clip…"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
            .frame(height: 380)
            .background(Color.black)

            WaveformView(envelope: envelope, start: windowStart, end: windowEnd,
                         current: (startDraft, endDraft), original: (originalStart, originalEnd),
                         neighbours: neighbours.map { ($0.start, $0.end) },
                         playhead: player.currentTime) { t in player.seek(to: t) }
                .frame(height: 70)
                .help(L("Click to move the playhead. Blue: the subtitle's new times, grey: neighbouring subtitles."))

            HStack(spacing: 8) {
                Button { player.play(from: windowStart, to: windowEnd) } label: {
                    Label(L("Play ±5 s"), systemImage: "play.fill")
                }
                Button { player.play(from: startDraft, to: endDraft) } label: {
                    Label(L("Play the subtitle"), systemImage: "text.bubble")
                }
                Button { player.togglePause() } label: { Image(systemName: "playpause.fill") }
                    .help(L("Pause / continue"))
                Spacer()
                Text(verbatim: SRT.format(ms: ms(player.currentTime)))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .disabled(loading || errorText != nil)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                timeRow(L("Start"), value: $startDraft)
                timeRow(L("End"), value: $endDraft)
            }
            .disabled(loading || errorText != nil)

            HStack {
                Button { suggestFromAudio() } label: {
                    Label(L("Suggest from the audio"), systemImage: "waveform")
                }
                .disabled(envelope.isEmpty)
                .help(L("Finds where the speech starts and ends near the subtitle. Music and sound effects can fool it – listen before you accept."))
                Button(L("Reset")) { startDraft = originalStart; endDraft = originalEnd; info = nil }
                    .disabled(startDraft == originalStart && endDraft == originalEnd)
                if let info {
                    Text(info).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Use the times")) { applyTimes() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(endDraft <= startDraft || (startDraft == originalStart && endDraft == originalEnd))
            }
        }
        .padding(20)
        .frame(width: 760)
        .task { await load() }
        .onDisappear { player.stop() }
    }

    private func timeRow(_ title: String, value: Binding<Double>) -> some View {
        GridRow {
            Text(title).frame(width: 50, alignment: .leading)
            Button { value.wrappedValue = max(0, value.wrappedValue - 0.1) } label: { Text(verbatim: "−" + formatNumber(0.1)) }
            Text(verbatim: SRT.format(ms: ms(value.wrappedValue)))
                .font(.body.monospacedDigit())
                .frame(width: 110)
            Button { value.wrappedValue += 0.1 } label: { Text(verbatim: "+" + formatNumber(0.1)) }
            Button(L("Set at the playhead")) { value.wrappedValue = player.currentTime }
                .help(L("Uses the current playback position"))
        }
    }

    private func ms(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

    private func load() async {
        guard let cue, let t = SRT.times(of: cue.timecode) else { dismiss(); return }
        originalStart = Double(t.start) / 1000
        originalEnd = Double(t.end) / 1000
        startDraft = originalStart
        endDraft = originalEnd
        windowStart = max(0, originalStart - Self.margin)
        windowEnd = originalEnd + Self.margin
        let media = model.review.media
        do {
            let clip = try await media.clip(from: windowStart, to: windowEnd)
            player.load(url: clip.url, offset: clip.offset)
            loading = false
            player.play(from: windowStart, to: windowEnd)
            envelope = (try? await media.envelope(from: windowStart, to: windowEnd)) ?? []
        } catch {
            loading = false
            errorText = error.localizedDescription
        }
    }

    private func suggestFromAudio() {
        if let s = SpeechTiming.suggest(envelope: envelope, envelopeStart: windowStart,
                                        start: startDraft, end: endDraft, prevEnd: prevEnd, nextStart: nextStart) {
            startDraft = (s.start * 100).rounded() / 100
            endDraft = (s.end * 100).rounded() / 100
            info = L("Suggestion from the audio – play the subtitle to check it.")
        } else {
            info = L("The audio gives no clear answer here.")
        }
    }

    private func applyTimes() {
        if model.review.updateTimecode(seq: seq, start: SRT.format(ms: ms(startDraft)), end: SRT.format(ms: ms(endDraft))) {
            dismiss()
        }
    }
}

/// Loudness curve with the subtitle, its neighbours and the playhead.
struct WaveformView: View {
    let envelope: [Float]
    let start: Double
    let end: Double
    let current: (Double, Double)
    let original: (Double, Double)
    let neighbours: [(Double, Double)]
    let playhead: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let total = max(end - start, 0.1)
                func x(_ t: Double) -> CGFloat { CGFloat((t - start) / total) * size.width }
                func span(_ a: Double, _ b: Double) -> Path {
                    Path(CGRect(x: x(a), y: 0, width: max(x(b) - x(a), 1), height: size.height))
                }
                for n in neighbours {
                    ctx.fill(span(n.0, n.1), with: .color(Color.secondary.opacity(0.18)))
                }
                ctx.stroke(span(original.0, original.1), with: .color(Color.accentColor.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ctx.fill(span(current.0, current.1), with: .color(Color.accentColor.opacity(0.25)))

                if !envelope.isEmpty {
                    let peak = max(envelope.max() ?? 1, 0.0001)
                    let barWidth = size.width * CGFloat(1 / AudioReader.envelopeRate / total)
                    for (i, v) in envelope.enumerated() {
                        let h = CGFloat(v / peak) * size.height * 0.95
                        let bx = x(start + Double(i) / AudioReader.envelopeRate)
                        ctx.fill(Path(CGRect(x: bx, y: (size.height - h) / 2, width: max(barWidth, 1), height: h)),
                                 with: .color(Color.primary.opacity(0.55)))
                    }
                }
                ctx.fill(Path(CGRect(x: x(playhead) - 1, y: 0, width: 2, height: size.height)), with: .color(.red))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let fraction = max(0, min(1, value.location.x / max(geo.size.width, 1)))
                onSeek(start + Double(fraction) * (end - start))
            })
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Hosts the AppKit video view created in PlayerSurface.swift.
private struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        PlayerSurface.makeView(player: player)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        PlayerSurface.update(nsView, player: player)
    }
}
