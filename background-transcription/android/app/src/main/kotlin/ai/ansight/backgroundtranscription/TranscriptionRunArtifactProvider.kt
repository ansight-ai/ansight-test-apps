package ai.ansight.backgroundtranscription

import ai.ansight.runtime.AndroidArtifactDefinition
import ai.ansight.runtime.AndroidArtifactMetadata
import ai.ansight.runtime.AndroidArtifactProvider
import ai.ansight.runtime.AndroidArtifactProviderDescriptor
import ai.ansight.runtime.AndroidArtifactQueryContext
import ai.ansight.runtime.AndroidArtifactRequest
import ai.ansight.runtime.AndroidArtifactResult

class TranscriptionRunArtifactProvider(
    private val runStore: RunStore,
) : AndroidArtifactProvider {
    override val descriptor = AndroidArtifactProviderDescriptor(
        id = PROVIDER_ID,
        name = "Background transcription runs",
        description = "Exports the immutable JSON result for a terminal background transcription run.",
        category = "transcription",
    )

    override fun query(context: AndroidArtifactQueryContext): List<AndroidArtifactDefinition> {
        val run = runStore.load()
        return listOf(
            AndroidArtifactDefinition(
                id = ARTIFACT_ID,
                name = "Transcript result",
                description = "The saved transcript, run metadata, background-state evidence, and terminal status.",
                kind = "report",
                category = "transcription",
                mimeType = "application/json",
                fileName = "transcription-result.json",
                estimatedSizeBytes = runStore.resultFile.takeIf { it.isFile }?.length(),
                tags = listOf("background", "speech", "transcript"),
                metadata = mapOf(
                    "latestRunId" to run.id,
                    "phase" to run.phase.wireName,
                    "platform" to run.platform,
                ),
            ),
        )
    }

    override fun create(request: AndroidArtifactRequest): AndroidArtifactResult {
        require(request.providerId == PROVIDER_ID && request.artifactId == ARTIFACT_ID) {
            "The transcript artifact request is invalid."
        }
        val requestedRunId = request.arguments["runId"].orEmpty()
        require(requestedRunId.isNotBlank()) { "A runId is required." }

        val run = runStore.load()
        require(run.id == requestedRunId && run.phase.isTerminal) {
            "The requested terminal transcription run is no longer available."
        }
        val bytes = runStore.resultFile.readBytes()
        return AndroidArtifactResult(
            metadata = AndroidArtifactMetadata(
                providerId = request.providerId,
                artifactId = request.artifactId,
                name = "Transcript result ${run.expectedDurationSeconds}s",
                kind = "report",
                mimeType = "application/json",
                fileName = "transcription-${run.expectedDurationSeconds}s-${run.id}.json",
                sizeBytes = bytes.size.toLong(),
                description = "Terminal ${run.platform} background transcription result (${run.phase.wireName}).",
                tags = listOf("background", "speech", "transcript"),
                metadata = mapOf(
                    "runId" to run.id,
                    "platform" to run.platform,
                    "audioSource" to run.audioSource.wireName,
                    "fixtureFileName" to run.fixtureFileName,
                    "backgroundedDuringRun" to run.backgroundedDuringRun.toString(),
                ),
            ),
            bytes = bytes,
        )
    }

    companion object {
        const val PROVIDER_ID = "background-transcription.runs"
        const val ARTIFACT_ID = "transcript-result"
    }
}
