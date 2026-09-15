package ai.ansight.backgroundtranscription

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class TranscriptionService : Service(), RecognitionListener {
    private lateinit var runStore: RunStore
    private val handler = Handler(Looper.getMainLooper())
    private var runId: String? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var audioDescriptor: ParcelFileDescriptor? = null
    private var microphoneEndsAtElapsedRealtime = 0L
    private var microphoneFinishing = false
    private var microphoneTranscriptPrefix = ""

    override fun onCreate() {
        super.onCreate()
        runStore = RunStore(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            cancelCurrentRun()
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val requestedRunId = intent?.getStringExtra(EXTRA_RUN_ID)
        if (intent?.action != ACTION_START || requestedRunId.isNullOrBlank()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (runId != null) return START_NOT_STICKY
        runId = requestedRunId
        val run = runStore.load()
        val foregroundServiceType = if (run.audioSource == TranscriptionSource.DeviceMicrophone) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
        }
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(
                if (run.audioSource == TranscriptionSource.DeviceMicrophone) {
                    "Starting microphone capture"
                } else {
                    "Preparing validation run"
                },
                1,
            ),
            foregroundServiceType,
        )
        update(TranscriptionPhase.Preparing, 1)
        if (run.audioSource == TranscriptionSource.DeviceMicrophone) {
            // Start while the activity is visible. Android allows this microphone
            // foreground service to keep recording after the app is backgrounded.
            microphoneEndsAtElapsedRealtime = SystemClock.elapsedRealtime() + run.expectedDurationSeconds * 1_000L
            microphoneFinishing = false
            microphoneTranscriptPrefix = ""
            handler.postDelayed(::finishMicrophoneInput, run.expectedDurationSeconds * 1_000L)
            startRecognition()
        } else {
            runCountdown(second = 1)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTimeout(startId: Int, fgsType: Int) {
        val currentRunId = runId
        if (currentRunId != null) {
            runStore.update(
                runId = currentRunId,
                phase = TranscriptionPhase.Expired,
                error = "Android exhausted the media-processing foreground-service time allowance.",
            )?.let { expiredRun ->
                AnsightTelemetry.record("background_transcription.expired", expiredRun)
                notifyUpdated()
            }
        }
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        speechRecognizer?.destroy()
        speechRecognizer = null
        audioDescriptor?.close()
        audioDescriptor = null
        super.onDestroy()
    }

    private fun runCountdown(second: Int) {
        if (second > VALIDATION_DELAY_SECONDS) {
            startRecognition()
            return
        }
        handler.postDelayed({
            val progress = second * 2
            update(TranscriptionPhase.Preparing, progress)
            updateNotification("Background the app now — starting in ${VALIDATION_DELAY_SECONDS - second}s", progress)
            runCountdown(second + 1)
        }, 1_000)
    }

    private fun startRecognition() {
        val currentRunId = runId ?: return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            fail("No Android speech recognition service is available.")
            return
        }

        val run = runStore.load()
        if (run.id != currentRunId) {
            fail("The durable run did not match the foreground service.")
            return
        }
        val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer = recognizer
        recognizer.setRecognitionListener(this)
        val recognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (run.audioSource == TranscriptionSource.InjectedFixture) {
                val audio = runCatching { WaveFixture.extractPcm(this@TranscriptionService, run.fixtureFileName) }
                    .getOrElse { error ->
                        fail("Could not prepare ${run.fixtureFileName}: ${error.message}")
                        return
                    }
                audioDescriptor = runCatching {
                    ParcelFileDescriptor.open(audio.file, ParcelFileDescriptor.MODE_READ_ONLY)
                }.getOrElse { error ->
                    fail("Could not open injected PCM audio: ${error.message}")
                    return
                }
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, audioDescriptor)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, audio.channelCount)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, audio.encoding)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, audio.sampleRate)
            }
        }
        update(TranscriptionPhase.Transcribing, 25)
        updateNotification(
            if (run.audioSource == TranscriptionSource.DeviceMicrophone) {
                "Speak now — microphone is recording"
            } else {
                "Injected speech recognition is running"
            },
            25,
        )
        runCatching { recognizer.startListening(recognizerIntent) }.onFailure { error ->
            fail("Could not start speech recognition for run $currentRunId: ${error.message}")
        }
    }

    override fun onReadyForSpeech(params: Bundle?) {
        update(TranscriptionPhase.Transcribing, 35)
        val source = runStore.load().audioSource
        updateNotification(
            if (source == TranscriptionSource.DeviceMicrophone) {
                "Microphone is recording"
            } else {
                "Recognizer accepted injected audio"
            },
            35,
        )
    }

    override fun onBeginningOfSpeech() {
        update(TranscriptionPhase.Transcribing, 45)
    }

    override fun onRmsChanged(rmsdB: Float) = Unit
    override fun onBufferReceived(buffer: ByteArray?) = Unit

    override fun onEndOfSpeech() {
        update(TranscriptionPhase.Transcribing, 90)
        updateNotification("Finalizing transcript", 90)
    }

    override fun onError(error: Int) {
        val run = runStore.load()
        val canRestartMicrophone = run.audioSource == TranscriptionSource.DeviceMicrophone &&
            !microphoneFinishing &&
            SystemClock.elapsedRealtime() < microphoneEndsAtElapsedRealtime &&
            error in setOf(
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
            )
        if (canRestartMicrophone) {
            restartMicrophoneRecognition()
            return
        }
        if (run.audioSource == TranscriptionSource.DeviceMicrophone &&
            microphoneFinishing &&
            run.transcript.isNotBlank()
        ) {
            complete(run.transcript)
            return
        }
        fail("Speech recognition failed: ${recognizerError(error)} ($error). The installed recognizer may not support EXTRA_AUDIO_SOURCE.")
    }

    override fun onResults(results: Bundle?) {
        val segment = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            .orEmpty()
        val run = runStore.load()
        val transcript = if (run.audioSource == TranscriptionSource.DeviceMicrophone) {
            joinTranscript(microphoneTranscriptPrefix, segment)
        } else {
            segment
        }
        if (transcript.isBlank()) {
            fail("The recognizer returned no transcript. The installed recognizer may not support injected audio.")
            return
        }
        if (run.audioSource == TranscriptionSource.DeviceMicrophone &&
            !microphoneFinishing &&
            SystemClock.elapsedRealtime() < microphoneEndsAtElapsedRealtime
        ) {
            microphoneTranscriptPrefix = transcript
            update(TranscriptionPhase.Transcribing, run.progressPercent.coerceAtLeast(65), transcript)
            restartMicrophoneRecognition()
            return
        }
        complete(transcript)
    }

    private fun complete(transcript: String) {
        val currentRunId = runId ?: return
        val run = runStore.update(
            runId = currentRunId,
            phase = TranscriptionPhase.Completed,
            progressPercent = 100,
            transcript = transcript,
        ) ?: return
        AnsightTelemetry.record("background_transcription.completed", run)
        notifyUpdated()
        updateNotification("Transcription completed", 100)
        finishService()
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val segment = partialResults
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            .orEmpty()
        val transcript = if (runStore.load().audioSource == TranscriptionSource.DeviceMicrophone) {
            joinTranscript(microphoneTranscriptPrefix, segment)
        } else {
            segment
        }
        if (transcript.isNotBlank()) {
            update(TranscriptionPhase.Transcribing, 70, transcript)
        }
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit

    private fun update(phase: TranscriptionPhase, progress: Int, transcript: String? = null) {
        val currentRunId = runId ?: return
        val run = runStore.update(
            runId = currentRunId,
            phase = phase,
            progressPercent = progress,
            transcript = transcript,
        ) ?: return
        AnsightTelemetry.record("background_transcription.phase.${phase.wireName}", run)
        notifyUpdated()
    }

    private fun fail(message: String) {
        val currentRunId = runId ?: return
        val run = runStore.update(
            runId = currentRunId,
            phase = TranscriptionPhase.Failed,
            error = message,
        ) ?: return
        AnsightTelemetry.record("background_transcription.failed", run)
        notifyUpdated()
        updateNotification("Transcription failed", run.progressPercent)
        finishService()
    }

    private fun cancelCurrentRun() {
        val activeRunId = runId ?: runStore.load().id
        handler.removeCallbacksAndMessages(null)
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
        audioDescriptor?.close()
        audioDescriptor = null
        runStore.update(
            runId = activeRunId,
            phase = TranscriptionPhase.Cancelled,
            error = "Stopped by the user.",
        )?.let { cancelledRun ->
            AnsightTelemetry.record("background_transcription.cancelled", cancelledRun)
            notifyUpdated()
        }
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }

    private fun finishMicrophoneInput() {
        val currentRunId = runId ?: return
        if (runStore.load().id != currentRunId || runStore.load().phase.isTerminal) return
        microphoneFinishing = true
        update(TranscriptionPhase.Transcribing, 90)
        updateNotification("Finalizing transcript", 90)
        speechRecognizer?.stopListening()
        handler.postDelayed({
            val run = runStore.load()
            if (run.id != currentRunId || run.phase.isTerminal) return@postDelayed
            if (run.transcript.isBlank()) {
                fail("Speech recognition did not return a transcript after microphone capture ended.")
            } else {
                complete(run.transcript)
            }
        }, 10_000)
    }

    private fun restartMicrophoneRecognition() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        handler.postDelayed({
            if (!microphoneFinishing && SystemClock.elapsedRealtime() < microphoneEndsAtElapsedRealtime) {
                startRecognition()
            }
        }, 100)
    }

    private fun joinTranscript(prefix: String, segment: String): String =
        listOf(prefix.trim(), segment.trim())
            .filter { it.isNotEmpty() }
            .joinToString(" ")

    private fun finishService() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        audioDescriptor?.close()
        audioDescriptor = null
        handler.postDelayed({
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }, 3_000)
    }

    private fun notifyUpdated() {
        sendBroadcast(Intent(ACTION_RUN_UPDATED).setPackage(packageName))
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Background transcription",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows progress for user-initiated audio processing."
            },
        )
    }

    private fun updateNotification(message: String, progress: Int) {
        getSystemService(NotificationManager::class.java).notify(
            NOTIFICATION_ID,
            buildNotification(message, progress),
        )
    }

    private fun buildNotification(message: String, progress: Int): Notification {
        val openAppIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_transcription)
            .setContentTitle("Background transcription spike")
            .setContentText(message)
            .setContentIntent(openAppIntent)
            .setOngoing(progress < 100)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, false)
            .build()
    }

    private fun recognizerError(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "audio input error"
        SpeechRecognizer.ERROR_CLIENT -> "client error"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "insufficient permissions"
        SpeechRecognizer.ERROR_NETWORK -> "network error"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network timeout"
        SpeechRecognizer.ERROR_NO_MATCH -> "no speech match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "recognizer busy"
        SpeechRecognizer.ERROR_SERVER -> "recognition service error"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "speech timeout"
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "recognition service disconnected"
        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "too many requests"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "language not supported"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "language unavailable"
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "cannot check support"
        SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS -> "cannot listen for model downloads"
        else -> "unknown recognizer error"
    }

    companion object {
        const val ACTION_START = "ai.ansight.backgroundtranscription.action.START"
        const val ACTION_STOP = "ai.ansight.backgroundtranscription.action.STOP"
        const val ACTION_RUN_UPDATED = "ai.ansight.backgroundtranscription.action.RUN_UPDATED"
        const val EXTRA_RUN_ID = "runId"
        private const val NOTIFICATION_CHANNEL_ID = "background-transcription"
        private const val NOTIFICATION_ID = 2201
        private const val VALIDATION_DELAY_SECONDS = 10
    }
}
