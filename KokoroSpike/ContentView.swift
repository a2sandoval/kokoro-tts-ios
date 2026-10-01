import SwiftUI

struct ContentView: View {
    @StateObject private var store: ModelStore
    @StateObject private var engine: KokoroEngine

    init() {
        let s = ModelStore()
        _store = StateObject(wrappedValue: s)
        _engine = StateObject(wrappedValue: KokoroEngine(store: s))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .checking:
                ProgressView("Checking voice files…")
            case .missing, .failed:
                DownloadView(store: store)
            case .downloading:
                DownloadView(store: store)
            case .ready:
                ReaderView(engine: engine)
            }
        }
        .onAppear { store.check() }
    }
}

// MARK: - Download

struct DownloadView: View {
    @ObservedObject var store: ModelStore

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Kokoro Voices")
                .font(.largeTitle.bold())
            Text("Free, open-source neural voices that run entirely on your iPhone. One download of about 165 MB, then everything works offline.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            switch store.phase {
            case .downloading(let downloaded, let total, let label):
                VStack(spacing: 8) {
                    ProgressView(value: Double(downloaded), total: Double(total))
                    Text("\(label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(formatMB(downloaded)) of \(formatMB(total))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Try Again") { store.download() }
                    .buttonStyle(.borderedProminent)
            default:
                Button("Download Voices (165 MB)") { store.download() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Spacer()
        }
        .padding()
    }

    private func formatMB(_ bytes: Int64) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }
}

// MARK: - Reader

struct ReaderView: View {
    @ObservedObject var engine: KokoroEngine
    @State private var text = """
        Hello! This is Kokoro, a free and open-source voice running entirely on your iPhone. \
        No cloud, no subscription, and none of your words ever leave this device. \
        The quick brown fox jumps over the lazy dog. \
        Try a different voice, or paste in anything you like — an article, a chapter, a message — and press speak.
        """

    var body: some View {
        NavigationStack {
            Form {
                Section("Voice") {
                    NavigationLink {
                        VoicePickerView(engine: engine)
                    } label: {
                        HStack {
                            Text(engine.voice.displayName)
                            Spacer()
                            Text(engine.voice.accentDescription)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                }

                Section("Speed") {
                    HStack {
                        Slider(value: $engine.speed, in: 0.5...2.0, step: 0.05)
                        Text(String(format: "%.2fx", engine.speed))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        switch engine.phase {
                        case .loading:
                            ProgressView("Loading voices…")
                        case .generating:
                            ProgressView("Generating speech…")
                        case .playing:
                            Button("Stop", systemImage: "stop.fill") { engine.stop() }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                        case .failed(let message):
                            Text(message).foregroundStyle(.red)
                        default:
                            Button("Speak", systemImage: "play.fill") {
                                engine.ensureLoaded()
                                // ensureLoaded is async; speak once ready
                                waitForReadyThenSpeak()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Kokoro TTS")
            .onAppear { engine.ensureLoaded() }
        }
    }

    private func waitForReadyThenSpeak() {
        Task { @MainActor in
            for _ in 0..<600 {
                if engine.phase == .ready {
                    engine.speak(text)
                    return
                }
                if case .failed = engine.phase { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

// MARK: - Voice picker

struct VoicePickerView: View {
    @ObservedObject var engine: KokoroEngine

    var body: some View {
        List {
            Section("English") {
                ForEach(KokoroVoice.english) { voice in
                    voiceRow(voice)
                }
            }
            Section("Other languages") {
                ForEach(KokoroVoice.other) { voice in
                    voiceRow(voice)
                }
            }
        }
        .navigationTitle("Voice")
    }

    private func voiceRow(_ voice: KokoroVoice) -> some View {
        Button {
            engine.voice = voice
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(voice.displayName)
                        .foregroundStyle(.primary)
                    Text(voice.accentDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if engine.voice == voice {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
