package com.sbarpanda.expendituretracker

import android.provider.Telephony
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.sbarpanda.expendituretracker/sms"
    private val eventChannelName = "com.sbarpanda.expendituretracker/sms_stream"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots and screen recording
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Keep the old MethodChannel for fallback or synchronous small reads if needed, 
        // though we will migrate Dart to use the EventChannel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInboxSms" -> {
                        val since = call.argument<Number>("since")?.toLong() ?: 0L
                        val filterSenders = call.argument<List<String>>("filterSenders")
                        Thread {
                            try {
                                val messages = readInbox(since, filterSenders)
                                runOnUiThread { result.success(messages) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("SMS_READ_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var thread: Thread? = null
                
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val args = arguments as? Map<*, *>
                    val since = (args?.get("since") as? Number)?.toLong() ?: 0L
                    @Suppress("UNCHECKED_CAST")
                    val filterSenders = args?.get("filterSenders") as? List<String>
                    val batchSize = 500
                    
                    thread = Thread {
                        try {
                            val projection = arrayOf(
                                Telephony.Sms._ID,
                                Telephony.Sms.ADDRESS,
                                Telephony.Sms.BODY,
                                Telephony.Sms.DATE
                            )
                            val selection = if (since > 0) "${Telephony.Sms.DATE} > ?" else null
                            val selectionArgs = if (since > 0) arrayOf(since.toString()) else null

                            contentResolver.query(
                                Telephony.Sms.Inbox.CONTENT_URI,
                                projection,
                                selection,
                                selectionArgs,
                                "${Telephony.Sms.DATE} ASC"
                            )?.use { cursor ->
                                val idIdx = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
                                val addressIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                                val bodyIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
                                val dateIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)

                                var batch = mutableListOf<Map<String, Any?>>()
                                while (cursor.moveToNext() && !Thread.currentThread().isInterrupted) {
                                    val sender = cursor.getString(addressIdx) ?: ""
                                    
                                    var shouldInclude = true
                                    if (!filterSenders.isNullOrEmpty()) {
                                        val upperSender = sender.uppercase()
                                        shouldInclude = filterSenders.any { upperSender.contains(it.uppercase()) }
                                    }

                                    if (shouldInclude) {
                                        batch.add(
                                            mapOf(
                                                "id" to cursor.getLong(idIdx),
                                                "sender" to sender,
                                                "body" to (cursor.getString(bodyIdx) ?: ""),
                                                "date" to cursor.getLong(dateIdx)
                                            )
                                        )
                                        if (batch.size >= batchSize) {
                                            val currentBatch = batch
                                            batch = mutableListOf()
                                            runOnUiThread { events?.success(currentBatch) }
                                        }
                                    }
                                }
                                if (batch.isNotEmpty() && !Thread.currentThread().isInterrupted) {
                                    runOnUiThread { events?.success(batch) }
                                }
                            }
                            if (!Thread.currentThread().isInterrupted) {
                                runOnUiThread { events?.endOfStream() }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { events?.error("SMS_READ_ERROR", e.message, null) }
                        }
                    }
                    thread?.start()
                }

                override fun onCancel(arguments: Any?) {
                    thread?.interrupt()
                    thread = null
                }
            })
    }

    private fun readInbox(since: Long, filterSenders: List<String>?): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val selection = if (since > 0) "${Telephony.Sms.DATE} > ?" else null
        val selectionArgs = if (since > 0) arrayOf(since.toString()) else null

        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${Telephony.Sms.DATE} ASC"
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
            val addressIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)

            while (cursor.moveToNext()) {
                val sender = cursor.getString(addressIdx) ?: ""
                var shouldInclude = true
                if (!filterSenders.isNullOrEmpty()) {
                    val upperSender = sender.uppercase()
                    shouldInclude = filterSenders.any { upperSender.contains(it.uppercase()) }
                }

                if (shouldInclude) {
                    messages.add(
                        mapOf(
                            "id" to cursor.getLong(idIdx),
                            "sender" to sender,
                            "body" to (cursor.getString(bodyIdx) ?: ""),
                            "date" to cursor.getLong(dateIdx)
                        )
                    )
                }
            }
        }
        return messages
    }
}
