package ai.ansight.backgroundtranscription

import ai.ansight.runtime.AnsightEventType
import ai.ansight.runtime.AnsightRuntime
import android.util.Log
import org.json.JSONObject

object AnsightTelemetry {
    const val PROGRESS_CHANNEL = 40
    const val TERMINAL_EVENT_LABEL = "background_transcription.terminal"

    fun record(label: String, run: TranscriptionRun) {
        val details = JSONObject()
            .put("schema", "ansight.background-transcription-terminal/v1")
            .put("runId", run.id)
            .put("platform", run.platform)
            .put("audioSource", run.audioSource.wireName)
            .put("fixtureFileName", run.fixtureFileName)
            .put("expectedDurationSeconds", run.expectedDurationSeconds)
            .put("phase", run.phase.wireName)
            .put("progressPercent", run.progressPercent)
            .put("backgroundedDuringRun", run.backgroundedDuringRun)
            .put("transcript", run.transcript)
            .put("error", run.error ?: "")
            .put("providerId", TranscriptionRunArtifactProvider.PROVIDER_ID)
            .put("resultArtifactId", TranscriptionRunArtifactProvider.ARTIFACT_ID)
            .toString()
        runCatching {
            AnsightRuntime.metric(run.progressPercent.toLong(), PROGRESS_CHANNEL)
            AnsightRuntime.event(
                label = label,
                type = if (run.phase == TranscriptionPhase.Failed || run.phase == TranscriptionPhase.Expired || run.phase == TranscriptionPhase.Interrupted) {
                    AnsightEventType.Error
                } else {
                    AnsightEventType.Info
                },
                details = details,
                externalId = run.id,
            )
            if (run.phase.isTerminal && label != TERMINAL_EVENT_LABEL) {
                AnsightRuntime.event(
                    label = TERMINAL_EVENT_LABEL,
                    type = if (run.phase == TranscriptionPhase.Failed || run.phase == TranscriptionPhase.Expired || run.phase == TranscriptionPhase.Interrupted) {
                        AnsightEventType.Error
                    } else {
                        AnsightEventType.Info
                    },
                    details = details,
                    externalId = run.id,
                )
            }
        }
        val emittedLabels = if (run.phase.isTerminal && label != TERMINAL_EVENT_LABEL) {
            listOf(label, TERMINAL_EVENT_LABEL)
        } else {
            listOf(label)
        }
        emittedLabels.forEach { emittedLabel ->
            val logLine = "$emittedLabel runId=${run.id} phase=${run.phase.wireName} progress=${run.progressPercent}%"
            Log.i("BackgroundTranscript", logLine)
            AnsightRuntime.sendClientLog(logLine)
        }
    }
}
