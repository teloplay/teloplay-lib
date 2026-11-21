package com.piyas.teloplay.match

import java.text.Normalizer

/**
 * Canonical JSON Serializer for Kotlin JVM and Android
 * Conforming strictly to Section 7 & Section 4 of Spec
 */
object Canonical {

    fun escape(s: String): String {
        val nfc = Normalizer.normalize(s, Normalizer.Form.NFC)
        val sb = StringBuilder("\"")
        for (ch in nfc) {
            when (ch) {
                '\"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\b' -> sb.append("\\b")
                '\u000c' -> sb.append("\\f")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> {
                    if (ch.code < 32) {
                        sb.append(String.format("\\u%04x", ch.code))
                    } else {
                        sb.append(ch)
                    }
                }
            }
        }
        sb.append("\"")
        return sb.toString()
    }

    fun track(
        id: String,
        title: String,
        artists: List<String>,
        artistLine: String,
        album: String?,
        durationMs: Int?,
        thumbnail: String?,
        explicit: Boolean
    ): String {
        val artsJson = artists.joinToString(separator = ",", prefix = "[", postfix = "]") { escape(it) }
        val albJson = if (album != null) escape(album) else "null"
        val durJson = durationMs?.toString() ?: "null"
        val thumbJson = if (thumbnail != null) escape(thumbnail) else "null"

        return "{\"kind\":\"track\",\"id\":${escape(id)},\"title\":${escape(title)},\"artists\":$artsJson,\"artistLine\":${escape(artistLine)},\"album\":$albJson,\"durationMs\":$durJson,\"thumbnail\":$thumbJson,\"explicit\":$explicit}"
    }

    fun artist(
        id: String,
        name: String,
        thumbnail: String?,
        subscribers: String?
    ): String {
        val thumbJson = if (thumbnail != null) escape(thumbnail) else "null"
        val subsJson = if (subscribers != null) escape(subscribers) else "null"
        return "{\"kind\":\"artist\",\"id\":${escape(id)},\"name\":${escape(name)},\"thumbnail\":$thumbJson,\"subscribers\":$subsJson}"
    }

    fun album(
        id: String,
        title: String,
        artists: List<String>,
        year: Int?,
        thumbnail: String?
    ): String {
        val artsJson = artists.joinToString(separator = ",", prefix = "[", postfix = "]") { escape(it) }
        val yrJson = year?.toString() ?: "null"
        val thumbJson = if (thumbnail != null) escape(thumbnail) else "null"
        return "{\"kind\":\"album\",\"id\":${escape(id)},\"title\":${escape(title)},\"artists\":$artsJson,\"year\":$yrJson,\"thumbnail\":$thumbJson}"
    }

    fun section(type: String, itemsJson: List<String>): String {
        return "{\"type\":${escape(type)},\"items\":[${itemsJson.joinToString(",")}]}"
    }

    fun searchResponse(query: String, sectionsJson: List<String>): String {
        return "{\"v\":2,\"query\":${escape(query)},\"sections\":[${sectionsJson.joinToString(",")}]}"
    }

    fun relatedResponse(id: String, status: String, itemsJson: List<String>): String {
        return "{\"v\":1,\"id\":${escape(id)},\"status\":${escape(status)},\"items\":[${itemsJson.joinToString(",")}]}"
    }

    fun resolveResponse(
        id: String,
        source: String,
        streamUrl: String,
        bitrateKbps: Int,
        mime: String,
        expiresAtMs: Long?,
        accepted: Boolean,
        reason: String,
        scoreMilli: Int,
        jiosaavnId: String?
    ): String {
        val expJson = expiresAtMs?.toString() ?: "null"
        val saavnJson = if (jiosaavnId != null) escape(jiosaavnId) else "null"
        val matchJson = "{\"accepted\":$accepted,\"reason\":${escape(reason)},\"scoreMilli\":$scoreMilli,\"jiosaavnId\":$saavnJson}"

        return "{\"v\":1,\"id\":${escape(id)},\"source\":${escape(source)},\"streamUrl\":${escape(streamUrl)},\"bitrateKbps\":$bitrateKbps,\"mime\":${escape(mime)},\"expiresAtMs\":$expJson,\"match\":$matchJson}"
    }
}
