import AppKit
import CoreGraphics

/// A precomputed layout of the whole script: the frame of every word (indexed
/// by word id) and the total content height, for a given column width and font.
///
/// Computing this once with TextKit lets the prompter render only the words in
/// the visible window while still positioning the highlighted word exactly —
/// the positions come from this model, not from measuring live SwiftUI views,
/// so it scales to book-length scripts.
struct ScriptLayout {
    var boxes: [CGRect]        // boxes[wordID] in top-left content coordinates
    var totalHeight: CGFloat
    var width: CGFloat
    var fontSize: CGFloat

    /// Build the layout. CPU-bound; call from a background task for large scripts.
    static func make(script: Script, width: CGFloat, fontSize: CGFloat) -> ScriptLayout {
        guard width > 0, !script.words.isEmpty else {
            return ScriptLayout(boxes: [], totalHeight: 0, width: width, fontSize: fontSize)
        }

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.4
        paragraphStyle.paragraphSpacing = fontSize * 0.9

        let full = NSMutableAttributedString()
        var wordRanges = [NSRange](repeating: NSRange(location: 0, length: 0),
                                   count: script.words.count)

        for para in script.paragraphs {
            for i in para.wordRange {
                let word = script.words[i]
                let start = full.length
                full.append(NSAttributedString(string: word.text))
                wordRanges[word.id] = NSRange(location: start,
                                              length: (word.text as NSString).length)
                full.append(NSAttributedString(string: " "))   // separator, not part of the word
            }
            full.append(NSAttributedString(string: "\n"))       // paragraph break
        }
        full.addAttributes([.font: font, .paragraphStyle: paragraphStyle],
                           range: NSRange(location: 0, length: full.length))

        // TextKit stack, used only here and never touched by the UI.
        let textStorage = NSTextStorage(attributedString: full)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width,
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        var boxes = [CGRect](repeating: .zero, count: script.words.count)
        for id in 0..<script.words.count {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: wordRanges[id],
                                                      actualCharacterRange: nil)
            boxes[id] = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        }

        let total = layoutManager.usedRect(for: container).height
        return ScriptLayout(boxes: boxes, totalHeight: total, width: width, fontSize: fontSize)
    }

    // MARK: Windowing (boxes are in reading order, so minY/maxY are non-decreasing)

    /// First word id whose bottom edge reaches `y` (>= y).
    func firstID(bottomAtLeast y: CGFloat) -> Int {
        var lo = 0, hi = boxes.count - 1, ans = boxes.count
        while lo <= hi {
            let mid = (lo + hi) / 2
            if boxes[mid].maxY >= y { ans = mid; hi = mid - 1 } else { lo = mid + 1 }
        }
        return ans
    }

    /// Last word id whose top edge is still above `y` (<= y).
    func lastID(topAtMost y: CGFloat) -> Int {
        var lo = 0, hi = boxes.count - 1, ans = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if boxes[mid].minY <= y { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }
}
