package com.example.game_recorder

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.regex.Pattern

class MainActivity : FlutterActivity() {
    private val MONITOR_CHANNEL = "com.example.game_recorder/monitor"
    private val OVERLAY_CMD_CHANNEL = "com.example.game_recorder/overlay_cmd"
    private val PROJECTION_REQUEST = 1001

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var pendingResult: MethodChannel.Result? = null
    private var isReading = false

    private val pctPattern =
        Pattern.compile("[▲▼+\\-]?\\s*(\\d{1,3}(?:\\.\\d{1,2})?)\\s*%")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // Monitor channel - OCR screen reading
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, MONITOR_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readChartPercent" -> {
                    if (mediaProjection == null) {
                        pendingResult = result
                        startActivityForResult(
                            projectionManager!!.createScreenCaptureIntent(),
                            PROJECTION_REQUEST
                        )
                    } else {
                        captureAndOcr(result)
                    }
                }
                "autoTap" -> result.success(null)
                else -> result.notImplemented()
            }
        }

        // Overlay command channel - receives commands from overlay
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CMD_CHANNEL
        ).setMethodCallHandler { call, result ->
            // Commands from overlay are handled in Dart (main_screen.dart)
            // This channel just needs to exist on native side
            result.success(null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PROJECTION_REQUEST &&
            resultCode == Activity.RESULT_OK && data != null
        ) {
            mediaProjection = projectionManager!!.getMediaProjection(resultCode, data)
            pendingResult?.let { captureAndOcr(it) }
            pendingResult = null
        } else {
            pendingResult?.success(null)
            pendingResult = null
        }
    }

    private fun captureAndOcr(result: MethodChannel.Result) {
        if (isReading) { result.success(null); return }
        isReading = true

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(metrics)

        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        imageReader?.close()
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        virtualDisplay?.release()
        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "ScreenCapture", width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val image: Image? = imageReader!!.acquireLatestImage()
                if (image == null) {
                    isReading = false
                    result.success(null)
                    return@postDelayed
                }

                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * width

                val bitmap = Bitmap.createBitmap(
                    width + rowPadding / pixelStride, height,
                    Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)
                image.close()

                // Crop to the area where 747live shows the % (top center)
                val cx = (width * 0.15).toInt()
                val cy = (height * 0.05).toInt()
                val cw = (width * 0.70).toInt()
                val ch = (height * 0.50).toInt()
                val cropped = Bitmap.createBitmap(bitmap, cx, cy, cw, ch)
                bitmap.recycle()

                val inputImage = InputImage.fromBitmap(cropped, 0)
                val recognizer =
                    TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

                recognizer.process(inputImage)
                    .addOnSuccessListener { visionText ->
                        isReading = false
                        virtualDisplay?.release()
                        result.success(extractPercent(visionText.text))
                    }
                    .addOnFailureListener {
                        isReading = false
                        virtualDisplay?.release()
                        result.success(null)
                    }
            } catch (e: Exception) {
                isReading = false
                virtualDisplay?.release()
                result.success(null)
            }
        }, 300)
    }

    private fun extractPercent(text: String): Double? {
        for (line in text.lines()) {
            val matcher = pctPattern.matcher(line)
            while (matcher.find()) {
                val numStr = matcher.group(1) ?: continue
                val num = numStr.toDoubleOrNull() ?: continue
                val hasDown = line.contains('▼') ||
                    (line.contains('-') && !line.contains('▲'))
                val value = if (hasDown) -num else num
                if (value.isFinite() && Math.abs(value) <= 100) return value
            }
        }
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
    }
}
