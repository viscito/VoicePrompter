import SwiftUI
import Combine

/// Drives the teleprompter off a single continuous `position` (a fractional
/// word index). Speed, rewind, seek and scrubbing are all just changes to it.
@MainActor
final class PrompterEngine: ObservableObject {
    @Published var script = Script()
    @Published var isPlaying = false
    @Published var wpm: Double = 130                    // reading pace
    @Published var fontSize: Double = 34
    @Published var position: Double = 0                 // fractional word index
    @Published var statusMessage: String?               // shown when nothing is loaded

    @Published private(set) var isScrubbing = false
    private var resumeAfterScrub = false

    private var lastTick: Date?
    private var timer: AnyCancellable?

    var wordCount: Int { script.words.count }
    var currentWordIndex: Int { min(Int(position), max(0, wordCount - 1)) }

    var totalSeconds:   Double { wpm > 0 ? Double(wordCount) * 60.0 / wpm : 0 }
    var currentSeconds: Double { wpm > 0 ? position * 60.0 / wpm : 0 }
    var progress:       Double { wordCount > 1 ? position / Double(wordCount - 1) : 0 }

    // MARK: Loading

    func load(url: URL) {
        pause()
        position = 0
        switch Script.load(from: url) {
        case .success(let s):
            script = s
            statusMessage = nil
        case .emptyText:
            script = Script()
            statusMessage = """
            “\(url.lastPathComponent)” has no selectable text — it looks like a \
            scanned or image-only PDF. It needs OCR before it can be read as a script.
            """
        case .unreadable:
            script = Script()
            statusMessage = "Couldn’t open “\(url.lastPathComponent)” as a PDF."
        }
    }

    func report(_ message: String) {
        statusMessage = message
    }

    // MARK: Transport

    func play() {
        guard !script.words.isEmpty else { return }
        isPlaying = true
        lastTick = Date()
        timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause()   { isPlaying = false; timer?.cancel(); timer = nil; lastTick = nil }
    func toggle()  { isPlaying ? pause() : play() }
    func restart() { position = 0 }

    func rewind(seconds: Double = 5) {
        position = max(0, position - seconds * wpm / 60.0)
    }

    func seek(toWord index: Int) {
        position = Double(min(max(0, index), max(0, wordCount - 1)))
    }

    // MARK: Scrubbing

    func beginScrub() {
        resumeAfterScrub = isPlaying
        isScrubbing = true
        pause()
    }

    func scrub(toProgress p: Double) {
        let clamped = min(max(0, p), 1)
        position = clamped * Double(max(0, wordCount - 1))
    }

    func endScrub() {
        isScrubbing = false
        if resumeAfterScrub { play() }
        resumeAfterScrub = false
    }

    // MARK: Clock

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick ?? now)
        lastTick = now
        position += dt * wpm / 60.0
        if position >= Double(wordCount) {
            position = Double(max(0, wordCount - 1))
            pause()
        }
    }
}
