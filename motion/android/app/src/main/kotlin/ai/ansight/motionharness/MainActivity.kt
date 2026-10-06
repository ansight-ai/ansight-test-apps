package ai.ansight.motionharness

import ai.ansight.Ansight
import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale

/** Visible evidence that the Android app, rather than just the host, received motion. */
class MainActivity : Activity(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private val tracker = MotionTracker()

    private lateinit var sensorStatus: TextView
    private lateinit var sampleCount: TextView
    private lateinit var lastSample: TextView
    private lateinit var shakeCount: TextView
    private lateinit var shakeStatus: TextView
    private lateinit var customStatus: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            setBackgroundColor(Color.rgb(18, 28, 42))
        }
        root.addView(label("Motion Harness", 25f))
        root.addView(label("Inject a shake or accelerometer sequence with an Ansight task, then check the app observations below.", 15f))
        sensorStatus = label("Sensor: waiting", 17f, R.id.motion_sensor_status).also(root::addView)
        sampleCount = label("Samples received: 0", 17f, R.id.motion_sample_count).also(root::addView)
        lastSample = label("Last acceleration: waiting", 15f, R.id.motion_last_sample).also(root::addView)
        shakeCount = label("Shake count: 0", 17f, R.id.motion_shake_count).also(root::addView)
        shakeStatus = label("Shake waiting", 17f, R.id.motion_shake_status).also(root::addView)
        customStatus = label("Custom sample waiting", 17f, R.id.motion_custom_status).also(root::addView)
        root.addView(Button(this).apply {
            id = R.id.motion_reset
            text = "RESET COUNTERS"
            setOnClickListener {
                tracker.reset()
                render(null)
            }
        })
        setContentView(root)

        Ansight.initializeAndActivate(
            application = application,
            options = Ansight.developerOptions(clientName = "Motion Harness"),
        )
        render(null)
    }

    override fun onResume() {
        super.onResume()
        accelerometer?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        sensorStatus.text = if (accelerometer == null) "Sensor unavailable" else "Sensor ready"
    }

    override fun onPause() {
        sensorManager.unregisterListener(this)
        super.onPause()
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        tracker.observe(x, event.timestamp)
        render(floatArrayOf(x, y, z))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun render(acceleration: FloatArray?) {
        sampleCount.text = "Samples received: ${tracker.sampleCount}"
        shakeCount.text = "Shake count: ${tracker.shakeCount}"
        shakeStatus.text = if (tracker.shakeCount > 0) "Shake detected" else "Shake waiting"
        customStatus.text = if (tracker.customSampleObserved) "Custom sample observed" else "Custom sample waiting"
        if (acceleration == null) {
            lastSample.text = "Last acceleration: waiting"
        } else {
            lastSample.text = String.format(Locale.US, "Last acceleration: x=%.2f y=%.2f z=%.2f m/s²",
                acceleration[0], acceleration[1], acceleration[2])
        }
    }

    private fun label(value: String, size: Float, viewId: Int = -1) = TextView(this).apply {
        id = viewId
        text = value
        textSize = size
        setTextColor(Color.WHITE)
        setPadding(0, dp(8), 0, dp(8))
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
