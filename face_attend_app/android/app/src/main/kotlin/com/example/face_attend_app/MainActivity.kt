package com.example.face_attend_app

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.FloatBuffer
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val channelName = "face_attend_app/arcface"
    private var arcFace: ArcFaceRunner? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "embed" -> {
                    try {
                        val imageBytes = call.argument<ByteArray>("imageBytes")
                            ?: throw IllegalArgumentException("imageBytes is required")
                        val landmarks = call.argument<Map<String, Any>>("landmarks")
                            ?: throw IllegalArgumentException("landmarks are required")
                        val runner = arcFace ?: ArcFaceRunner(assets, cacheDir).also { arcFace = it }
                        result.success(runner.embed(imageBytes, landmarks))
                    } catch (error: Throwable) {
                        result.error("arcface_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

private class ArcFaceRunner(private val assets: AssetManager, private val cacheDir: File) {
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val session: OrtSession by lazy {
        env.createSession(modelFile().absolutePath, OrtSession.SessionOptions())
    }

    fun embed(imageBytes: ByteArray, landmarks: Map<String, Any>): List<Double> {
        val source = decodeOrientedBitmap(imageBytes)
        val aligned = alignFace(source, landmarks)
        val input = preprocess(aligned)
        val tensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(input), longArrayOf(1, 3, 112, 112))
        tensor.use {
            session.run(mapOf("input.1" to tensor)).use { output ->
                val raw = output[0].value
                val values = when (raw) {
                    is Array<*> -> (raw[0] as FloatArray)
                    is FloatArray -> raw
                    else -> throw IllegalStateException("Unexpected ArcFace output ${raw::class.java}")
                }
                return normalize(values).map { it.toDouble() }
            }
        }
    }

    private fun modelFile(): File {
        val file = File(contextCacheDir(), "w600k_r50.onnx")
        if (file.exists() && file.length() > 0) return file
        assets.open("flutter_assets/assets/models/w600k_r50.onnx").use { input ->
            FileOutputStream(file).use { output -> input.copyTo(output) }
        }
        return file
    }

    private fun contextCacheDir(): File {
        val dir = File(cacheDir, "face_attend_arcface")
        dir.mkdirs()
        return dir
    }

    private fun decodeOrientedBitmap(imageBytes: ByteArray): Bitmap {
        val decoded = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: throw IllegalArgumentException("Could not decode image")
        val orientation = try {
            ExifInterface(ByteArrayInputStream(imageBytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Throwable) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(-90f)
            else -> return decoded
        }
        return Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
    }

    private fun alignFace(source: Bitmap, landmarks: Map<String, Any>): Bitmap {
        val src = floatArrayOf(
            pointX(landmarks, "leftEye"), pointY(landmarks, "leftEye"),
            pointX(landmarks, "rightEye"), pointY(landmarks, "rightEye"),
            pointX(landmarks, "nose"), pointY(landmarks, "nose"),
            pointX(landmarks, "mouthLeft"), pointY(landmarks, "mouthLeft"),
            pointX(landmarks, "mouthRight"), pointY(landmarks, "mouthRight"),
        )
        val dst = floatArrayOf(
            38.2946f, 51.6963f,
            73.5318f, 51.5014f,
            56.0252f, 71.7366f,
            41.5493f, 92.3655f,
            70.7299f, 92.2041f,
        )
        val matrix = similarityTransform(src, dst)
        val output = Bitmap.createBitmap(112, 112, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(source, matrix, paint)
        return output
    }

    private fun similarityTransform(src: FloatArray, dst: FloatArray): Matrix {
        val count = src.size / 2
        var srcCx = 0f
        var srcCy = 0f
        var dstCx = 0f
        var dstCy = 0f
        for (i in 0 until count) {
            srcCx += src[i * 2]
            srcCy += src[i * 2 + 1]
            dstCx += dst[i * 2]
            dstCy += dst[i * 2 + 1]
        }
        srcCx /= count
        srcCy /= count
        dstCx /= count
        dstCy /= count

        var den = 0f
        var aNum = 0f
        var bNum = 0f
        for (i in 0 until count) {
            val sx = src[i * 2] - srcCx
            val sy = src[i * 2 + 1] - srcCy
            val dx = dst[i * 2] - dstCx
            val dy = dst[i * 2 + 1] - dstCy
            den += sx * sx + sy * sy
            aNum += sx * dx + sy * dy
            bNum += sx * dy - sy * dx
        }
        if (den <= 1e-6f) throw IllegalArgumentException("Invalid face landmarks")

        val a = aNum / den
        val b = bNum / den
        val tx = dstCx - a * srcCx + b * srcCy
        val ty = dstCy - b * srcCx - a * srcCy
        val matrix = Matrix()
        matrix.setValues(
            floatArrayOf(
                a, -b, tx,
                b, a, ty,
                0f, 0f, 1f,
            )
        )
        return matrix
    }

    private fun preprocess(bitmap: Bitmap): FloatArray {
        val input = FloatArray(1 * 3 * 112 * 112)
        val pixels = IntArray(112 * 112)
        bitmap.getPixels(pixels, 0, 112, 0, 0, 112, 112)
        var pixelIndex = 0
        for (y in 0 until 112) {
            for (x in 0 until 112) {
                val pixel = pixels[pixelIndex++]
                val r = ((pixel shr 16) and 0xff).toFloat()
                val g = ((pixel shr 8) and 0xff).toFloat()
                val b = (pixel and 0xff).toFloat()
                val offset = y * 112 + x
                input[offset] = (r - 127.5f) / 127.5f
                input[112 * 112 + offset] = (g - 127.5f) / 127.5f
                input[2 * 112 * 112 + offset] = (b - 127.5f) / 127.5f
            }
        }
        return input
    }

    private fun normalize(values: FloatArray): FloatArray {
        var norm = 0.0
        for (value in values) norm += (value * value).toDouble()
        norm = sqrt(norm).coerceAtLeast(1e-12)
        return FloatArray(values.size) { index -> (values[index] / norm).toFloat() }
    }

    @Suppress("UNCHECKED_CAST")
    private fun pointX(points: Map<String, Any>, key: String): Float {
        val point = points[key] as? Map<String, Any>
            ?: throw IllegalArgumentException("$key is required")
        return (point["x"] as Number).toFloat()
    }

    @Suppress("UNCHECKED_CAST")
    private fun pointY(points: Map<String, Any>, key: String): Float {
        val point = points[key] as? Map<String, Any>
            ?: throw IllegalArgumentException("$key is required")
        return (point["y"] as Number).toFloat()
    }
}
