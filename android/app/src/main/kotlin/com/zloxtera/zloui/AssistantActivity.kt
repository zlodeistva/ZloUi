package com.zloxtera.zloui

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Floating assistant window: a transparent Activity with its own Flutter entrypoint. */
class AssistantActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "assistantMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zloui/assist")
            .setMethodCallHandler { call, result ->
                if (call.method == "openApp") {
                    startActivity(
                        Intent(this, MainActivity::class.java).apply {
                            action = Intent.ACTION_ASSIST
                            putExtra("assist", true)
                            (call.arguments as? String)?.let { putExtra("chat_id", it) }
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        }
                    )
                    result.success(null)
                    finish()
                } else {
                    result.notImplemented()
                }
            }
    }
}
