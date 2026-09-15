package ai.ansight.backgroundtranscription

import ai.ansight.Ansight
import ai.ansight.runtime.AnsightRuntime
import ai.ansight.runtime.HostConnectionStatusSubscription
import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.ProgressBar
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
    private lateinit var runStore: RunStore
    private lateinit var startButton: Button
    private lateinit var phaseValue: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var resultValue: TextView
    private lateinit var sourceSpinner: Spinner
    private lateinit var durationSpinner: Spinner
    private lateinit var enrollmentStatus: TextView
    private lateinit var scanEnrollmentButton: Button
    private lateinit var clearEnrollmentButton: Button
    private var connectionMessage = ""
    private var connectionStatusSubscription: HostConnectionStatusSubscription? = null
    private var availableDurations = RecordingDuration.values().filter { it.supportsInjectedFixture }

    private val runPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        val allGranted = requiredRunPermissions().all { permission ->
            grants[permission] == true ||
                ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) {
            startRun()
        } else {
            Toast.makeText(this, "Notification and microphone permissions are required for this mode.", Toast.LENGTH_LONG).show()
        }
    }

    private val runUpdateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            render()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        runStore = RunStore(this)
        startButton = findViewById(R.id.startButton)
        phaseValue = findViewById(R.id.phaseValue)
        progressBar = findViewById(R.id.progressBar)
        resultValue = findViewById(R.id.resultValue)
        sourceSpinner = findViewById(R.id.sourceSpinner)
        durationSpinner = findViewById(R.id.fixtureSpinner)
        enrollmentStatus = findViewById(R.id.enrollmentStatus)
        scanEnrollmentButton = findViewById(R.id.scanEnrollmentButton)
        clearEnrollmentButton = findViewById(R.id.clearEnrollmentButton)
        sourceSpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            TranscriptionSource.values().map { it.title },
        )
        sourceSpinner.setSelection(TranscriptionSource.InjectedFixture.ordinal)
        sourceSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                configureDurationSpinner()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
        configureDurationSpinner()
        startButton.setOnClickListener {
            val run = runStore.load()
            if (run.phase != TranscriptionPhase.Idle && !run.phase.isTerminal) {
                stopRun()
            } else {
                requestPermissionsAndStart()
            }
        }
        findViewById<Button>(R.id.refreshButton).setOnClickListener { render() }
        scanEnrollmentButton.setOnClickListener { scanEnrollmentQr() }
        clearEnrollmentButton.setOnClickListener { clearEnrollment() }
        render()
    }

    override fun onStart() {
        super.onStart()
        ContextCompat.registerReceiver(
            this,
            runUpdateReceiver,
            IntentFilter(TranscriptionService.ACTION_RUN_UPDATED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        connectionStatusSubscription = Ansight.addHostConnectionStatusListener(
            listener = { _, _ -> runOnUiThread { renderEnrollment() } },
        )
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    override fun onStop() {
        connectionStatusSubscription?.close()
        connectionStatusSubscription = null
        unregisterReceiver(runUpdateReceiver)
        super.onStop()
    }

    private fun scanEnrollmentQr() {
        scanEnrollmentButton.isEnabled = false
        connectionMessage = getString(R.string.opening_enrollment_scanner)
        renderEnrollment()
        Ansight.enrollFromQrCode(
            activity = this,
            clientName = "Background Transcription Android",
            expectedAppId = packageName,
            onResult = { result ->
                runOnUiThread {
                    connectionMessage = result.message
                    scanEnrollmentButton.isEnabled = true
                    renderEnrollment()
                }
            },
            onError = { error ->
                runOnUiThread {
                    connectionMessage = error.message ?: getString(R.string.enrollment_failed)
                    scanEnrollmentButton.isEnabled = true
                    renderEnrollment()
                }
            },
        )
    }

    private fun clearEnrollment() {
        val clearResult = AnsightRuntime.clearSavedPairingConfig()
        AnsightRuntime.clearCachedSession()
        connectionMessage = clearResult.message
        renderEnrollment()
    }

    private fun requestPermissionsAndStart() {
        val missing = requiredRunPermissions().filter { permission ->
            ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            startRun()
        } else {
            runPermissions.launch(missing.toTypedArray())
        }
    }

    private fun requiredRunPermissions(): List<String> = buildList {
        add(Manifest.permission.POST_NOTIFICATIONS)
        if (selectedSource() == TranscriptionSource.DeviceMicrophone) {
            add(Manifest.permission.RECORD_AUDIO)
        }
    }

    private fun selectedSource(): TranscriptionSource =
        TranscriptionSource.values()[sourceSpinner.selectedItemPosition]

    private fun startRun() {
        val existing = runStore.load()
        if (existing.phase != TranscriptionPhase.Idle && !existing.phase.isTerminal) return
        val duration = availableDurations[durationSpinner.selectedItemPosition]
        val run = runStore.begin(duration, selectedSource())
        AnsightTelemetry.record("background_transcription.scheduled", run)
        CaptureValidationNetworkProbe.run(run.id)
        render()
        runCatching {
            ContextCompat.startForegroundService(
                this,
                Intent(this, TranscriptionService::class.java).apply {
                    action = TranscriptionService.ACTION_START
                    putExtra(TranscriptionService.EXTRA_RUN_ID, run.id)
                },
            )
        }.onFailure { error ->
            runStore.update(
                runId = run.id,
                phase = TranscriptionPhase.Failed,
                error = "Could not start media-processing service: ${error.message}",
            )?.let { failedRun ->
                AnsightTelemetry.record("background_transcription.failed", failedRun)
            }
            render()
        }
    }

    private fun stopRun() {
        startService(
            Intent(this, TranscriptionService::class.java).apply {
                action = TranscriptionService.ACTION_STOP
            },
        )
    }

    private fun render() {
        val run = runStore.load()
        renderEnrollment()
        phaseValue.text = getString(R.string.phase_format, run.phase.wireName)
        progressBar.progress = run.progressPercent
        val isRunActive = run.phase != TranscriptionPhase.Idle && !run.phase.isTerminal
        startButton.isEnabled = true
        startButton.setText(
            if (isRunActive) R.string.stop_background_transcription else R.string.start_background_transcription,
        )
        durationSpinner.isEnabled = !isRunActive
        sourceSpinner.isEnabled = !isRunActive
        resultValue.text = buildString {
            appendLine("Progress: ${run.progressPercent}%")
            appendLine("Backgrounded: ${if (run.backgroundedDuringRun) "yes" else "no"}")
            appendLine("Audio source: ${run.audioSource.wireName}")
            appendLine(
                if (run.audioSource == TranscriptionSource.DeviceMicrophone) {
                    "Input: Device microphone"
                } else {
                    "Fixture: ${run.fixtureFileName}"
                },
            )
            appendLine("Audio duration: ${run.expectedDurationSeconds}s")
            appendLine("Run ID: ${run.id}")
            appendLine("Started: ${run.startedAt}")
            appendLine("Updated: ${run.updatedAt}")
            appendLine("Transcript: ${run.transcript.ifBlank { "—" }}")
            if (run.error != null) appendLine("Error: ${run.error}")
            append("Result file: ${runStore.resultFile.absolutePath}")
        }
    }

    private fun renderEnrollment() {
        val status = AnsightRuntime.hostConnectionStatus()
        enrollmentStatus.text = buildString {
            appendLine("State: ${status.summaryMessage}")
            appendLine("Registration: ${if (status.hasSavedConfig) "Enrolled" else "Not enrolled"}")
            append("Connection: ${if (status.isConnected) "Connected" else "Disconnected"}")
            if (connectionMessage.isNotBlank()) append("\n$connectionMessage")
        }
        clearEnrollmentButton.isEnabled = status.hasSavedConfig || status.hasCachedSession
    }

    private fun configureDurationSpinner() {
        val previousSelection = availableDurations.getOrNull(durationSpinner.selectedItemPosition)
        availableDurations = if (selectedSource() == TranscriptionSource.DeviceMicrophone) {
            RecordingDuration.values().toList()
        } else {
            RecordingDuration.values().filter { it.supportsInjectedFixture }
        }
        durationSpinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            availableDurations.map { it.title },
        )
        val selectedDuration = previousSelection
            ?.takeIf { it in availableDurations }
            ?: RecordingDuration.SixtySeconds
        durationSpinner.setSelection(availableDurations.indexOf(selectedDuration))
    }
}
