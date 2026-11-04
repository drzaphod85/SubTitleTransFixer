import AVFoundation
import Foundation
import Observation

enum MediaError: LocalizedError {
    case noVideo, noAudio
    case needsFFmpeg(String)
    case ffmpegFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideo: return L("No video file is selected.")
        case .noAudio: return L("The video file has no audio track that can be read.")
        case .needsFFmpeg(let ext):
            return L("macOS cannot play .{0} files by itself. Install ffmpeg (brew install ffmpeg) and try again.", ext)
        case .ffmpegFailed(let message): return L("ffmpeg failed: {0}", message)
        }
    }
}

/// Finds the video that belongs to a subtitle file.
enum MediaLocator {
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "webm", "wmv", "mpg", "mpeg"]

    /// "Matador - S01E01.sv.srt" → "Matador - S01E01.mkv" (or .mp4 …) in the same folder.
    static func findVideo(for subtitleURL: URL) -> URL? {
        let dir = subtitleURL.deletingLastPathComponent()
        let base = SRT.baseName(subtitleURL.lastPathComponent)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let videos = files.filter { videoExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let exact = videos.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == base }) {
            return exact
        }
        return videos.first { SRT.baseName($0.lastPathComponent) == base }
    }
}

/// Runs ffmpeg, which is needed for formats macOS cannot play itself (e.g. .mkv).
enum FFmpeg {
    static let path: String? = {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static var isAvailable: Bool { path != nil }

    /// Runs ffmpeg and returns what it writes to standard output.
    static func run(_ arguments: [String]) async throws -> Data {
        guard let path else { throw MediaError.needsFFmpeg("mkv") }
        return try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error"] + arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errorData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw MediaError.ffmpegFailed(String(message.suffix(300)))
            }
            return data
        }.value
    }

    static func seconds(_ t: Double) -> String { String(format: "%.3f", max(t, 0)) }
}

/// Reads audio as 8 kHz mono 16-bit PCM and turns it into a loudness envelope.
enum AudioReader {
    static let sampleRate = 8000.0
    /// Loudness values per second in an envelope.
    static let envelopeRate = 50.0

    /// AVFoundation path for files macOS can read itself.
    static func readPCM(url: URL, from: Double?, duration: Double?) async throws -> Data {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw MediaError.noAudio }
        return try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let reader = try AVAssetReader(asset: asset)
            if let from, let duration {
                reader.timeRange = CMTimeRange(start: CMTime(seconds: max(from, 0), preferredTimescale: 1000),
                                               duration: CMTime(seconds: duration, preferredTimescale: 1000))
            }
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: sampleRate,
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? MediaError.noAudio }
            var data = Data()
            while let buffer = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                var chunk = Data(count: length)
                chunk.withUnsafeMutableBytes { raw in
                    if let base = raw.baseAddress {
                        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                    }
                }
                data.append(chunk)
            }
            if reader.status == .failed { throw reader.error ?? MediaError.noAudio }
            return data
        }.value
    }

    /// ffmpeg path for any format.
    static func readPCMWithFFmpeg(url: URL, from: Double?, duration: Double?) async throws -> Data {
        var args: [String] = []
        if let from { args += ["-ss", FFmpeg.seconds(from)] }
        args += ["-i", url.path]
        if let duration { args += ["-t", FFmpeg.seconds(duration)] }
        args += ["-vn", "-sn", "-dn", "-ac", "1", "-ar", "\(Int(sampleRate))", "-f", "s16le", "-"]
        return try await FFmpeg.run(args)
    }

    /// RMS loudness, `envelopeRate` values per second.
    static func envelope(_ pcm: Data) -> [Float] {
        let perValue = Int(sampleRate / AudioReader.envelopeRate)
        let sampleCount = pcm.count / 2
        let n = sampleCount / perValue
        guard n > 0 else { return [] }
        return pcm.withUnsafeBytes { raw -> [Float] in
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                var sum: Float = 0
                for j in 0..<perValue {
                    let v = Float(raw.loadUnaligned(fromByteOffset: (i * perValue + j) * 2, as: Int16.self)) / 32768
                    sum += v * v
                }
                out[i] = (sum / Float(perValue)).squareRoot()
            }
            return out
        }
    }
}

/// Finds where speech starts and ends near a subtitle, from the loudness envelope.
/// It only measures loudness, so music and sound effects can fool it – the result
/// is a suggestion to check by listening.
enum SpeechTiming {
    /// - Parameters:
    ///   - envelope: loudness values; `envelope[0]` is at `envelopeStart` seconds.
    ///   - start, end: the subtitle's current times in seconds.
    ///   - prevEnd, nextStart: neighbouring subtitles, which the result never overlaps.
    static func suggest(envelope: [Float], envelopeStart: Double, start: Double, end: Double,
                        prevEnd: Double?, nextStart: Double?) -> (start: Double, end: Double)? {
        let rate = AudioReader.envelopeRate
        func index(_ t: Double) -> Int { Int(((t - envelopeStart) * rate).rounded()) }
        func time(_ i: Int) -> Double { envelopeStart + Double(i) / rate }

        // Threshold from the surroundings: between the quiet floor and the loud parts.
        let lo = max(0, index(start - 5)), hi = min(envelope.count, index(end + 5))
        guard hi - lo > Int(rate) else { return nil }
        let region = envelope[lo..<hi].sorted()
        let floor = region[Int(Double(region.count) * 0.15)]
        let peak = region[min(region.count - 1, Int(Double(region.count) * 0.95))]
        guard peak > floor * 2, peak > 0.003 else { return nil }
        let threshold = floor + (peak - floor) * 0.25

        // Speech frames, with short gaps filled and short blips removed.
        var speech = (lo..<hi).map { envelope[$0] > threshold }
        fill(&speech, value: false, shorterThan: Int(rate * 0.25)) // short pauses inside speech
        fill(&speech, value: true, shorterThan: Int(rate * 0.12))  // short clicks and blips

        var onsets: [Double] = [], offsets: [Double] = []
        for k in 1..<speech.count {
            if speech[k] && !speech[k - 1] { onsets.append(time(lo + k)) }
            if !speech[k] && speech[k - 1] { offsets.append(time(lo + k)) }
        }

        // Search windows; empty when the neighbours leave no room.
        let startLow = max(start - 1.0, (prevEnd ?? -1) + 0.05), startHigh = start + 0.8
        let endLow = end - 1.0, endHigh = min(end + 1.5, (nextStart ?? .infinity) - 0.05)
        let newStart = onsets.filter { $0 >= startLow && $0 <= startHigh }.min { abs($0 - start) < abs($1 - start) }
        var newEnd = offsets.filter { $0 >= endLow && $0 <= endHigh }.min { abs($0 - end) < abs($1 - end) }
        // A short tail after the speech, without running into the next subtitle.
        if let e = newEnd { newEnd = min(e + 0.15, (nextStart ?? .infinity) - 0.05) }

        guard newStart != nil || newEnd != nil else { return nil }
        let s = newStart.map { max($0 - 0.05, 0) } ?? start
        let e = newEnd ?? end
        guard e - s >= 0.5 else { return nil }
        return (s, e)
    }

    /// Flips runs of `value` that are shorter than `shorterThan` frames
    /// (and lie between frames of the other value).
    private static func fill(_ a: inout [Bool], value: Bool, shorterThan: Int) {
        var i = 0
        while i < a.count {
            guard a[i] == !value else { i += 1; continue }
            // a[i] is the "other" value; skip it
            i += 1
            var j = i
            while j < a.count && a[j] == value { j += 1 }
            if j < a.count && j - i > 0 && j - i < shorterThan {
                for k in i..<j { a[k] = !value }
            }
            i = j
        }
    }
}

/// The video that belongs to the file being reviewed: playback clips and audio analysis.
@MainActor
@Observable
final class MediaSupport {
    private(set) var videoURL: URL?
    /// Can AVFoundation play the file itself? nil = not checked yet.
    private(set) var isPlayable: Bool?
    /// Loudness envelope for the whole file, once analysed.
    private(set) var fullEnvelope: [Float]?
    @ObservationIgnored private var clipCache: [String: URL] = [:]

    var hasVideo: Bool { videoURL != nil }
    /// The file needs ffmpeg, which is not installed.
    var needsFFmpeg: Bool { isPlayable == false && !FFmpeg.isAvailable }

    func setVideo(_ url: URL?) {
        videoURL = url
        isPlayable = nil
        fullEnvelope = nil
        for file in clipCache.values { try? FileManager.default.removeItem(at: file) }
        clipCache = [:]
        guard let url else { return }
        Task {
            let playable = (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
            if videoURL == url { isPlayable = playable }
        }
    }

    private func playable() async -> Bool {
        if let isPlayable { return isPlayable }
        guard let url = videoURL else { return false }
        let p = (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
        isPlayable = p
        return p
    }

    /// A file to play for the span `from`…`to` (video time), and the video time
    /// at which the file starts (0 when the original file is played).
    func clip(from: Double, to: Double) async throws -> (url: URL, offset: Double) {
        guard let video = videoURL else { throw MediaError.noVideo }
        if await playable() { return (video, 0) }
        guard FFmpeg.isAvailable else { throw MediaError.needsFFmpeg(video.pathExtension) }
        let start = max(from, 0)
        let key = "\(Int(start * 10))-\(Int(to * 10))"
        if let cached = clipCache[key] { return (cached, start) }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("subtitle-transfixer-\(UUID().uuidString).mp4")
        _ = try await FFmpeg.run([
            "-y", "-ss", FFmpeg.seconds(start), "-i", video.path, "-t", FFmpeg.seconds(to - start),
            "-sn", "-dn", "-vf", "scale=640:-2", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "30",
            "-c:a", "aac", "-ac", "2", "-b:a", "128k", out.path,
        ])
        clipCache[key] = out
        return (out, start)
    }

    /// Loudness for `from`…`to` (video time). `[0]` is at `max(from, 0)`.
    func envelope(from: Double, to: Double) async throws -> [Float] {
        let start = max(from, 0)
        if let all = fullEnvelope {
            let lo = min(all.count, Int(start * AudioReader.envelopeRate))
            let hi = min(all.count, Int(to * AudioReader.envelopeRate))
            return lo < hi ? Array(all[lo..<hi]) : []
        }
        guard let video = videoURL else { throw MediaError.noVideo }
        let pcm: Data
        if await playable() {
            pcm = try await AudioReader.readPCM(url: video, from: start, duration: to - start)
        } else if FFmpeg.isAvailable {
            pcm = try await AudioReader.readPCMWithFFmpeg(url: video, from: start, duration: to - start)
        } else {
            throw MediaError.needsFFmpeg(video.pathExtension)
        }
        return AudioReader.envelope(pcm)
    }

    /// Analyses the audio of the whole file (takes a few seconds for an episode).
    func loadFullEnvelope() async throws -> [Float] {
        if let fullEnvelope { return fullEnvelope }
        guard let video = videoURL else { throw MediaError.noVideo }
        let pcm: Data
        if await playable() {
            pcm = try await AudioReader.readPCM(url: video, from: nil, duration: nil)
        } else if FFmpeg.isAvailable {
            pcm = try await AudioReader.readPCMWithFFmpeg(url: video, from: nil, duration: nil)
        } else {
            throw MediaError.needsFFmpeg(video.pathExtension)
        }
        let env = AudioReader.envelope(pcm)
        if videoURL == video { fullEnvelope = env }
        return env
    }
}

/// Plays a clip and reports the current video time.
@MainActor
@Observable
final class ClipPlayer {
    let player = AVPlayer()
    /// Video time at which the loaded file starts.
    private(set) var offset: Double = 0
    /// Current position in video time.
    private(set) var currentTime: Double = 0
    @ObservationIgnored private var observer: Any?

    func load(url: URL, offset: Double) {
        self.offset = offset
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if observer == nil {
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] t in
                MainActor.assumeIsolated { self?.currentTime = t.seconds + (self?.offset ?? 0) }
            }
        }
    }

    /// Plays from `from` and stops at `to` (video time).
    func play(from: Double, to: Double) {
        guard let item = player.currentItem else { return }
        item.forwardPlaybackEndTime = CMTime(seconds: max(to - offset, 0.1), preferredTimescale: 1000)
        let target = CMTime(seconds: max(from - offset, 0), preferredTimescale: 1000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.player.play() }
        }
    }

    func seek(to t: Double) {
        player.currentItem?.forwardPlaybackEndTime = .invalid
        player.seek(to: CMTime(seconds: max(t - offset, 0), preferredTimescale: 1000),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = t
    }

    func togglePause() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func stop() {
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        player.replaceCurrentItem(with: nil)
    }
}
