package com.piyas.teloplay.match

import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * TeloPlay Reference Matcher Engine (Kotlin Implementation)
 * Conforming strictly to Section 5.3 of TELOPLAY_HANDOFF_SPEC.md (v1.0.0)
 */

data class MatchSpec(
    val specVersion: String = "1.0.0",
    val durationHardLimitSec: Int = 12,
    val durationFullScoreSec: Int = 4,
    val weights: Weights = Weights(0.45, 0.35, 0.2),
    val acceptScore: Double = 0.8,
    val artistMinSim: Double = 0.85,
    val titleMinSim: Double = 0.75,
    val fuzzyTokenMinLen: Int = 5,
    val fuzzyTokenMinSim: Double = 0.85,
    val subsetMinRatio: Double = 0.6,
    val titleSeparators: List<String> = listOf(" - ", " – ", " — ", " | "),
    val titleNoiseWords: List<String> = listOf("official", "video", "audio", "lyrics", "lyric", "lyrical", "visualizer", "hd", "hq", "4k", "mv", "feat", "ft", "featuring", "full", "song"),
    val artistStopWords: List<String> = listOf("topic", "vevo", "official", "music", "records", "feat", "ft", "featuring", "and"),
    val versionMarkers: List<String> = listOf("remix", "live", "acoustic", "unplugged", "cover", "reprise", "slowed", "reverb", "lofi", "instrumental", "karaoke", "sped", "nightcore", "mashup", "flip", "bootleg", "rework")
)

data class Weights(val artist: Double, val title: Double, val duration: Double)

data class TrackInfo(
    val title: String,
    val artists: List<String>,
    val durationSec: Int
)

data class Scores(
    val artistMilli: Int,
    val titleMilli: Int,
    val durationMilli: Int,
    val scoreMilli: Int
)

data class MatchResult(
    val accepted: Boolean,
    val reason: String,
    val scores: Scores
)

data class SelectedCandidate<T>(
    val candidate: T,
    val match: MatchResult,
    val index: Int
)

object Matcher {

    val DEFAULT_SPEC = MatchSpec()

    fun norm(s: String?): String {
        if (s.isNullOrEmpty()) return ""
        val decomposed = Normalizer.normalize(s, Normalizer.Form.NFKD)
            .replace(Regex("[\\u0300-\\u036f]"), "")
        val composed = Normalizer.normalize(decomposed, Normalizer.Form.NFC).lowercase()
        return composed.replace(Regex("[^\\p{L}\\p{N}\\p{M}]+"), " ").trim()
    }

    fun tokens(s: String?): List<String> {
        val n = norm(s)
        if (n.isEmpty()) return emptyList()
        return n.split(" ").filter { it.isNotEmpty() }
    }

    data class SplitBracketsResult(val outside: String, val inside: List<String>)

    fun splitBrackets(raw: String?): SplitBracketsResult {
        if (raw.isNullOrEmpty()) return SplitBracketsResult("", emptyList())
        val outside = StringBuilder()
        val inside = mutableListOf<String>()
        var currentInside = StringBuilder()
        var depth = 0

        for (ch in raw) {
            when (ch) {
                '(', '[', '{' -> {
                    if (depth == 0) {
                        outside.append(" ")
                        currentInside = StringBuilder()
                    } else {
                        currentInside.append(ch)
                    }
                    depth++
                }
                ')', ']', '}' -> {
                    if (depth > 0) {
                        depth--
                        if (depth == 0) {
                            inside.add(currentInside.toString())
                            currentInside = StringBuilder()
                        } else {
                            currentInside.append(ch)
                        }
                    } else {
                        outside.append(ch)
                    }
                }
                else -> {
                    if (depth > 0) {
                        currentInside.append(ch)
                    } else {
                        outside.append(ch)
                    }
                }
            }
        }

        if (depth > 0 && currentInside.isNotEmpty()) {
            inside.add(currentInside.toString())
        }

        return SplitBracketsResult(outside.toString(), inside)
    }

    data class ExtractVariantsResult(val rest: List<String>, val found: Set<String>)

    fun extractVariants(toks: List<String>, versionMarkers: List<String>): ExtractVariantsResult {
        val rest = mutableListOf<String>()
        val found = mutableSetOf<String>()
        val vmSet = versionMarkers.toSet()

        var i = 0
        while (i < toks.size) {
            val t = toks[i]
            if (t == "lo" && i + 1 < toks.size && toks[i + 1] == "fi") {
                found.add("lofi")
                i += 2
            } else if (vmSet.contains(t)) {
                found.add(t)
                i++
            } else {
                rest.add(t)
                i++
            }
        }
        return ExtractVariantsResult(rest, found)
    }

    data class CleanTitleResult(val core: List<String>, val variants: List<String>)

    fun cleanTitle(raw: String?, artistTokens: List<String>, spec: MatchSpec = DEFAULT_SPEC): CleanTitleResult {
        val artistTokSet = artistTokens.toSet()
        val noiseSet = spec.titleNoiseWords.toSet()
        val (outside, inside) = splitBrackets(raw)

        var segments = listOf(outside)
        for (sep in spec.titleSeparators) {
            val nextSegs = mutableListOf<String>()
            for (seg in segments) {
                nextSegs.addAll(seg.split(sep))
            }
            segments = nextSegs
        }

        val segToks = segments.map { tokens(it) }.filter { it.isNotEmpty() }

        var coreIdx = 0
        if (segToks.size > 1) {
            val seg0 = segToks[0]
            if (seg0.isNotEmpty() && seg0.all { artistTokSet.contains(it) }) {
                coreIdx = 1
            }
        }

        val allVariants = mutableSetOf<String>()
        var core = emptyList<String>()

        for (i in segToks.indices) {
            val (rest, found) = extractVariants(segToks[i], spec.versionMarkers)
            allVariants.addAll(found)

            if (i == coreIdx) {
                core = rest.filter { !noiseSet.contains(it) }
            }
        }

        for (inStr in inside) {
            val inToks = tokens(inStr)
            val (_, found) = extractVariants(inToks, spec.versionMarkers)
            allVariants.addAll(found)
        }

        return CleanTitleResult(core, allVariants.toList().sorted())
    }

    fun editDistance(a: String, b: String): Int {
        val m = a.length
        val n = b.length
        val dp = Array(m + 1) { IntArray(n + 1) }

        for (i in 0..m) dp[i][0] = i
        for (j in 0..n) dp[0][j] = j

        for (i in 1..m) {
            for (j in 1..n) {
                if (a[i - 1] == b[j - 1]) {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(dp[i - 1][j], min(dp[i][j - 1], dp[i - 1][j - 1]))
                }
            }
        }
        return dp[m][n]
    }

    fun levRatio(a: String, b: String): Double {
        if (a.isEmpty() && b.isEmpty()) return 1.0
        val maxLen = max(a.length, b.length)
        if (maxLen == 0) return 1.0
        return 1.0 - (editDistance(a, b).toDouble() / maxLen)
    }

    fun jaccard(setA: Set<String>, setB: Set<String>): Double {
        if (setA.isEmpty() && setB.isEmpty()) return 1.0
        if (setA.isEmpty() || setB.isEmpty()) return 0.0
        var intersection = 0
        for (item in setA) {
            if (setB.contains(item)) intersection++
        }
        val union = setA.size + setB.size - intersection
        return if (union == 0) 0.0 else intersection.toDouble() / union
    }

    fun titleSim(coreA: List<String>, coreB: List<String>): Double {
        if (coreA.isEmpty() || coreB.isEmpty()) return 0.0
        val strA = coreA.joinToString(" ")
        val strB = coreB.joinToString(" ")
        val lev = levRatio(strA, strB)
        val jc = jaccard(coreA.toSet(), coreB.toSet())
        return max(jc, lev)
    }

    fun nameTokens(name: String?, spec: MatchSpec = DEFAULT_SPEC): List<String> {
        val stopSet = spec.artistStopWords.toSet()
        return tokens(name).filter { !stopSet.contains(it) }
    }

    fun nameMatch(toksA: List<String>, toksB: List<String>, spec: MatchSpec = DEFAULT_SPEC): Double {
        if (toksA.isEmpty() || toksB.isEmpty()) return 0.0

        val sortedA = toksA.sorted()
        val sortedB = toksB.sorted()

        if (sortedA.size == sortedB.size && sortedA.indices.all { sortedA[it] == sortedB[it] }) {
            return 1.0
        }

        val (small, large) = if (sortedA.size <= sortedB.size) Pair(sortedA, sortedB) else Pair(sortedB, sortedA)
        if (small.size >= 2) {
            val largeSet = large.toSet()
            if (small.all { largeSet.contains(it) }) {
                if (small.size.toDouble() / large.size >= spec.subsetMinRatio) {
                    return 0.9
                }
            }
        }

        if (sortedA.size == sortedB.size) {
            var match = true
            for (i in sortedA.indices) {
                val ta = sortedA[i]
                val tb = sortedB[i]
                if (ta == tb) continue
                if (ta.length >= spec.fuzzyTokenMinLen && tb.length >= spec.fuzzyTokenMinLen) {
                    if (levRatio(ta, tb) >= spec.fuzzyTokenMinSim) {
                        continue
                    }
                }
                match = false
                break
            }
            if (match) return 0.85
        }

        return 0.0
    }

    fun artistScore(ytArtists: List<String>, jsArtists: List<String>, spec: MatchSpec = DEFAULT_SPEC): Double {
        if (ytArtists.isEmpty() || jsArtists.isEmpty()) return 0.0
        val leadTokens = nameTokens(ytArtists[0], spec)
        if (leadTokens.isEmpty()) return 0.0

        var maxScore = 0.0
        for (jsArt in jsArtists) {
            val jsToks = nameTokens(jsArt, spec)
            val score = nameMatch(leadTokens, jsToks, spec)
            if (score > maxScore) maxScore = score
        }
        return maxScore
    }

    fun durationScore(delta: Int, spec: MatchSpec = DEFAULT_SPEC): Double {
        if (delta > spec.durationHardLimitSec) return 0.0
        if (delta <= spec.durationFullScoreSec) return 1.0
        return 1.0 - (0.5 * (delta - spec.durationFullScoreSec).toDouble() / (spec.durationHardLimitSec - spec.durationFullScoreSec))
    }

    fun milli(x: Double): Int {
        return floor(x * 1000 + 0.5).toInt()
    }

    fun matchTrack(yt: TrackInfo, js: TrackInfo, spec: MatchSpec = DEFAULT_SPEC): MatchResult {
        val allArtistTokens = mutableSetOf<String>()
        yt.artists.forEach { nameTokens(it, spec).forEach { t -> allArtistTokens.add(t) } }
        js.artists.forEach { nameTokens(it, spec).forEach { t -> allArtistTokens.add(t) } }

        val ytTitleClean = cleanTitle(yt.title, allArtistTokens.toList(), spec)
        val jsTitleClean = cleanTitle(js.title, allArtistTokens.toList(), spec)

        val delta = abs(yt.durationSec - js.durationSec)

        val aScore = artistScore(yt.artists, js.artists, spec)
        val tScore = titleSim(ytTitleClean.core, jsTitleClean.core)
        val dScore = durationScore(delta, spec)

        val sScore = (spec.weights.artist * aScore) + (spec.weights.title * tScore) + (spec.weights.duration * dScore)

        val artistMilli = milli(aScore)
        val titleMilli = milli(tScore)
        val durationMilli = milli(dScore)
        val scoreMilli = milli(sScore)

        val ytVariantsStr = ytTitleClean.variants.joinToString(",")
        val jsVariantsStr = jsTitleClean.variants.joinToString(",")

        var reason = "ok"
        var accepted = true

        if (delta > spec.durationHardLimitSec) {
            accepted = false
            reason = "duration_out_of_range"
        } else if (aScore < spec.artistMinSim) {
            accepted = false
            reason = "artist_mismatch"
        } else if (ytVariantsStr != jsVariantsStr) {
            accepted = false
            reason = "variant_mismatch"
        } else if (tScore < spec.titleMinSim) {
            accepted = false
            reason = "title_mismatch"
        } else if (sScore < spec.acceptScore) {
            accepted = false
            reason = "score_below_threshold"
        }

        return MatchResult(
            accepted = accepted,
            reason = reason,
            scores = Scores(artistMilli, titleMilli, durationMilli, scoreMilli)
        )
    }

    fun <T> selectBest(
        spec: MatchSpec = DEFAULT_SPEC,
        yt: TrackInfo,
        candidates: List<T>,
        toTrackInfo: (T) -> TrackInfo
    ): SelectedCandidate<T>? {
        if (candidates.isEmpty()) return null

        var bestCandidate: SelectedCandidate<T>? = null
        var bestScore = -1
        var bestDelta = 999999
        var bestRejected: SelectedCandidate<T>? = null
        var maxRejectedScore = -1

        for (i in candidates.indices) {
            val c = candidates[i]
            val trackInfo = toTrackInfo(c)
            val match = matchTrack(yt, trackInfo, spec)
            val delta = abs(yt.durationSec - trackInfo.durationSec)

            if (match.accepted) {
                val s = match.scores.scoreMilli
                if (s > bestScore || (s == bestScore && delta < bestDelta)) {
                    bestScore = s
                    bestDelta = delta
                    bestCandidate = SelectedCandidate(c, match, i)
                }
            } else {
                if (match.scores.scoreMilli > maxRejectedScore) {
                    maxRejectedScore = match.scores.scoreMilli
                    bestRejected = SelectedCandidate(c, match, i)
                }
            }
        }

        return bestCandidate ?: bestRejected
    }
}
