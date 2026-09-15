import Foundation

enum TranscriptionPhase: String, Codable {
    case idle
    case scheduled
    case preparing
    case transcribing
    case completed
    case cancelled
    case interrupted
    case failed
    case expired

    var isTerminal: Bool {
        self == .completed || self == .cancelled || self == .interrupted || self == .failed || self == .expired
    }
}

struct TranscriptionRun: Codable, Identifiable {
    let id: String
    let platform: String
    var audioSource: String?
    let fixtureFileName: String
    let expectedDurationSeconds: Int
    let startedAt: Date
    var updatedAt: Date
    var phase: TranscriptionPhase
    var progressPercent: Int
    var backgroundedDuringRun: Bool
    var transcript: String
    var error: String?

    static var empty: TranscriptionRun {
        TranscriptionRun(
            id: "none",
            platform: "iOS",
            audioSource: TranscriptionSource.injectedFixture.rawValue,
            fixtureFileName: "none",
            expectedDurationSeconds: 0,
            startedAt: Date(),
            updatedAt: Date(),
            phase: .idle,
            progressPercent: 0,
            backgroundedDuringRun: false,
            transcript: "",
            error: nil
        )
    }
}
