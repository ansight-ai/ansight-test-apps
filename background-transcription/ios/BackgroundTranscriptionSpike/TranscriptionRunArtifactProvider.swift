import Ansight
import Foundation

struct TranscriptionRunArtifactProvider: AnsightArtifactProvider {
    static let providerId = "background-transcription.runs"
    static let artifactId = "transcript-result"

    let descriptor = AnsightArtifactProviderDescriptor(
        id: providerId,
        name: "Background transcription runs",
        description: "Exports the immutable JSON result for a terminal background transcription run.",
        category: "transcription",
        tags: ["background", "speech", "transcript"]
    )

    func query(context: AnsightArtifactQueryContext) throws -> [AnsightArtifactDefinition] {
        let run = RunStore.shared.load()
        let estimatedSize = (try? FileManager.default.attributesOfItem(atPath: RunStore.shared.resultURL.path)[.size] as? NSNumber)?.int64Value

        return [
            AnsightArtifactDefinition(
                id: Self.artifactId,
                name: "Transcript result",
                description: "The saved transcript, run metadata, background-state evidence, and terminal status.",
                kind: "report",
                category: "transcription",
                content: AnsightArtifactContentDescriptor(
                    supportedMimeTypes: ["application/json"],
                    defaultMimeType: "application/json",
                    suggestedFileName: "transcription-result.json",
                    supportsText: true,
                    supportsBinary: true,
                    sizeKnownBeforeCreation: estimatedSize != nil,
                    estimatedSizeBytes: estimatedSize
                ),
                tags: ["background", "speech", "transcript"],
                metadata: [
                    "latestRunId": run.id,
                    "phase": run.phase.rawValue,
                    "platform": run.platform,
                ]
            ),
        ]
    }

    func create(request: AnsightArtifactRequest) throws -> AnsightArtifactResult {
        guard request.providerId == Self.providerId,
              request.artifactId == Self.artifactId,
              let requestedRunId = request.arguments["runId"],
              !requestedRunId.isEmpty
        else {
            throw ArtifactProviderError.invalidRequest
        }

        let run = RunStore.shared.load()
        guard run.id == requestedRunId, run.phase.isTerminal else {
            throw ArtifactProviderError.runUnavailable
        }

        let path = RunStore.shared.resultURL.path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        return AnsightArtifactResult(
            metadata: AnsightArtifactMetadata(
                artifactId: request.artifactId,
                providerId: request.providerId,
                name: "Transcript result \(run.expectedDurationSeconds)s",
                kind: "report",
                mimeType: "application/json",
                fileName: "transcription-\(run.expectedDurationSeconds)s-\(run.id).json",
                description: "Terminal \(run.platform) background transcription result (\(run.phase.rawValue)).",
                sizeBytes: size,
                tags: ["background", "speech", "transcript"],
                metadata: [
                    "runId": run.id,
                    "platform": run.platform,
                    "audioSource": run.audioSource ?? TranscriptionSource.injectedFixture.rawValue,
                    "fixtureFileName": run.fixtureFileName,
                    "backgroundedDuringRun": String(run.backgroundedDuringRun),
                ]
            ),
            payload: .fromFile(path)
        )
    }
}

private enum ArtifactProviderError: LocalizedError {
    case invalidRequest
    case runUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The transcript artifact request is invalid."
        case .runUnavailable:
            return "The requested terminal transcription run is no longer available."
        }
    }
}
