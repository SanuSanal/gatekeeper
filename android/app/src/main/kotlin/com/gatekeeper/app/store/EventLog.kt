package com.gatekeeper.app.store

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

data class LogEntry(val timestamp: Long, val category: String, val message: String)

/**
 * Append-only, size-capped event log stored as JSON lines in app-private storage.
 * Never write full phone numbers here; callers mask them.
 */
class EventLog(context: Context) {
    private val file = File(context.applicationContext.filesDir, "gatekeeper_log.jsonl")

    @Synchronized
    fun append(timestamp: Long, category: String, message: String) {
        try {
            val line = JSONObject().put("t", timestamp).put("c", category).put("m", message).toString()
            file.appendText(line + "\n")
            trimIfNeeded()
        } catch (e: Exception) {
            Log.w("GateKeeper", "Event log write failed", e)
        }
        Log.i("GateKeeper", "[$category] $message")
    }

    /** Newest first. */
    @Synchronized
    fun read(limit: Int): List<LogEntry> {
        if (!file.exists()) return emptyList()
        return file.readLines().asReversed().asSequence()
            .mapNotNull { parse(it) }
            .take(limit.coerceAtLeast(0))
            .toList()
    }

    @Synchronized
    fun clear() {
        file.delete()
    }

    private fun parse(line: String): LogEntry? = try {
        val o = JSONObject(line)
        LogEntry(o.getLong("t"), o.getString("c"), o.getString("m"))
    } catch (_: Exception) {
        null
    }

    private fun trimIfNeeded() {
        val lines = file.readLines()
        if (lines.size > MAX_LINES + TRIM_SLACK) {
            file.writeText(lines.takeLast(MAX_LINES).joinToString("\n", postfix = "\n"))
        }
    }

    private companion object {
        const val MAX_LINES = 1000
        const val TRIM_SLACK = 200
    }
}
