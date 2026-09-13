import SwiftUI

/// The scrolling prompter surface. Words are positioned from a precomputed
/// `ScriptLayout`, and only those in (or near) the viewport are rendered, so it
/// scales to very long scripts. The current word is highlighted karaoke-style
/// and parked on a fixed read line, gliding via interpolation between words.
struct PrompterView: View {
    @ObservedObject var engine: PrompterEngine
    @State private var layout: ScriptLayout?

    private let readLineFraction: CGFloat = 0.4     // where the "live" word sits
    private let columnMaxWidth: CGFloat = 820
    private let hPadding: CGFloat = 40

    private struct LayoutKey: Hashable { let rev: Int; let width: Int; let font: Int }

    var body: some View {
        GeometryReader { geo in
            let readLineY = geo.size.height * readLineFraction
            let colWidth = max(0, min(geo.size.width - hPadding * 2, columnMaxWidth))

            Group {
                if let layout, engine.wordCount > 0, !layout.boxes.isEmpty {
                    prompter(layout: layout, colWidth: colWidth,
                             readLineY: readLineY, viewport: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: LayoutKey(rev: engine.scriptRevision,
                                width: Int(colWidth), font: Int(engine.fontSize))) {
                guard colWidth > 0, engine.wordCount > 0 else { layout = nil; return }
                let script = engine.script
                let width = colWidth
                let fontSize = CGFloat(engine.fontSize)
                let computed = await Task.detached(priority: .userInitiated) {
                    ScriptLayout.make(script: script, width: width, fontSize: fontSize)
                }.value
                if Task.isCancelled { return }
                layout = computed
            }
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
                Text(engine.statusMessage ?? "Open or drop a PDF to begin")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(40)
                    .frame(maxWidth: 520)
            }
        }
    }

    private func prompter(layout: ScriptLayout, colWidth: CGFloat,
                          readLineY: CGFloat, viewport: CGFloat) -> some View {
        let target = targetY(layout)
        let offset = readLineY - target

        // Visible content-Y range, with one viewport of buffer above and below.
        let visibleTop = target - readLineY
        let lower = layout.firstID(bottomAtLeast: visibleTop - viewport)
        let upper = layout.lastID(topAtMost: visibleTop + viewport * 2)
        let ids = (lower <= upper && lower >= 0) ? Array(lower...upper) : []

        return ZStack(alignment: .topLeading) {
            ForEach(ids, id: \.self) { id in
                let box = layout.boxes[id]
                Text(engine.script.words[id].text)
                    .font(.system(size: engine.fontSize, weight: .medium))
                    .foregroundStyle(color(for: id))
                    .position(x: box.midX, y: box.midY)
                    .onTapGesture { engine.seek(toWord: id) }
            }
        }
        .frame(width: colWidth, height: layout.totalHeight, alignment: .topLeading)
        .offset(y: offset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func color(for id: Int) -> Color {
        let idx = engine.currentWordIndex
        if id == idx { return .yellow }
        return id < idx ? .white : .white.opacity(0.45)
    }

    /// Interpolate the read-line target between the current and next word.
    private func targetY(_ layout: ScriptLayout) -> CGFloat {
        let p = engine.position
        let lo = min(Int(p), engine.wordCount - 1)
        let hi = min(lo + 1, engine.wordCount - 1)
        guard lo >= 0, hi < layout.boxes.count else { return 0 }
        let f = CGFloat(p - Double(lo))
        let y0 = layout.boxes[lo].midY
        let y1 = layout.boxes[hi].midY
        return y0 + (y1 - y0) * f
    }
}
