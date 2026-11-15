package com.zloxtera.zloui

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.content.Context
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

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

/**
 * Android requires a RecognitionService for an assistant service, and while
 * this app is the default assistant the system also makes it the default
 * speech recognizer. So it must actually recognize speech: every request is
 * forwarded to another recognizer on the device (Google's when present).
 * Without this, voice input fails in this app and in every other app.
 */
class AssistantRecognitionService : RecognitionService() {
    private var delegate: SpeechRecognizer? = null

    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        if (listener == null) return
        val component = delegateComponent()
        if (component == null) {
            Log.w(TAG, "No other speech recognizer on this device")
            safely { listener.error(SpeechRecognizer.ERROR_CLIENT) }
            return
        }
        delegate?.destroy()
        val recognizer = SpeechRecognizer.createSpeechRecognizer(this, component)
        delegate = recognizer
        recognizer.setRecognitionListener(Forwarder(listener))
        recognizer.startListening(
            recognizerIntent ?: Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH),
        )
    }

    override fun onStopListening(listener: Callback?) {
        delegate?.stopListening()
    }

    override fun onCancel(listener: Callback?) {
        delegate?.cancel()
    }

    override fun onDestroy() {
        delegate?.destroy()
        delegate = null
        super.onDestroy()
    }

    /** Another app's recognizer, preferring Google's. */
    private fun delegateComponent(): ComponentName? {
        val services = packageManager
            .queryIntentServices(Intent(RecognitionService.SERVICE_INTERFACE), 0)
            .mapNotNull { it.serviceInfo }
            .filter { it.packageName != packageName }
        val chosen = PREFERRED_PACKAGES.firstNotNullOfOrNull { preferred ->
            services.firstOrNull { it.packageName == preferred }
        } ?: services.firstOrNull()
        return chosen?.let { ComponentName(it.packageName, it.name) }
    }

    /** Relays the delegate's events to the client that called this service. */
    private class Forwarder(private val listener: RecognitionService.Callback) : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) =
            safely { listener.readyForSpeech(params ?: Bundle()) }

        override fun onBeginningOfSpeech() = safely { listener.beginningOfSpeech() }

        override fun onRmsChanged(rmsdB: Float) = safely { listener.rmsChanged(rmsdB) }

        override fun onBufferReceived(buffer: ByteArray?) {
            if (buffer != null) safely { listener.bufferReceived(buffer) }
        }

        override fun onEndOfSpeech() = safely { listener.endOfSpeech() }

        override fun onError(error: Int) = safely { listener.error(error) }

        override fun onResults(results: Bundle?) =
            safely { listener.results(results ?: Bundle()) }

        override fun onPartialResults(partialResults: Bundle?) =
            safely { listener.partialResults(partialResults ?: Bundle()) }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private companion object {
        const val TAG = "AssistantRecognition"

        val PREFERRED_PACKAGES = listOf(
            "com.google.android.googlequicksearchbox",
            "com.google.android.as",
            "com.google.android.tts",
        )

        /** The client may have gone away; that must not crash the service. */
        inline fun safely(block: () -> Unit) {
            try {
                block()
            } catch (error: Exception) {
                Log.w(TAG, "Recognition client unreachable", error)
            }
        }
    }
}
