import SwiftUI

/// Draggable progress bar with elapsed / total reading-time labels.
/// Tap to jump, drag to scrub; auto-pauses while dragging and resumes after.
struct ScrubberBar: View {
    @ObservedObject var engine: PrompterEngine

    var body: some View {
        HStack(spacing: 10) {
            Text(timeString(engine.currentSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)

            GeometryReader { geo in
                let w = geo.size.width
                let x = CGFloat(engine.progress) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 5)
                    Capsule().fill(.yellow).frame(width: max(0, x), height: 5)
                    Circle().fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(radius: 1)
                        .offset(x: min(max(0, x - 7), w - 14))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard w > 0 else { return }
                            if !engine.isScrubbing { engine.beginScrub() }
                            engine.scrub(toProgress: Double(v.location.x / w))
                        }
                        .onEnded { _ in engine.endScrub() }
                )
            }
            .frame(height: 20)

            Text(timeString(engine.totalSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
        }
    }

    private func timeString(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
