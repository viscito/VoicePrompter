import PDFKit

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

    /// Load and tokenize a PDF's text. Returns nil if the file can't be opened.
    static func load(from url: URL) -> Script? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { return nil }

        var raw = ""
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string { raw += s + "\n\n" }
        }
        return parse(raw)
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
}
