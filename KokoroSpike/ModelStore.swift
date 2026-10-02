import Foundation
import UIKit

/// Downloads the Kokoro model files from Hugging Face on first launch.
/// Model: csukuangfj/kokoro-int8-multi-lang-v1_0 (int8, ~166 MB total).
@MainActor
final class ModelStore: ObservableObject {
    enum Phase: Equatable {
        case checking
        case missing
        case downloading(downloaded: Int64, total: Int64, label: String)
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .checking

    static let hfBase = "https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_0/resolve/main/"
    static let hfTreeAPI = "https://huggingface.co/api/models/csukuangfj/kokoro-int8-multi-lang-v1_0/tree/main/espeak-ng-data?recursive=true"

    let dir: URL
    var modelURL: URL { dir.appendingPathComponent("model.int8.onnx") }
    var voicesURL: URL { dir.appendingPathComponent("voices.bin") }
    var tokensURL: URL { dir.appendingPathComponent("tokens.txt") }
    var lexiconURL: URL { dir.appendingPathComponent("lexicon-us-en.txt") }
    var dataDirURL: URL { dir.appendingPathComponent("espeak-ng-data", isDirectory: true) }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("kokoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var isReady: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: modelURL.path)
            && fm.fileExists(atPath: voicesURL.path)
            && fm.fileExists(atPath: tokensURL.path)
            && fm.fileExists(atPath: dataDirURL.path)
    }

    func check() {
        phase = isReady ? .ready : .missing
    }

    func download() {
        // Keep the screen awake: iOS suspends ordinary downloads when the app backgrounds.
        UIApplication.shared.isIdleTimerDisabled = true
        phase = .downloading(downloaded: 0, total: 1, label: "Starting…")
        Task.detached { [weak self] in
            do {
                try await Self.performDownload { downloaded, total, label in
                    await MainActor.run { [weak self] in
                        self?.phase = .downloading(downloaded: downloaded, total: total, label: label)
                    }
                }
                await MainActor.run { [weak self] in
                    UIApplication.shared.isIdleTimerDisabled = false
                    guard let self else { return }
                    self.phase = self.isReady ? .ready : .failed("Download finished but files are missing.")
                }
            } catch {
                await MainActor.run { [weak self] in
                    UIApplication.shared.isIdleTimerDisabled = false
                    self?.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func resetToMissing() {
        phase = .missing
    }

    // MARK: - Download engine (runs off the main actor)

    private struct Item {
        let remote: String
        let local: String
        let size: Int64
    }

    private struct HFEntry: Decodable {
        let path: String
        let type: String
        let size: Int?
    }

    private actor ProgressState {
        var done: Int64 = 0
        func add(_ n: Int64) -> Int64 { done += n; return done }
    }

    private static func performDownload(
        report: @escaping (Int64, Int64, String) async -> Void
    ) async throws {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kokoro", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var items: [Item] = [
            Item(remote: "model.int8.onnx", local: "model.int8.onnx", size: 114_203_756),
            Item(remote: "voices.bin", local: "voices.bin", size: 28_200_960),
            Item(remote: "tokens.txt", local: "tokens.txt", size: 687),
            Item(remote: "lexicon-us-en.txt", local: "lexicon-us-en.txt", size: 6_366_635),
        ]

        // espeak-ng-data file list (355 small files, ~17.5 MB)
        let (apiData, apiResponse) = try await URLSession.shared.data(from: URL(string: hfTreeAPI)!)
        guard (apiResponse as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            throw URLError(.badServerResponse)
        }
        let entries = try JSONDecoder().decode([HFEntry].self, from: apiData)
        for e in entries where e.type != "directory" {
            items.append(Item(remote: e.path, local: e.path, size: Int64(e.size ?? 0)))
        }

        let total = items.reduce(0) { $0 + $1.size }
        let progress = ProgressState()

        // Big files first, sequentially.
        for item in items.prefix(4) {
            try await fetch(item: item, dir: dir, total: total, progress: progress, report: report)
        }
        // espeak-ng-data with limited parallelism.
        let rest = Array(items.dropFirst(4))
        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = 0
            for item in rest {
                if pending >= 6 {
                    try await group.next()
                    pending -= 1
                }
                pending += 1
                group.addTask {
                    try await fetch(item: item, dir: dir, total: total, progress: progress, report: report)
                }
            }
            try await group.waitForAll()
        }
        let done = await progress.add(0)
        await report(done, total, "Finishing…")
    }

    private static let chunkSize: Int64 = 4 * 1024 * 1024  // 4 MB chunks

    private static func fetch(
        item: Item,
        dir: URL,
        total: Int64,
        progress: ProgressState,
        report: @escaping (Int64, Int64, String) async -> Void
    ) async throws {
        let fm = FileManager.default
        let localURL = dir.appendingPathComponent(item.local)
        let url = URL(string: hfBase + item.remote)!

        // Resume: pick up where a previous attempt left off.
        var offset: Int64 = 0
        if fm.fileExists(atPath: localURL.path) {
            offset = (try? fm.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
            if item.size > 0 && offset >= item.size {
                let d = await progress.add(offset)
                await report(d, total, item.local)
                return
            }
        } else {
            try fm.createDirectory(
                at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: localURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: localURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var lastReport = await progress.add(0)
        while item.size <= 0 || offset < item.size {
            let end: Int64 =
                item.size > 0 ? min(offset + chunkSize - 1, item.size - 1) : offset + chunkSize - 1
            var request = URLRequest(url: url)
            request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")

            // Retry a chunk several times with backoff; a dropout loses at most one chunk.
            var lastError: Error?
            var chunkDone = false
            for attempt in 1...6 {
                do {
                    // One direct fetch per chunk: far faster than byte-by-byte AsyncBytes.
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
                    if status == 200 && offset > 0 {
                        // Server ignored the Range header; restart the file from scratch.
                        try handle.truncate(atOffset: 0)
                        try handle.seek(toOffset: 0)
                        offset = 0
                        throw URLError(.cannotParseResponse)
                    }
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                    let received = Int64(data.count)
                    offset += received
                    let d = await progress.add(received)
                    if d - lastReport > max(total / 200, 1) {
                        lastReport = d
                        await report(d, total, item.local)
                    }
                    chunkDone = true
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    // Roll the file back to the last fully-downloaded chunk before retrying.
                    try? handle.truncate(atOffset: UInt64(max(offset, 0)))
                    try? handle.seekToEnd()
                    if attempt < 6 {
                        let delay = UInt64(1 << min(attempt, 4)) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: delay)
                    }
                }
            }
            if !chunkDone {
                throw lastError ?? URLError(.unknown)
            }
            if item.size <= 0 { break }
        }
        let d = await progress.add(0)
        await report(d, total, item.local)
    }
}
