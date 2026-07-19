package com.example.expenditure_tracker

import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.expenditure_tracker/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInboxSms" -> {
                        val since = call.argument<Number>("since")?.toLong() ?: 0L
                        // Query on a background thread; the inbox can be large.
                        Thread {
                            try {
                                val messages = readInbox(since)
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
    }

    private fun readInbox(since: Long): List<Map<String, Any?>> {
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
                messages.add(
                    mapOf(
                        "id" to cursor.getLong(idIdx),
                        "sender" to (cursor.getString(addressIdx) ?: ""),
                        "body" to (cursor.getString(bodyIdx) ?: ""),
                        "date" to cursor.getLong(dateIdx)
                    )
                )
            }
        }
        return messages
    }
}
