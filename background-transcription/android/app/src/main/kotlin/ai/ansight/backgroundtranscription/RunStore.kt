package ai.ansight.backgroundtranscription

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.UUID

class RunStore(context: Context) {
    val resultFile = File(context.filesDir, "background-transcription/latest.json")

    @Synchronized
    fun begin(duration: RecordingDuration, source: TranscriptionSource): TranscriptionRun {
        val now = Instant.now().toString()
        val run = TranscriptionRun(
            id = UUID.randomUUID().toString(),
            platform = "Android",
            audioSource = source,
            fixtureFileName = if (source == TranscriptionSource.DeviceMicrophone) {
                "device-microphone"
            } else {
                requireNotNull(duration.injectedFixtureFileName)
            },
            expectedDurationSeconds = duration.durationSeconds,
            startedAt = now,
            updatedAt = now,
            phase = TranscriptionPhase.Scheduled,
            progressPercent = 0,
            backgroundedDuringRun = false,
            transcript = "",
            error = null,
        )
        save(run)
        return run
    }

    @Synchronized
    fun load(): TranscriptionRun = runCatching {
        TranscriptionRun.fromJson(JSONObject(resultFile.readText()))
    }.getOrDefault(TranscriptionRun.empty())

    @Synchronized
    fun update(
        runId: String,
        phase: TranscriptionPhase? = null,
        progressPercent: Int? = null,
        backgroundedDuringRun: Boolean? = null,
        transcript: String? = null,
        error: String? = null,
    ): TranscriptionRun? {
        val current = load()
        if (current.id != runId || current.phase.isTerminal) return null
        val updated = current.copy(
            updatedAt = Instant.now().toString(),
            phase = phase ?: current.phase,
            progressPercent = progressPercent ?: current.progressPercent,
            backgroundedDuringRun = backgroundedDuringRun ?: current.backgroundedDuringRun,
            transcript = transcript ?: current.transcript,
            error = error ?: current.error,
        )
        save(updated)
        return updated
    }

    @Synchronized
    fun save(run: TranscriptionRun) {
        resultFile.parentFile?.mkdirs()
        val temporary = File(resultFile.parentFile, "latest.json.tmp")
        temporary.writeText(run.toJson().toString(2))
        if (!temporary.renameTo(resultFile)) {
            temporary.copyTo(resultFile, overwrite = true)
            temporary.delete()
        }
    }
}
