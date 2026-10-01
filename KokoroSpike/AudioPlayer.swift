import AVFoundation

/// Simple one-shot PCM playback through AVAudioEngine.
final class AudioPlayer: NSObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        engine.attach(player)
    }

    var isPlaying: Bool { player.isPlaying }

    func play(samples: [Float], sampleRate: Double, onFinish: @escaping () -> Void) {
        stop()
        self.onFinish = onFinish

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("KokoroSpike: audio session error: \(error)")
        }

        guard !samples.isEmpty,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              )
        else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            guard let dst = buffer.floatChannelData?[0], let s = src.baseAddress else { return }
            dst.update(from: s, count: samples.count)
        }

        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            print("KokoroSpike: engine start error: \(error)")
            return
        }
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async { self?.finishPlayback() }
        }
        player.play()
    }

    private func finishPlayback() {
        let cb = onFinish
        onFinish = nil
        stopEngine()
        cb?()
    }

    func stop() {
        onFinish = nil
        if player.isPlaying { player.stop() }
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        engine.disconnectNodeOutput(player)
    }
}
