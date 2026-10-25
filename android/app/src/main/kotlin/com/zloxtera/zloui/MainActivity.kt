package com.zloxtera.zloui

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingAssist = false
    private var pendingChatId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zloui/assist")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeLaunch" -> {
                    result.success(mapOf("assist" to pendingAssist, "chatId" to pendingChatId))
                    pendingAssist = false
                    pendingChatId = null
                }
                "isDefaultAssistant" -> result.success(isDefaultAssistant())
                "openAssistantSettings" -> {
                    openAssistantSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        pendingAssist = isAssist(intent)
        pendingChatId = intent?.getStringExtra("chat_id")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isAssist(intent)) channel?.invokeMethod("assist", intent.getStringExtra("chat_id"))
    }

    private fun isDefaultAssistant(): Boolean {
        val setting = Settings.Secure.getString(contentResolver, "assistant") ?: return false
        return setting.startsWith("$packageName/")
    }

    private fun openAssistantSettings() {
        val candidates = listOf(
            Intent(Settings.ACTION_VOICE_INPUT_SETTINGS),
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in candidates) {
            try {
                startActivity(intent)
                return
            } catch (_: Exception) {
            }
        }
    }

    private fun isAssist(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_ASSIST || intent?.getBooleanExtra("assist", false) == true
}
