import Foundation

enum TranscriptionSource: String, CaseIterable, Identifiable {
    case injectedFixture = "injected_fixture"
    case deviceMicrophone = "device_microphone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .injectedFixture: "Injected speech"
        case .deviceMicrophone: "Device mic"
        }
    }
}

enum RecordingDuration: String, CaseIterable, Identifiable {
    case twentySeconds
    case thirtySeconds
    case sixtySeconds
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case twentyMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twentySeconds: "20 seconds"
        case .thirtySeconds: "30 seconds"
        case .sixtySeconds: "60 seconds"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .twentyMinutes: "20 minutes"
        }
    }

    var shortTitle: String {
        switch self {
        case .twentySeconds: "20s"
        case .thirtySeconds: "30s"
        case .sixtySeconds: "60s"
        case .twoMinutes: "2m"
        case .fiveMinutes: "5m"
        case .tenMinutes: "10m"
        case .twentyMinutes: "20m"
        }
    }

    var durationSeconds: Int {
        switch self {
        case .twentySeconds: 20
        case .thirtySeconds: 30
        case .sixtySeconds: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .twentyMinutes: 1_200
        }
    }

    var injectedFixtureFileName: String? {
        switch self {
        case .twentySeconds: "fdr-day-of-infamy-20s"
        case .thirtySeconds: "fdr-day-of-infamy-30s"
        case .sixtySeconds: "fdr-day-of-infamy-60s"
        case .twoMinutes, .fiveMinutes, .tenMinutes, .twentyMinutes: nil
        }
    }

    var supportsInjectedFixture: Bool {
        injectedFixtureFileName != nil
    }
}
