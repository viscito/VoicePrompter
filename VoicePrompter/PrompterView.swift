import SwiftUI

/// Collects each word's vertical midpoint within the content coordinate space.
/// Because it's measured in the content's own space, values are stable as the
/// content scrolls and only recompute when layout actually changes.
struct WordFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, n in n })
    }
}

/// The scrolling prompter surface. Words flow like text, the current word is
/// highlighted karaoke-style, and the content is offset so that word sits on a
/// fixed read line — interpolating between words for smooth, continuous motion.
struct PrompterView: View {
    @ObservedObject var engine: PrompterEngine
    @State private var wordMidY: [Int: CGFloat] = [:]

    private let readLineFraction: CGFloat = 0.4     // where the "live" word sits

    var body: some View {
        GeometryReader { geo in
            let readLineY = geo.size.height * readLineFraction

            content(readLineY: readLineY)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .coordinateSpace(name: "content")
                .offset(y: readLineY - targetY())
                .onPreferenceChange(WordFramesKey.self) { wordMidY = $0 }
        }
        .clipped()
        .background(.black)
        .overlay(alignment: .top) {                 // subtle read-line marker
            GeometryReader { g in
                Rectangle().fill(.white.opacity(0.06))
                    .frame(height: engine.fontSize * 1.6)
                    .offset(y: g.size.height * readLineFraction - engine.fontSize * 0.8)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .center) {
            if engine.wordCount == 0 {
                Text(engine.statusMessage ?? "Open a PDF to begin")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(40)
                    .frame(maxWidth: 520)
            }
        }
    }

    private func content(readLineY: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            Color.clear.frame(height: readLineY)                 // lead-in
            ForEach(engine.script.paragraphs) { para in
                FlowLayout {
                    ForEach(para.wordRange, id: \.self) { i in
                        wordView(engine.script.words[i])
                    }
                }
            }
            Color.clear.frame(height: readLineY * 1.5)           // run-out
        }
        .padding(.horizontal, 40)
    }

    private func wordView(_ word: Word) -> some View {
        let idx = engine.currentWordIndex
        let color: Color = word.id == idx ? .yellow
                         : word.id  < idx ? .white
                                          : .white.opacity(0.45)
        return Text(word.text)
            .font(.system(size: engine.fontSize,
                          weight: word.id == idx ? .bold : .medium))
            .foregroundStyle(color)
            .background(GeometryReader { g in
                Color.clear.preference(key: WordFramesKey.self,
                    value: [word.id: g.frame(in: .named("content")).midY])
            })
            .onTapGesture { engine.seek(toWord: word.id) }        // click-to-seek
    }

    /// Interpolate the target Y between the current word and the next so the
    /// prompter glides rather than hopping paragraph-to-paragraph.
    private func targetY() -> CGFloat {
        guard engine.wordCount > 0 else { return 0 }
        let p = engine.position
        let lo = min(Int(p), engine.wordCount - 1)
        let hi = min(lo + 1, engine.wordCount - 1)
        let f = CGFloat(p - Double(lo))
        let y0 = wordMidY[lo] ?? 0
        let y1 = wordMidY[hi] ?? y0
        return y0 + (y1 - y0) * f
    }
}
