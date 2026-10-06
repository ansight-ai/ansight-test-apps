package ai.ansight.motionharness

import kotlin.math.abs

/** Tracks a sign-changing X-axis shake independently of Android UI and sensor APIs. */
internal class MotionTracker {
    var sampleCount: Int = 0
        private set
    var shakeCount: Int = 0
        private set
    var customSampleObserved: Boolean = false
        private set

    private var pulseCount = 0
    private var lastPulseSign = 0
    private var lastPulseTimestampNs = 0L

    fun observe(x: Float, timestampNs: Long) {
        sampleCount++
        if (abs(x) >= CUSTOM_SAMPLE_THRESHOLD) customSampleObserved = true

        val sign = when {
            x >= SHAKE_THRESHOLD -> 1
            x <= -SHAKE_THRESHOLD -> -1
            else -> 0
        }
        if (sign == 0 || sign == lastPulseSign) return

        if (lastPulseTimestampNs == 0L || timestampNs - lastPulseTimestampNs > SHAKE_WINDOW_NS) {
            pulseCount = 0
        }
        lastPulseSign = sign
        lastPulseTimestampNs = timestampNs
        pulseCount++
        if (pulseCount >= 4) {
            shakeCount++
            pulseCount = 0
        }
    }

    fun reset() {
        sampleCount = 0
        shakeCount = 0
        customSampleObserved = false
        pulseCount = 0
        lastPulseSign = 0
        lastPulseTimestampNs = 0L
    }

    private companion object {
        const val SHAKE_THRESHOLD = 15f
        const val CUSTOM_SAMPLE_THRESHOLD = 28f
        const val SHAKE_WINDOW_NS = 1_500_000_000L
    }
}
