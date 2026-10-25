package com.zloxtera.zloui

import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.content.Context
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

class AssistantService : VoiceInteractionService()

class AssistantSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = AssistantSession(this)
}

class AssistantSession(context: Context) : VoiceInteractionSession(context) {
    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        val intent = Intent(context, AssistantActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        setUiEnabled(false)
        startAssistantActivity(intent)
    }

    override fun onTaskFinished(intent: Intent?, taskId: Int) {
        super.onTaskFinished(intent, taskId)
        hide()
    }
}

/** Stub: Android requires a RecognitionService for an assistant service. */
class AssistantRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        listener?.error(SpeechRecognizer.ERROR_CLIENT)
    }

    override fun onCancel(listener: Callback?) {}

    override fun onStopListening(listener: Callback?) {}
}
