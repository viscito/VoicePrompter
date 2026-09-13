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

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private enum Keys {
        static let wpm = "wpm"
        static let fontSize = "fontSize"
        static let bookmark = "lastPDFBookmark"
    }

    init() {
        // Restore saved preferences (clamped to valid ranges).
        if defaults.object(forKey: Keys.wpm) != nil {
            wpm = min(max(defaults.double(forKey: Keys.wpm), 60), 300)
        }
        if defaults.object(forKey: Keys.fontSize) != nil {
            fontSize = min(max(defaults.double(forKey: Keys.fontSize), 18), 80)
        }
        // Persist future changes.
        $wpm.sink { [weak self] in self?.defaults.set($0, forKey: Keys.wpm) }
            .store(in: &cancellables)
        $fontSize.sink { [weak self] in self?.defaults.set($0, forKey: Keys.fontSize) }
            .store(in: &cancellables)
        // Re-open the last file, if any.
        restoreLastFile()
    }

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
            saveBookmark(for: url)
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

    // MARK: Persistence

    /// Store a security-scoped bookmark to the current file so it survives
    /// relaunch (and keeps working once the app is sandboxed).
    private func saveBookmark(for url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            defaults.set(data, forKey: Keys.bookmark)
        }
    }

    /// Re-open the last file on launch. A successful load refreshes the
    /// bookmark; a missing/moved file clears it so we don't retry forever.
    private func restoreLastFile() {
        guard let data = defaults.data(forKey: Keys.bookmark) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            defaults.removeObject(forKey: Keys.bookmark)
            return
        }
        if stale { /* load()'s success path re-saves a fresh bookmark */ }
        load(url: url)
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
