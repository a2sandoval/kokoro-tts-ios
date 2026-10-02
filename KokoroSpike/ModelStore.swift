import Combine
import Foundation

/// Locates the Kokoro model files bundled inside the app.
/// The "Bundle Kokoro model" build phase downloads the pre-packaged model
/// archive from the GitHub release and extracts it into the app bundle,
/// so there is no in-app download.
@MainActor
final class ModelStore: ObservableObject {
    enum Phase: Equatable {
        case checking
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .checking

    private var bundleURL: URL {
        Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }

    var modelURL: URL { bundleURL.appendingPathComponent("model.int8.onnx") }
    var voicesURL: URL { bundleURL.appendingPathComponent("voices.bin") }
    var tokensURL: URL { bundleURL.appendingPathComponent("tokens.txt") }
    var lexiconURL: URL { bundleURL.appendingPathComponent("lexicon-us-en.txt") }
    var dataDirURL: URL { bundleURL.appendingPathComponent("espeak-ng-data", isDirectory: true) }

    var isReady: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: modelURL.path)
            && fm.fileExists(atPath: voicesURL.path)
            && fm.fileExists(atPath: tokensURL.path)
            && fm.fileExists(atPath: dataDirURL.path)
    }

    func check() {
        // Clean up partial downloads left by older versions that fetched the
        // model at runtime; the model now ships inside the app.
        let oldDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kokoro", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldDir.path) {
            try? FileManager.default.removeItem(at: oldDir)
        }
        phase = isReady ? .ready : .failed("Voice files are missing from the app. Please reinstall it.")
    }
}
