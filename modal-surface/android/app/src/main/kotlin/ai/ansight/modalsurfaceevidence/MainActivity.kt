package ai.ansight.modalsurfaceevidence

import ai.ansight.Ansight
import ai.ansight.runtime.AndroidUiEvidence
import ai.ansight.runtime.AnsightSessionJpegCaptureMode
import ai.ansight.runtime.AnsightSessionJpegCaptureOptions
import android.app.Activity
import android.app.Dialog
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import org.json.JSONObject

/** Reproduces the separate modal window and SurfaceView overlay from the Redpoint viewer. */
class MainActivity : Activity() {
    private var modal: Dialog? = null
    private var overlayTaps = 0
    private var sceneGestures = 0
    private var sdkTouchDowns = 0
    private var sdkTouchMoves = 0
    private var sdkTouchUps = 0
    private var touchObserver: AutoCloseable? = null
    private var touchEvidence: TextView? = null
    private var interactionEvidence: TextView? = null
    private var treeEvidence: TextView? = null
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setBackgroundColor(Color.rgb(21, 30, 46))
        }
        root.addView(label("Modal Surface Evidence", 24f, Color.WHITE))
        root.addView(label("Open the modal, tap its yellow button, drag the surface scene, then inspect Ansight touches and screenshots.", 16f, Color.LTGRAY))
        root.addView(button("OPEN MODAL") { showModal() })
        status = label("Modal closed", 16f, Color.WHITE)
        root.addView(status)
        setContentView(root)

        touchObserver = AndroidUiEvidence.addTouchObserver { touch ->
            if (modal?.isShowing == true) {
                when (touch.action) {
                    "Down" -> sdkTouchDowns++
                    "Move" -> sdkTouchMoves++
                    "Up" -> sdkTouchUps++
                }
                touchEvidence?.text = "SDK touch: Down=$sdkTouchDowns Move=$sdkTouchMoves Up=$sdkTouchUps last=(${touch.x.toInt()}, ${touch.y.toInt()})"
                if (touch.action == "Down") {
                    status.post { captureVisualTreeOnTouch(touch.capturedAtUtc) }
                }
            }
        }

        val options = Ansight.developerOptions(clientName = "Modal Surface Evidence")
        Ansight.initializeAndActivate(
            application = application,
            options = options.copy(
                sessionJpegCapture = AnsightSessionJpegCaptureOptions(
                    intervalMilliseconds = 1_000,
                    quality = 85,
                    maxWidth = 720,
                    mode = AnsightSessionJpegCaptureMode.ScreenshotWithVisualTreeOnTouch,
                ),
            ),
        )
        if (intent.getBooleanExtra(EXTRA_OPEN_MODAL, false)) root.post { showModal() }
    }

    override fun onDestroy() {
        modal?.dismiss()
        modal = null
        touchObserver?.close()
        touchObserver = null
        super.onDestroy()
    }

    private fun showModal() {
        if (modal?.isShowing == true) return
        val scene = SurfaceView(this).apply {
            holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) = drawScene(holder)
                override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = drawScene(holder)
                override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
            })
            setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_UP) {
                    sceneGestures++
                    updateState()
                }
                true
            }
        }
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(scene, FrameLayout.LayoutParams(-1, -1))
        }
        val overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setBackgroundColor(Color.rgb(255, 221, 0))
            elevation = dp(8).toFloat()
        }
        overlay.addView(label("YELLOW OVERLAY MUST BE VISIBLE", 16f, Color.BLACK))
        interactionEvidence = label("overlay taps: $overlayTaps | scene gestures: $sceneGestures", 15f, Color.BLACK)
        overlay.addView(interactionEvidence)
        sdkTouchDowns = 0
        sdkTouchMoves = 0
        sdkTouchUps = 0
        touchEvidence = label("SDK touch: Down=0 Move=0 Up=0", 14f, Color.BLACK)
        overlay.addView(touchEvidence)
        overlay.addView(button("TAP OVERLAY") {
            overlayTaps++
            updateState()
        })
        val screenshotEvidence = label("Screenshot: not captured", 14f, Color.BLACK)
        overlay.addView(screenshotEvidence)
        overlay.addView(button("SAVE ANSIGHT PNG") {
            val result = runCatching {
                val shot = AndroidUiEvidence.captureScreenshot("png", 100, 720)
                val file = File(filesDir, "modal-surface-evidence.png")
                file.writeBytes(shot.bytes)
                val bitmap = BitmapFactory.decodeByteArray(shot.bytes, 0, shot.bytes.size)
                val rootView = window.decorView.rootView
                val rootLocation = IntArray(2).also(rootView::getLocationOnScreen)
                val scale = shot.width.toFloat() / rootView.width
                fun colorAt(view: android.view.View, x: Float, y: Float): Int {
                    val location = IntArray(2).also(view::getLocationOnScreen)
                    val px = ((location[0] + view.width * x - rootLocation[0]) * scale).toInt().coerceIn(0, bitmap.width - 1)
                    val py = ((location[1] + view.height * y - rootLocation[1]) * scale).toInt().coerceIn(0, bitmap.height - 1)
                    return bitmap.getPixel(px, py)
                }
                val yellow = colorAt(overlay, 0.01f, 0.01f).let { Color.red(it) > 200 && Color.green(it) > 150 && Color.blue(it) < 80 }
                val blue = colorAt(scene, 0.05f, 0.95f).let { Color.red(it) < 80 && Color.blue(it) > 120 }
                val pink = colorAt(scene, 0.5f, 0.75f).let { Color.red(it) > 150 && Color.green(it) < 80 && Color.blue(it) > 80 }
                bitmap.recycle()
                "Screenshot: ${if (yellow && blue && pink) "PASS" else "FAIL"} yellow=$yellow blue=$blue pink=$pink (${shot.width}x${shot.height})"
            }.getOrElse { error -> "Capture failed: ${error.message}" }
            status.text = result
            screenshotEvidence.text = result
        })
        treeEvidence = label("Auto visual tree: waiting for touch", 14f, Color.BLACK)
        overlay.addView(treeEvidence)
        overlay.addView(button("CLOSE MODAL") { modal?.dismiss() })
        root.addView(overlay, FrameLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP))

        modal = Dialog(this).apply {
            setContentView(root)
            window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setOnDismissListener {
                modal = null
                touchEvidence = null
                interactionEvidence = null
                treeEvidence = null
                updateState()
            }
            show()
            window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT, (resources.displayMetrics.heightPixels * 0.82f).toInt())
        }
        updateState()
    }

    private fun updateState() {
        status.text = "modal=${modal?.isShowing == true} overlay taps=$overlayTaps scene gestures=$sceneGestures"
        interactionEvidence?.text = "overlay taps: $overlayTaps | scene gestures: $sceneGestures"
    }

    private fun captureVisualTreeOnTouch(touchCapturedAtUtc: String) {
        if (modal?.isShowing != true) return
        val result = runCatching {
            val tree = AndroidUiEvidence.visualTree()
            val windows = tree.getJSONObject("root").optJSONArray("children")?.length() ?: 0
            val hasControls = tree.toString().contains("YELLOW OVERLAY MUST BE VISIBLE") &&
                tree.toString().contains("TAP OVERLAY")
            File(filesDir, "modal-visual-tree.json").writeText(
                JSONObject().put("touchCapturedAtUtc", touchCapturedAtUtc).put("visualTree", tree).toString(2),
            )
            "Auto visual tree: ${if (windows >= 2 && hasControls) "PASS" else "FAIL"} windows=$windows nodes=${tree.optInt("nodeCount")}"
        }.getOrElse { error -> "Auto visual tree: ERROR ${error.message}" }
        treeEvidence?.text = result
    }

    private fun label(text: String, size: Float, color: Int) = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        setPadding(dp(8), dp(8), dp(8), dp(8))
    }

    private fun button(text: String, action: () -> Unit) = Button(this).apply {
        this.text = text
        setOnClickListener { action() }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun drawScene(holder: SurfaceHolder) {
        val canvas: Canvas = holder.lockCanvas() ?: return
        try {
            canvas.drawColor(Color.rgb(12, 60, 170))
            val paint = Paint().apply { color = Color.rgb(229, 13, 114) }
            canvas.drawRect(canvas.width * 0.2f, canvas.height * 0.5f, canvas.width * 0.8f, canvas.height * 0.8f, paint)
        } finally {
            holder.unlockCanvasAndPost(canvas)
        }
    }

    companion object {
        const val EXTRA_OPEN_MODAL = "ai.ansight.modalsurfaceevidence.OPEN_MODAL"
    }
}
