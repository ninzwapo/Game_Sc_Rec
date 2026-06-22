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
    private val CHANNEL = "com.example.game_recorder/monitor"
    private val PROJECTION_REQUEST = 1001

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var pendingResult: MethodChannel.Result? = null
    private var isReadingPercent = false

    // Regex to find percentage like ▲18% or ▼-5.3% or +18% or -5%
    private val pctPattern =
        Pattern.compile("[▲▼+\\-]?\\s*(\\d{1,3}(?:\\.\\d{1,2})?)\\s*%")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readChartPercent" -> {
                    if (mediaProjection == null) {
                        // Request permission first
                        pendingResult = result
                        startActivityForResult(
                            projectionManager!!.createScreenCaptureIntent(),
                            PROJECTION_REQUEST
                        )
                    } else {
                        captureAndReadPercent(result)
                    }
                }
                "autoTap" -> {
                    val direction = call.argument<String>("direction") ?: "up"
                    // Auto tap requires Accessibility Service
                    // For now just acknowledge
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PROJECTION_REQUEST && resultCode == Activity.RESULT_OK && data != null) {
            mediaProjection =
                projectionManager!!.getMediaProjection(resultCode, data)
            pendingResult?.let { captureAndReadPercent(it) }
            pendingResult = null
        } else {
            pendingResult?.success(null)
            pendingResult = null
        }
    }

    private fun captureAndReadPercent(result: MethodChannel.Result) {
        if (isReadingPercent) {
            result.success(null)
            return
        }
        isReadingPercent = true

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        wm.defaultDisplay.getMetrics(metrics)

        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        imageReader?.close()
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        virtualDisplay?.release()
        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "ScreenCapture",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null, null
        )

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val image: Image? = imageReader!!.acquireLatestImage()
                if (image == null) {
                    isReadingPercent = false
                    result.success(null)
                    return@postDelayed
                }

                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * width

                val bitmap = Bitmap.createBitmap(
                    width + rowPadding / pixelStride,
                    height,
                    Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)
                image.close()

                // Crop top-center area where the % is shown
                // Based on 747live layout: % is roughly top 40% center
                val cropX = (width * 0.2).toInt()
                val cropY = (height * 0.05).toInt()
                val cropW = (width * 0.6).toInt()
                val cropH = (height * 0.45).toInt()

                val cropped = Bitmap.createBitmap(bitmap, cropX, cropY, cropW, cropH)
                bitmap.recycle()

                val inputImage = InputImage.fromBitmap(cropped, 0)
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

                recognizer.process(inputImage)
                    .addOnSuccessListener { visionText ->
                        isReadingPercent = false
                        virtualDisplay?.release()

                        val text = visionText.text
                        val pct = extractPercent(text)
                        result.success(pct)
                    }
                    .addOnFailureListener {
                        isReadingPercent = false
                        virtualDisplay?.release()
                        result.success(null)
                    }

            } catch (e: Exception) {
                isReadingPercent = false
                virtualDisplay?.release()
                result.success(null)
            }
        }, 300)
    }

    private fun extractPercent(text: String): Double? {
        // Look for the main chart percentage
        // 747live shows it prominently as ▲18% or ▼-5%
        val lines = text.lines()

        for (line in lines) {
            val matcher = pctPattern.matcher(line)
            while (matcher.find()) {
                val numStr = matcher.group(1) ?: continue
                val num = numStr.toDoubleOrNull() ?: continue

                // Determine sign
                val hasDown = line.contains('▼') || line.contains('-')
                val value = if (hasDown) -num else num

                // Filter out unrealistic values (chart % is usually -100 to +100)
                if (value.isFinite() && Math.abs(value) <= 100) {
                    return value
                }
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
