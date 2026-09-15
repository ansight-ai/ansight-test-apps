package ai.ansight.backgroundtranscription

import ai.ansight.Ansight
import ai.ansight.runtime.AnsightChannel
import ai.ansight.runtime.AnsightOptions
import ai.ansight.runtime.AnsightSessionJpegCaptureMode
import ai.ansight.runtime.AnsightSessionJpegCaptureOptions
import ai.ansight.runtime.AnsightToolGuard
import ai.ansight.runtime.AnsightRuntime
import android.app.Activity
import android.app.Application
import android.content.pm.ApplicationInfo
import android.os.Bundle

class SpikeApplication : Application(), Application.ActivityLifecycleCallbacks {
    private lateinit var runStore: RunStore
    private var startedActivityCount = 0

    override fun onCreate() {
        super.onCreate()
        runStore = RunStore(this)
        registerActivityLifecycleCallbacks(this)
        runCatching {
            val isDebuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
            val developerOptions = Ansight.developerOptions(
                clientName = "Background Transcription Android",
            )
            val captureOptions = developerOptions.copy(
                retentionPeriodSeconds = 300,
                enableBatteryLevel = true,
                enableOpenFileHandleTracking = true,
                additionalChannels = listOf(
                    AnsightChannel(
                        id = AnsightTelemetry.PROGRESS_CHANNEL,
                        name = "Transcription Progress",
                        colorHex = "#0A84FF",
                        unit = "%",
                        type = "progress",
                        source = "background-transcription",
                    ),
                ),
                sessionJpegCapture = if (isDebuggable) {
                    AnsightSessionJpegCaptureOptions(
                        intervalMilliseconds = 1_000,
                        quality = 70,
                        maxWidth = 720,
                        mode = AnsightSessionJpegCaptureMode.ScreenshotWithVisualTreeOnTouch,
                    )
                } else {
                    null
                },
                toolGuard = if (isDebuggable) AnsightToolGuard.FullAccess else AnsightToolGuard.Disabled,
                initialTools = if (isDebuggable) developerOptions.initialTools else emptyList(),
                artifactProviders = listOf(TranscriptionRunArtifactProvider(runStore)),
                customProperties = mapOf(
                    "spike" to mapOf(
                        "name" to "background-transcription",
                        "platform" to "android-native",
                        "backgroundPrimitive" to "mediaProcessing-foreground-service",
                        "speechPrimitive" to "SpeechRecognizer.EXTRA_AUDIO_SOURCE",
                        "captureProfile" to "full-development",
                    ),
                ),
            )
            Ansight.initializeAndActivate(
                application = this,
                options = captureOptions,
            )
            AnsightRuntime.screenViewed(
                "Background Transcription Spike",
                mapOf("route" to "/background-transcription"),
            )
        }
        reconcileInterruptedRun()
    }

    override fun onActivityStarted(activity: Activity) {
        startedActivityCount += 1
    }

    override fun onActivityStopped(activity: Activity) {
        startedActivityCount = (startedActivityCount - 1).coerceAtLeast(0)
        if (startedActivityCount == 0 && !activity.isChangingConfigurations) {
            val current = runStore.load()
            if (current.phase != TranscriptionPhase.Idle && !current.phase.isTerminal) {
                runStore.update(current.id, backgroundedDuringRun = true)?.let { updated ->
                    AnsightTelemetry.record("background_transcription.lifecycle.background", updated)
                    sendBroadcast(
                        android.content.Intent(TranscriptionService.ACTION_RUN_UPDATED).setPackage(packageName),
                    )
                }
            }
        }
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit

    private fun reconcileInterruptedRun() {
        val current = runStore.load()
        if (current.phase == TranscriptionPhase.Idle || current.phase.isTerminal) return

        runStore.update(
            runId = current.id,
            phase = TranscriptionPhase.Interrupted,
            error = "The prior foreground service stopped when the app process ended. Start a new run.",
        )?.let { interruptedRun ->
            AnsightTelemetry.record("background_transcription.interrupted", interruptedRun)
        }
    }
}
