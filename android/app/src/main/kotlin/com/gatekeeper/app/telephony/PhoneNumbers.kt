package com.gatekeeper.app.telephony

import android.content.Context
import android.telephony.PhoneNumberUtils
import android.telephony.TelephonyManager

object PhoneNumbers {
    private val ALLOWED = Regex("^\\+?[0-9]{3,15}$")

    /** Well-known emergency short codes, used if the platform check is unavailable. */
    private val FALLBACK_EMERGENCY = setOf("100", "101", "102", "108", "110", "112", "118", "119", "911", "999", "000", "1122")

    /** Strips formatting characters. Returns null if the result is not a plausible dialable number. */
    fun normalize(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val stripped = raw.trim().replace(Regex("[\\s\\-().]"), "")
        if (!ALLOWED.matches(stripped)) return null
        if (!PhoneNumberUtils.isGlobalPhoneNumber(stripped)) return null
        return stripped
    }

    /** Validates and additionally refuses emergency numbers: the app must never auto-dial them. */
    fun normalizeForCalling(context: Context, raw: String?): String? {
        val n = normalize(raw) ?: return null
        if (isEmergency(context, n)) return null
        return n
    }

    fun isEmergency(context: Context, number: String): Boolean {
        if (number in FALLBACK_EMERGENCY) return true
        return try {
            context.getSystemService(TelephonyManager::class.java)?.isEmergencyNumber(number) ?: false
        } catch (_: Exception) {
            false
        }
    }

    /** "••• 1234" — never log or display the full number unnecessarily. */
    fun mask(number: String?): String {
        if (number.isNullOrBlank()) return "(none)"
        val digits = number.filter { it.isDigit() }
        return if (digits.length <= 4) "•••" else "••• ${digits.takeLast(4)}"
    }
}
