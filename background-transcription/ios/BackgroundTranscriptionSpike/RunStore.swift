import Foundation

extension Notification.Name {
    static let transcriptionRunUpdated = Notification.Name("transcriptionRunUpdated")
}

final class RunStore {
    static let shared = RunStore()

    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var resultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("background-transcription/latest.json")
    }

    func load() -> TranscriptionRun {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: resultURL),
              let run = try? decoder.decode(TranscriptionRun.self, from: data)
        else {
            return .empty
        }
        return run
    }

    @discardableResult
    func update(id: String, _ change: (inout TranscriptionRun) -> Void) -> TranscriptionRun? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: resultURL),
              var run = try? decoder.decode(TranscriptionRun.self, from: data),
              run.id == id,
              !run.phase.isTerminal
        else {
            return nil
        }
        change(&run)
        run.updatedAt = Date()
        saveLocked(run)
        notify()
        return run
    }

    func save(_ run: TranscriptionRun) {
        lock.lock()
        saveLocked(run)
        lock.unlock()
        notify()
    }

    private func saveLocked(_ run: TranscriptionRun) {
        let directory = resultURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(run) else { return }
        try? data.write(to: resultURL, options: .atomic)
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transcriptionRunUpdated, object: nil)
        }
    }
}
