import Foundation

#if canImport(SherpaOnnx)
@preconcurrency import SherpaOnnx
#elseif canImport(SherpaOnnxShared)
@preconcurrency import SherpaOnnxShared
#else
#error("sherpa-onnx module not found. Add the k2-fsa/sherpa-onnx Swift package.")
#endif

/// Wraps sherpa-onnx's Kokoro offline TTS. All blocking inference runs on a
/// dedicated background queue; state is published on the main actor.
@MainActor
final class KokoroEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case generating
        case playing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var voice: KokoroVoice = .default
    @Published var speed: Float = 1.0

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private let player = AudioPlayer()
    private let store: ModelStore
    private let ttsQueue = DispatchQueue(label: "kokoro.tts", qos: .userInitiated)
    private var genState: GenState?

    /// Cancellation flag shared with the C progress callback (callback thread only reads).
    private final class GenState: @unchecked Sendable {
        private let lock = NSLock()
        private var _cancelled = false
        var cancelled: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _cancelled }
            set { lock.lock(); defer { lock.unlock() }; _cancelled = newValue }
        }
    }

    init(store: ModelStore) {
        self.store = store
    }

    /// Lazily creates the TTS engine. Safe to call repeatedly.
    func ensureLoaded() {
        guard tts == nil, phase != .loading else { return }
        phase = .loading
        let model = store.modelURL.path
        let voices = store.voicesURL.path
        let tokens = store.tokensURL.path
        let dataDir = store.dataDirURL.path
        let lexiconPath = store.lexiconURL.path
        let lexicon = FileManager.default.fileExists(atPath: lexiconPath) ? lexiconPath : ""
        ttsQueue.async { [weak self] in
            let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
                model: model,
                voices: voices,
                tokens: tokens,
                dataDir: dataDir,
                lengthScale: 1.0,
                dictDir: "",
                lexicon: lexicon,
                lang: ""
            )
            var config = sherpaOnnxOfflineTtsConfig(
                model: sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, numThreads: 4, debug: 0)
            )
            let wrapper = SherpaOnnxOfflineTtsWrapper(config: &config)
            let ok = wrapper.tts != nil
            let speakers = ok ? wrapper.numSpeakers : 0
            let rate = ok ? wrapper.sampleRate : 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if ok {
                    self.tts = wrapper
                    self.phase = .ready
                    print("KokoroSpike: engine ready, speakers=\(speakers) rate=\(rate)")
                } else {
                    self.phase = .failed("Could not initialize the voice engine.")
                }
            }
        }
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopPlaybackOnly()
        guard let tts else {
            phase = .failed("Engine not loaded yet.")
            return
        }
        phase = .generating
        let state = GenState()
        genState = state
        let sid = voice.sid
        let speed = self.speed
        ttsQueue.async { [weak self] in
            guard let self else { return }
            let genConfig = SherpaOnnxGenerationConfigSwift(silenceScale: 0.2, speed: speed, sid: sid)
            // Non-capturing closure -> C function pointer. Returning 0 aborts generation.
            let callback: TtsProgressCallbackWithArg = { _, _, _, arg in
                let st = Unmanaged<GenState>.fromOpaque(arg!).takeUnretainedValue()
                return st.cancelled ? 0 : 1
            }
            let rawState = Unmanaged.passUnretained(state).toOpaque()
            let audio = tts.generateWithConfig(
                text: trimmed, config: genConfig, callback: callback, arg: rawState
            )
            let samples = audio.samples
            let rate = Double(audio.sampleRate)
            let wasCancelled = state.cancelled
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.genState = nil
                if wasCancelled || samples.isEmpty {
                    self.phase = self.tts == nil ? .idle : .ready
                    return
                }
                self.phase = .playing
                self.player.play(samples: samples, sampleRate: rate) { [weak self] in
                    guard let self else { return }
                    if self.phase == .playing { self.phase = .ready }
                }
            }
        }
    }

    /// Stops playback and aborts any in-flight generation.
    func stop() {
        genState?.cancelled = true
        stopPlaybackOnly()
        if phase == .playing || phase == .generating {
            phase = tts == nil ? .idle : .ready
        }
    }

    private func stopPlaybackOnly() {
        player.stop()
    }
}
