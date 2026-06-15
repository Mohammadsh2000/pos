package com.example.pos

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.pos/feedback"
    private var soundPool: SoundPool? = null
    private var soundId: Int = 0
    private var loaded = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        soundPool = SoundPool.Builder()
            .setMaxStreams(3)
            .setAudioAttributes(attrs)
            .build()
        soundPool?.setOnLoadCompleteListener { _, _, status ->
            loaded = (status == 0)
        }
        soundId = soundPool!!.load(this, R.raw.scan_beep, 1)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> {
                        result.success(true)
                    }
                    "playBeep" -> {
                        if (loaded && soundPool != null) {
                            soundPool?.play(
                                soundId,
                                1.0f,
                                1.0f,
                                1,
                                0,
                                1.0f
                            )
                            result.success(true)
                        } else {
                            playFallbackBeep()
                            result.success(false)
                        }
                    }
                    "playError" -> {
                        if (loaded && soundPool != null) {
                            soundPool?.play(
                                soundId,
                                1.0f,
                                0.8f,
                                2,
                                0,
                                0.85f
                            )
                            result.success(true)
                        } else {
                            playFallbackBeep()
                            result.success(false)
                        }
                    }
                    "playSuccess" -> {
                        if (loaded && soundPool != null) {
                            soundPool?.play(
                                soundId,
                                1.0f,
                                1.0f,
                                1,
                                0,
                                1.2f
                            )
                            result.success(true)
                        } else {
                            playFallbackBeep()
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playFallbackBeep() {
        try {
            val mp = MediaPlayer.create(this, R.raw.scan_beep)
            mp?.setOnCompletionListener { it.release() }
            mp?.start()
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        soundPool?.release()
        soundPool = null
        super.onDestroy()
    }
}
