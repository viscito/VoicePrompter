import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var engine = PrompterEngine()
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            PrompterView(engine: engine)
            Divider()
            ScrubberBar(engine: engine)
                .padding(.horizontal)
                .padding(.top, 8)
            controls
        }
        .frame(minWidth: 760, minHeight: 540)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                engine.load(url: url)
            case .failure(let error):
                engine.report("File selection failed: \(error.localizedDescription)")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { showImporter = true } label: { Image(systemName: "doc.badge.plus") }
                .help("Open PDF")

            Button { engine.restart() } label: { Image(systemName: "backward.end.fill") }
                .help("Restart")
            Button { engine.rewind() } label: { Image(systemName: "gobackward.5") }
                .help("Rewind 5 seconds")

            Button { engine.toggle() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play / Pause")

            Divider().frame(height: 22)

            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
            Slider(value: $engine.wpm, in: 60...300).frame(minWidth: 120)
            Image(systemName: "hare.fill").foregroundStyle(.secondary)
            Text("\(Int(engine.wpm)) wpm").monospacedDigit().frame(width: 70)

            Divider().frame(height: 22)

            Stepper("Font", value: $engine.fontSize, in: 18...80, step: 2).labelsHidden()
            Text("\(Int(engine.fontSize))pt").monospacedDigit().frame(width: 44)
        }
        .padding()
        .buttonStyle(.borderless)
    }
}

#Preview {
    ContentView()
}
