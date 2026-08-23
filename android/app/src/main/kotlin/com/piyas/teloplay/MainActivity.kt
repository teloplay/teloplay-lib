// android/app/src/main/kotlin/com/piyas/teloplay/MainActivity.kt
package com.piyas.teloplay

import android.util.Log
import com.arturo254.opentune.innertube.YouTube
import com.arturo254.opentune.innertube.NewPipeUtils
import com.arturo254.opentune.innertube.models.YouTubeClient
import com.arturo254.opentune.innertube.models.SongItem
import com.arturo254.opentune.innertube.models.WatchEndpoint
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

// ⚠️ চূড়ান্ত সঠিক পরিবর্তন: FlutterFragmentActivity নয়,
// audio_service প্যাকেজের নিজস্ব AudioServiceFragmentActivity
// ব্যবহার করতে হবে (com.ryanheise.audioservice প্যাকেজ থেকে)।
//
// কারণ: শুধু generic io.flutter.embedding.android.FlutterFragmentActivity
// ব্যবহার করলে সেটা Fragment host করতে পারলেও, audio_service প্লাগইনের
// প্রয়োজনীয় নির্দিষ্ট override/binding (যেগুলো MediaBrowserService-এর
// সাথে সঠিকভাবে FlutterEngine bind করে) সেখানে থাকে না। এই কারণেই
// "The Activity class declared in your AndroidManifest.xml is wrong
// or has not provided the correct FlutterEngine" crash হচ্ছিল, এমনকি
// FlutterFragmentActivity ব্যবহার করার পরেও।
//
// audio_service-এর official GitHub README/issue (ryanheise/audio_service
// #937)-এ স্পষ্ট বলা আছে: custom Activity ব্যবহার করতে চাইলে
// AudioServiceFragmentActivity extend করতে হবে, plain
// FlutterFragmentActivity না।
class MainActivity : AudioServiceFragmentActivity() {

    private val CHANNEL = "com.piyas.teloplay/youtube_stream"
    private val mainScope = CoroutineScope(Dispatchers.Main)

    // 17-client fallback — VISIONOS প্রথমে (একমাত্র client যেটা
    // pre-signed stream URL দেয়) — main.kt (Windows daemon) এর সাথে
    // hubohu identical, cross-platform consistency বজায় রাখার জন্য।
    private val fallbackClients = listOf(
        YouTubeClient.VISIONOS,                        // 12/12 OK (primary)
        YouTubeClient.ANDROID_VR_NO_AUTH,              // 1.37
        YouTubeClient.ANDROID_VR_1_61_48,
        YouTubeClient.ANDROID_VR_1_43_32,
        YouTubeClient.ANDROID_CREATOR,
        YouTubeClient.ANDROID_TESTSUITE,
        YouTubeClient.ANDROID_UNPLUGGED,
        YouTubeClient.IPADOS,
        YouTubeClient.IOS,
        YouTubeClient.IOS_MUSIC,
        YouTubeClient.ANDROID_MUSIC,
        YouTubeClient.MOBILE,                          // playability=OK কিন্তু URL=null — তাই শেষের দিকে
        YouTubeClient.TVHTML5,
        YouTubeClient.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
        YouTubeClient.WEB,
        YouTubeClient.WEB_CREATOR,
        YouTubeClient.WEB_REMIX,
    )

    private var visitorDataReady = false
    private var visitorDataFetchedAt = 0L
    private val VISITOR_DATA_TTL_MS = 30 * 60 * 1000L // 30 minutes

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // ⚠️ REVERTED: plain String url রিটার্ন করে, আগের কাজ-করা
                // আচরণে। rich StreamInfo (clientName/bitrate/itag ইত্যাদি)
                // দিলে Dart side String আশা করছিল বলে cast fail করে
                // streaming fail করছিল — তাই এটা আগের মতোই রাখা হলো।
                "getStreamUrl" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId == null) {
                        result.error("BAD_ARGS", "videoId missing", null)
                        return@setMethodCallHandler
                    }
                    mainScope.launch {
                        try {
                            val streamUrl = withContext(Dispatchers.IO) {
                                getStreamUrlInternal(videoId)
                            }
                            if (streamUrl != null) {
                                result.success(streamUrl)
                            } else {
                                result.error("NO_STREAM", "কোনো client দিয়ে stream URL পাওয়া যায়নি", null)
                            }
                        } catch (e: Exception) {
                            Log.e("TeloPlayInnertube", "getStreamUrl failed", e)
                            result.error("EXCEPTION", e.message, null)
                        }
                    }
                }
                "searchTracks" -> {
                    val query = call.argument<String>("query")
                    val limit = call.argument<Int>("limit") ?: 10
                    if (query == null) {
                        result.error("BAD_ARGS", "query missing", null)
                        return@setMethodCallHandler
                    }
                    mainScope.launch {
                        try {
                            val tracks = withContext(Dispatchers.IO) {
                                searchTracksInternal(query, limit)
                            }
                            result.success(tracks)
                        } catch (e: Exception) {
                            Log.e("TeloPlayInnertube", "searchTracks failed", e)
                            result.error("EXCEPTION", e.message, null)
                        }
                    }
                }
                "getSearchSuggestions" -> {
                    val query = call.argument<String>("query")
                    if (query == null) {
                        result.error("BAD_ARGS", "query missing", null)
                        return@setMethodCallHandler
                    }
                    mainScope.launch {
                        try {
                            val suggestions = withContext(Dispatchers.IO) {
                                getSearchSuggestionsInternal(query)
                            }
                            result.success(suggestions)
                        } catch (e: Exception) {
                            // Suggestion ব্যর্থ হওয়া non-critical — error()
                            // এর বদলে খালি list দেওয়া হচ্ছে, যাতে Dart
                            // side-এ কোনো exception catch করার দরকার না
                            // হয় (PlaybackEngine.searchSuggestions()-এর
                            // default no-op contract-এর সাথে সামঞ্জস্যপূর্ণ)।
                            Log.w("TeloPlayInnertube", "getSearchSuggestions failed: ${e.message}")
                            result.success(emptyList<String>())
                        }
                    }
                }
                // ========== GENERIC COMMAND HANDLER (main.kt এর handleCommand স্টাইল) ==========
                // album, artist, related, playlist, lyrics, media-info, charts,
                // home, details, resolve(rich) — এই সব commands একটাই
                // MethodChannel case দিয়ে হ্যান্ডেল হয়। এখানের "resolve"
                // rich StreamInfo দেয়, কিন্তু সম্পূর্ণ আলাদা ফাংশন
                // (resolveStreamRich) ব্যবহার করে — তাই getStreamUrl
                // (playback path)-এর plain-String আচরণে কোনো প্রভাব
                // পড়ে না।
                "command" -> {
                    val cmd = call.argument<String>("cmd")
                    if (cmd == null) {
                        result.error("BAD_ARGS", "cmd missing", null)
                        return@setMethodCallHandler
                    }
                    val params: Map<String, Any?> = call.arguments as? Map<String, Any?> ?: emptyMap()
                    mainScope.launch {
                        try {
                            val response = withContext(Dispatchers.IO) {
                                handleCommand(cmd, params)
                            }
                            result.success(response)
                        } catch (e: Exception) {
                            Log.e("TeloPlayInnertube", "command '$cmd' failed", e)
                            result.error("EXCEPTION", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private suspend fun ensureVisitorData(forceRefresh: Boolean = false) {
        val expired = (System.currentTimeMillis() - visitorDataFetchedAt) > VISITOR_DATA_TTL_MS
        if (visitorDataReady && !expired && !forceRefresh) return

        val vdResult = YouTube.visitorData()
        vdResult.onSuccess { vd ->
            YouTube.visitorData = vd
            visitorDataReady = true
            visitorDataFetchedAt = System.currentTimeMillis()
            Log.d("TeloPlayInnertube", "visitorData refreshed")
        }
        vdResult.onFailure { e ->
            Log.e("TeloPlayInnertube", "visitorData fetch failed", e)
        }
    }

    // ========== STREAM RESOLVE — playback path (আগের কাজ-করা plain String version, অপরিবর্তিত) ==========
    private suspend fun getStreamUrlInternal(videoId: String): String? {
        ensureVisitorData()

        suspend fun attempt(): String? {
            val sigTimestamp = NewPipeUtils.getSignatureTimestamp(videoId).getOrNull()

            for (client in fallbackClients) {
                try {
                    val playerResult = withTimeout(20_000) {
                        YouTube.player(
                            videoId = videoId,
                            client = client,
                            signatureTimestamp = sigTimestamp,
                        )
                    }
                    val playerResponse = playerResult.getOrNull() ?: continue
                    if (playerResponse.playabilityStatus.status != "OK") {
                        Log.w("TeloPlayInnertube", "${client.clientName}: status=${playerResponse.playabilityStatus.status}")
                        continue
                    }

                    val audioFormat = playerResponse.streamingData?.adaptiveFormats
                        ?.filter { it.mimeType.startsWith("audio/") }
                        ?.maxByOrNull { it.bitrate ?: 0 }
                        ?: continue

                    val streamUrlResult = withTimeout(20_000) {
                        NewPipeUtils.getStreamUrl(
                            format = audioFormat,
                            videoId = videoId,
                            client = client,
                        )
                    }
                    streamUrlResult.getOrNull()?.let { url ->
                        Log.d("TeloPlayInnertube", "success with ${client.clientName}")
                        return url
                    }
                    Log.w("TeloPlayInnertube", "${client.clientName}: getStreamUrl null")
                } catch (e: Exception) {
                    Log.w("TeloPlayInnertube", "${client.clientName} failed: ${e.message}")
                }
            }
            return null
        }

        val first = attempt()
        if (first != null) return first

        // সব client fail হলে — visitorData force refresh করে একবার retry (Windows CLI-এর মতো)
        Log.w("TeloPlayInnertube", "all clients failed — forcing visitorData refresh and retrying once")
        ensureVisitorData(forceRefresh = true)
        return attempt()
    }

    // ========== RICH RESOLVE — শুধু "command"->"resolve" এর জন্য, playback path থেকে সম্পূর্ণ আলাদা ==========
    private data class StreamInfo(
        val url: String,
        val clientName: String,
        val clientVersion: String,
        val itag: Int,
        val bitrate: Int,
        val mimeType: String,
        val expiresInSeconds: Int?,
        val contentLength: Long?,
    )

    private suspend fun resolveStreamRich(videoId: String): StreamInfo? {
        ensureVisitorData()

        suspend fun attempt(): StreamInfo? {
            val sigTimestamp = NewPipeUtils.getSignatureTimestamp(videoId).getOrNull()

            for (client in fallbackClients) {
                try {
                    val playerResult = withTimeout(20_000) {
                        YouTube.player(
                            videoId = videoId,
                            client = client,
                            signatureTimestamp = sigTimestamp,
                        )
                    }
                    val playerResponse = playerResult.getOrNull() ?: continue
                    if (playerResponse.playabilityStatus.status != "OK") continue

                    val audioFormat = playerResponse.streamingData?.adaptiveFormats
                        ?.filter { it.mimeType.startsWith("audio/") }
                        ?.maxByOrNull { it.bitrate }
                        ?: continue

                    val url = withTimeout(20_000) {
                        NewPipeUtils.getStreamUrl(audioFormat, videoId, client).getOrNull()
                    }
                    if (url != null) {
                        return StreamInfo(
                            url = url,
                            clientName = client.clientName,
                            clientVersion = client.clientVersion,
                            itag = audioFormat.itag,
                            bitrate = audioFormat.bitrate,
                            mimeType = audioFormat.mimeType,
                            expiresInSeconds = playerResponse.streamingData?.expiresInSeconds,
                            contentLength = audioFormat.contentLength,
                        )
                    }
                } catch (e: Exception) {
                    Log.w("TeloPlayInnertube", "${client.clientName} failed: ${e.message}")
                }
            }
            return null
        }

        val first = attempt()
        if (first != null) return first
        ensureVisitorData(forceRefresh = true)
        return attempt()
    }

    private fun streamInfoToMap(info: StreamInfo): Map<String, Any?> = mapOf(
        "url" to info.url,
        "clientName" to info.clientName,
        "clientVersion" to info.clientVersion,
        "itag" to info.itag,
        "bitrate" to info.bitrate,
        "mimeType" to info.mimeType,
        "expiresInSeconds" to info.expiresInSeconds,
        "contentLength" to info.contentLength,
    )

    // ⚠️ FIX (cross-platform consistency): আগে YouTube.search(query,
    // FILTER_SONG) ব্যবহার হতো — এটা শুধু "Songs" ট্যাবের সংকীর্ণ ফলাফল
    // দিত। OpenTune-এর নিজের search screen (OnlineSearchScreen.kt)
    // আসলে YouTube.searchSummary() ব্যবহার করে "Top results" + একাধিক
    // category মিশিয়ে দেখায় — এটাই broader, বেশি প্রাসঙ্গিক ফলাফল দেয়।
    private suspend fun searchTracksInternal(query: String, limit: Int = 10): List<Map<String, Any?>> {
        ensureVisitorData()

        val summaryResult = YouTube.searchSummary(query).getOrNull()
            ?: return emptyList()

        val songs = summaryResult.summaries
            .flatMap { it.items }
            .filterIsInstance<SongItem>()
            .distinctBy { it.id }

        val limited = if (limit <= 0) songs else songs.take(limit)

        return limited.map { song -> songToMap(song) }
    }

    // main.kt এর songToJson() এর সমতুল্য — Flutter MethodChannel এর
    // জন্য Map<String, Any?> হিসেবে (JsonObject এর বদলে, কারণ
    // MethodChannel নিজে থেকেই Map/List/primitive marshal করতে পারে)।
    private fun songToMap(song: SongItem): Map<String, Any?> = mapOf(
        "videoId" to song.id,
        "title" to song.title,
        "author" to (song.artists.firstOrNull()?.name ?: "Unknown"),
        "artistId" to song.artists.firstOrNull()?.id,
        "allArtistNames" to song.artists.map { it.name },
        "allArtistIds" to song.artists.map { it.id },
        "thumbnail" to song.thumbnail,
        "duration" to song.duration,
        "albumId" to song.album?.id,
        "albumName" to song.album?.name,
        "explicit" to song.explicit,
        "chartPosition" to song.chartPosition,
        "chartChange" to song.chartChange,
        "setVideoId" to song.setVideoId,
    )

    // Live search suggestion — YouTube.searchSuggestions() Innertube
    // module-এ ইতিমধ্যে আছে (OpenTune-এর নিজের search screen ব্যবহার
    // করে), তাই নতুন backend integration লাগেনি।
    private suspend fun getSearchSuggestionsInternal(query: String): List<String> {
        ensureVisitorData()
        val result = YouTube.searchSuggestions(query).getOrNull() ?: return emptyList()
        return result.queries
    }

    // ========== NEW COMMANDS (main.kt থেকে পোর্ট করা) ==========

    // 1. VIDEO DETAILS — YouTube.next() + WatchEndpoint ব্যবহার করে
    private suspend fun getVideoDetails(videoId: String): Map<String, Any?> {
        ensureVisitorData()

        val endpoint = WatchEndpoint(videoId = videoId)
        val nextResult = YouTube.next(endpoint).getOrNull()
            ?: return mapOf("ok" to false, "error" to "DETAILS_FAILED")

        val song = nextResult.items.firstOrNull()
            ?: return mapOf("ok" to false, "error" to "NO_DETAILS_FOUND")

        return mapOf(
            "ok" to true,
            "videoId" to videoId,
            "title" to song.title,
            "author" to (song.artists.firstOrNull()?.name ?: "Unknown"),
            "thumbnail" to song.thumbnail,
            "duration" to (song.duration ?: 0),
            "explicit" to song.explicit,
        )
    }

    // 2. ALBUM TRACKS — YouTube.album()
    private suspend fun getAlbumTracks(albumId: String): Map<String, Any?> {
        ensureVisitorData()

        val albumPage = YouTube.album(albumId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "ALBUM_NOT_FOUND")

        val album = albumPage.album
        val songs = albumPage.songs

        return mapOf(
            "ok" to true,
            "albumName" to album.title,
            "artistName" to (album.artists?.firstOrNull()?.name ?: "Unknown"),
            "artistId" to album.artists?.firstOrNull()?.id,
            "thumbnail" to album.thumbnail,
            "year" to (album.year ?: 0),
            "trackCount" to songs.size,
            "tracks" to songs.map { track -> songToMap(track) },
        )
    }

    // 3. ARTIST SONGS — YouTube.artist() তারপর sections থেকে SongItem filter
    private suspend fun getArtistSongs(artistId: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val artistPage = YouTube.artist(artistId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "ARTIST_NOT_FOUND")

        val artist = artistPage.artist

        val allSongs = artistPage.sections
            .flatMap { it.items }
            .filterIsInstance<SongItem>()
            .distinctBy { it.id }

        val limited = if (limit <= 0) allSongs else allSongs.take(limit)

        return mapOf(
            "ok" to true,
            "artistId" to artistId,
            "artistName" to artist.title,
            "thumbnail" to (artist.thumbnail ?: ""),
            "songCount" to limited.size,
            "songs" to limited.map { song -> songToMap(song) },
        )
    }

    // 4. RELATED SONGS — YouTube.next() দিয়ে related endpoint বের করে, তারপর YouTube.related()
    private suspend fun getRelatedSongs(videoId: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val endpoint = WatchEndpoint(videoId = videoId)
        val nextResult = YouTube.next(endpoint).getOrNull()
            ?: return mapOf("ok" to false, "error" to "RELATED_FAILED")

        val relatedEndpoint = nextResult.relatedEndpoint
            ?: return mapOf("ok" to false, "error" to "NO_RELATED_ENDPOINT")

        val relatedPage = YouTube.related(relatedEndpoint).getOrNull()
            ?: return mapOf("ok" to false, "error" to "RELATED_FAILED")

        val songs = relatedPage.songs
        val limited = if (limit <= 0) songs else songs.take(limit)

        return mapOf(
            "ok" to true,
            "videoId" to videoId,
            "relatedCount" to limited.size,
            "songs" to limited.map { song ->
                mapOf(
                    "videoId" to song.id,
                    "title" to song.title,
                    "author" to (song.artists.firstOrNull()?.name ?: "Unknown"),
                    "thumbnail" to song.thumbnail,
                    "duration" to (song.duration ?: 0),
                )
            },
        )
    }

    // 5. PLAYLIST CONTENT — YouTube.playlist()
    private suspend fun getPlaylistTracks(playlistId: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val playlistPage = YouTube.playlist(playlistId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "PLAYLIST_NOT_FOUND")

        val playlist = playlistPage.playlist
        val tracks = playlistPage.songs
        val limited = if (limit <= 0) tracks else tracks.take(limit)

        return mapOf(
            "ok" to true,
            "playlistId" to playlistId,
            "playlistName" to playlist.title,
            "author" to (playlist.author?.name ?: ""),
            "thumbnail" to (playlist.thumbnail ?: ""),
            "trackCount" to limited.size,
            "tracks" to limited.map { track -> songToMap(track) },
        )
    }

    // 6. LYRICS — YouTube.next() দিয়ে lyrics endpoint বের করে, তারপর YouTube.lyrics()
    // ⚠️ শুধু plain text lyrics দেয় (upstream YouTube.lyrics() timed/synced
    // lyrics parse করে না) — isSynced তাই সবসময় false।
    private suspend fun getLyrics(videoId: String): Map<String, Any?> {
        ensureVisitorData()

        val endpoint = WatchEndpoint(videoId = videoId)
        val nextResult = YouTube.next(endpoint).getOrNull()
            ?: return mapOf("ok" to false, "error" to "LYRICS_NOT_FOUND")

        val lyricsEndpoint = nextResult.lyricsEndpoint
            ?: return mapOf("ok" to false, "error" to "LYRICS_NOT_FOUND")

        val lyricsText = YouTube.lyrics(lyricsEndpoint).getOrNull()
            ?: return mapOf("ok" to false, "error" to "LYRICS_NOT_FOUND")

        return mapOf(
            "ok" to true,
            "videoId" to videoId,
            "lyrics" to lyricsText,
            "source" to "youtube",
            "isSynced" to false,
        )
    }

    // 7. MEDIA INFO — YouTube.getMediaInfo()
    private suspend fun getMediaInfo(videoId: String): Map<String, Any?> {
        ensureVisitorData()

        val info = YouTube.getMediaInfo(videoId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "MEDIA_INFO_FAILED")

        return mapOf(
            "ok" to true,
            "videoId" to info.videoId,
            "title" to info.title,
            "author" to info.author,
            "authorId" to info.authorId,
            "authorThumbnail" to info.authorThumbnail,
            "description" to info.description,
            "uploadDate" to info.uploadDate,
            "subscribers" to info.subscribers,
            "viewCount" to info.viewCount,
            "like" to info.like,
            "dislike" to info.dislike,
        )
    }

    // 8. CHARTS — YouTube.getChartsPage()
    private suspend fun getCharts(): Map<String, Any?> {
        ensureVisitorData()

        val chartsPage = YouTube.getChartsPage().getOrNull()
            ?: return mapOf("ok" to false, "error" to "CHARTS_FAILED")

        return mapOf(
            "ok" to true,
            "sections" to chartsPage.sections.map { section ->
                mapOf(
                    "title" to section.title,
                    "chartType" to section.chartType.name,
                    "songs" to section.items.filterIsInstance<SongItem>().map { song -> songToMap(song) },
                )
            },
        )
    }

    // 9. HOME — YouTube.home()
    private suspend fun getHome(): Map<String, Any?> {
        ensureVisitorData()

        val homePage = YouTube.home().getOrNull()
            ?: return mapOf("ok" to false, "error" to "HOME_FAILED")

        return mapOf(
            "ok" to true,
            "sections" to homePage.sections.map { section ->
                mapOf(
                    "title" to section.title,
                    "songs" to section.items.filterIsInstance<SongItem>().map { song -> songToMap(song) },
                )
            },
        )
    }

    // ========== GENERIC COMMAND DISPATCH (main.kt এর handleCommand() এর সমতুল্য) ==========
    private suspend fun handleCommand(cmd: String, params: Map<String, Any?>): Map<String, Any?> {
        return when (cmd) {
            // rich StreamInfo — resolveStreamRich() ব্যবহার করে, playback
            // path (getStreamUrl/getStreamUrlInternal) থেকে সম্পূর্ণ
            // স্বতন্ত্র, তাই একে অন্যকে প্রভাবিত করে না।
            "resolve" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                val info = resolveStreamRich(videoId)
                if (info != null) {
                    mapOf("ok" to true) + streamInfoToMap(info)
                } else {
                    mapOf("ok" to false, "error" to "RESOLVE_FAILED")
                }
            }
            "search" -> {
                val query = params["query"] as? String
                    ?: return mapOf("ok" to false, "error" to "query missing")
                val limit = (params["limit"] as? Int) ?: 0
                val tracks = searchTracksInternal(query, if (limit <= 0) Int.MAX_VALUE else limit)
                mapOf("ok" to true, "results" to tracks)
            }
            "suggest" -> {
                val query = params["query"] as? String
                    ?: return mapOf("ok" to false, "error" to "query missing")
                mapOf("ok" to true, "suggestions" to getSearchSuggestionsInternal(query))
            }
            "ping" -> mapOf("ok" to true, "pong" to true)
            "details" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                getVideoDetails(videoId)
            }
            "album" -> {
                val albumId = params["albumId"] as? String
                    ?: return mapOf("ok" to false, "error" to "albumId missing")
                getAlbumTracks(albumId)
            }
            "artist" -> {
                val artistId = params["artistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "artistId missing")
                val limit = (params["limit"] as? Int) ?: 0
                getArtistSongs(artistId, limit)
            }
            "related" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                val limit = (params["limit"] as? Int) ?: 0
                getRelatedSongs(videoId, limit)
            }
            "playlist" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val limit = (params["limit"] as? Int) ?: 0
                getPlaylistTracks(playlistId, limit)
            }
            "lyrics" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                getLyrics(videoId)
            }
            "media-info" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                getMediaInfo(videoId)
            }
            "charts" -> getCharts()
            "home" -> getHome()
            else -> mapOf("ok" to false, "error" to "unknown cmd: $cmd")
        }
    }
}