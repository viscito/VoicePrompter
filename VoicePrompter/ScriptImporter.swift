import PDFKit
import Vision
import CoreGraphics

/// Outcome of trying to import a PDF, so the UI can explain failures.
enum ScriptLoadResult {
    case success(Script)
    case emptyText      // opened, but no selectable text (likely a scanned/image PDF)
    case unreadable     // couldn't be opened as a PDF at all
}

/// One tokenized word from the script, with a stable global index.
struct Word: Identifiable {
    let id: Int          // global index into Script.words
    let text: String
    let paragraphID: Int
}

/// A paragraph of the reflowed text and the range of word indices it owns.
struct Paragraph: Identifiable {
    let id: Int
    let text: String
    let wordRange: Range<Int>   // indices into Script.words
}

/// The full imported script: a flat list of words plus paragraph grouping.
struct Script {
    var words: [Word] = []
    var paragraphs: [Paragraph] = []

    /// Load and tokenize a PDF's text, reporting why it failed if it did.
    static func load(from url: URL) -> ScriptLoadResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { return .unreadable }

        var raw = ""
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string { raw += s + "\n\n" }
        }

        let script = parse(raw)
        return script.words.isEmpty ? .emptyText : .success(script)
    }

    /// Split raw text into paragraphs (on blank lines) and words (on whitespace).
    static func parse(_ raw: String) -> Script {
        var script = Script()
        var wordCounter = 0

        let paraTexts = raw
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ")
                     .trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for (pIndex, text) in paraTexts.enumerated() {
            let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let start = wordCounter
            for t in tokens {
                script.words.append(Word(id: wordCounter, text: t, paragraphID: pIndex))
                wordCounter += 1
            }
            script.paragraphs.append(
                Paragraph(id: pIndex, text: text, wordRange: start..<wordCounter))
        }
        return script
    }

    // MARK: OCR fallback (for scanned / image-only PDFs)

    /// Render each page and recognize its text with Vision. CPU-heavy and
    /// synchronous — call from a background task. `progress` reports (page, total).
    static func ocr(url: URL, progress: @Sendable (Int, Int) -> Void) -> ScriptLoadResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { return .unreadable }

        let count = doc.pageCount
        var raw = ""
        for i in 0..<count {
            if Task.isCancelled { break }
            progress(i + 1, count)
            guard let page = doc.page(at: i), let image = render(page: page, scale: 2.5) else { continue }
            raw += recognizeLines(in: image).joined(separator: "\n") + "\n\n"
        }

        let script = parse(raw)
        return script.words.isEmpty ? .emptyText : .success(script)
    }

    /// Rasterize a PDF page to a bitmap suitable for OCR.
    private static func render(page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }

        ctx.setFillColor(gray: 1, alpha: 1)                      // white background
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// Recognize text lines in reading order (top to bottom).
    private static func recognizeLines(in cgImage: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return [] }

        let observations = (request.results ?? [])
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }   // Vision y-origin is bottom-left
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
