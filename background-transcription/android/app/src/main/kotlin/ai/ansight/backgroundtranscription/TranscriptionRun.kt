package ai.ansight.backgroundtranscription

import org.json.JSONObject
import java.time.Instant

enum class TranscriptionSource(val wireName: String, val title: String) {
    InjectedFixture("injected_fixture", "Injected speech"),
    DeviceMicrophone("device_microphone", "Device mic");

    companion object {
        fun fromWireName(value: String): TranscriptionSource =
            values().firstOrNull { it.wireName == value } ?: InjectedFixture
    }
}

enum class TranscriptionPhase(val wireName: String) {
    Idle("idle"),
    Scheduled("scheduled"),
    Preparing("preparing"),
    Transcribing("transcribing"),
    Completed("completed"),
    Cancelled("cancelled"),
    Interrupted("interrupted"),
    Failed("failed"),
    Expired("expired");

    val isTerminal: Boolean
        get() = this == Completed || this == Cancelled || this == Interrupted || this == Failed || this == Expired

    companion object {
        fun fromWireName(value: String): TranscriptionPhase =
            values().firstOrNull { it.wireName == value } ?: Idle
    }
}

data class TranscriptionRun(
    val id: String,
    val platform: String,
    val audioSource: TranscriptionSource,
    val fixtureFileName: String,
    val expectedDurationSeconds: Int,
    val startedAt: String,
    val updatedAt: String,
    val phase: TranscriptionPhase,
    val progressPercent: Int,
    val backgroundedDuringRun: Boolean,
    val transcript: String,
    val error: String?,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("platform", platform)
        .put("audioSource", audioSource.wireName)
        .put("fixtureFileName", fixtureFileName)
        .put("expectedDurationSeconds", expectedDurationSeconds)
        .put("startedAt", startedAt)
        .put("updatedAt", updatedAt)
        .put("phase", phase.wireName)
        .put("progressPercent", progressPercent)
        .put("backgroundedDuringRun", backgroundedDuringRun)
        .put("transcript", transcript)
        .put("error", error ?: JSONObject.NULL)

    companion object {
        fun empty(): TranscriptionRun {
            val now = Instant.now().toString()
            return TranscriptionRun(
                id = "none",
                platform = "Android",
                audioSource = TranscriptionSource.InjectedFixture,
                fixtureFileName = "none",
                expectedDurationSeconds = 0,
                startedAt = now,
                updatedAt = now,
                phase = TranscriptionPhase.Idle,
                progressPercent = 0,
                backgroundedDuringRun = false,
                transcript = "",
                error = null,
            )
        }

        fun fromJson(json: JSONObject): TranscriptionRun = TranscriptionRun(
            id = json.getString("id"),
            platform = json.getString("platform"),
            audioSource = TranscriptionSource.fromWireName(
                json.optString("audioSource", TranscriptionSource.InjectedFixture.wireName),
            ),
            fixtureFileName = json.getString("fixtureFileName"),
            expectedDurationSeconds = json.getInt("expectedDurationSeconds"),
            startedAt = json.getString("startedAt"),
            updatedAt = json.getString("updatedAt"),
            phase = TranscriptionPhase.fromWireName(json.getString("phase")),
            progressPercent = json.getInt("progressPercent"),
            backgroundedDuringRun = json.getBoolean("backgroundedDuringRun"),
            transcript = json.optString("transcript"),
            error = json.optString("error").takeIf { it.isNotBlank() && it != "null" },
        )
    }
}
