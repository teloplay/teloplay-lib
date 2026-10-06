// android/app/src/main/kotlin/com/piyas/teloplay/MainActivity.kt
package com.piyas.teloplay

import android.util.Log
import com.arturo254.opentune.innertube.YouTube
import com.arturo254.opentune.innertube.NewPipeUtils
import com.arturo254.opentune.innertube.models.YouTubeClient
import com.arturo254.opentune.innertube.models.SongItem
import com.arturo254.opentune.innertube.models.AlbumItem
import com.arturo254.opentune.innertube.models.ArtistItem
import com.arturo254.opentune.innertube.models.PlaylistItem
import com.arturo254.opentune.innertube.models.YTItem
import com.arturo254.opentune.innertube.models.BrowseEndpoint
import com.arturo254.opentune.innertube.models.WatchEndpoint
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
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
                // ⚠️ OpenTune-parity multi-entity search (v11) — OpenTune-এর
                // search screen ঠিক এভাবেই করে: প্রতিটা SearchFilter-এর জন্য
                // আলাদা `YouTube.search(query, filter)`, আর প্রতিটা item
                // `ytItemToMap()` দিয়ে typed map। আগে `searchTracksInternal`
                // সব কিছু SongItem-এ collapse করত, ফলে Album/Artist/Playlist
                // item + section title পুরোপুরি হারিয়ে যেত।
                "searchSections" -> {
                    val query = call.argument<String>("query")
                    val limit = call.argument<Int>("limitPerSection") ?: 20
                    if (query == null) {
                        result.error("BAD_ARGS", "query missing", null)
                        return@setMethodCallHandler
                    }
                    mainScope.launch {
                        try {
                            val sections = withContext(Dispatchers.IO) {
                                searchSectionsInternal(query, limit)
                            }
                            result.success(sections)
                        } catch (e: Exception) {
                            // এক section fail করলেও বাকিগুলো যেন UI-তে যায় —
                            // খালি list দিলে Dart side-এ fallback কাজ করবে।
                            Log.e("TeloPlayInnertube", "searchSections failed", e)
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                }
                // OpenTune-এর `SearchSuggestions(queries, recommendedItems)` —
                // আগে শুধু `queries` যেত, `recommendedItems` (suggestion
                // dropdown-এর song/album preview) বাদ পড়ত।
                "suggestRich" -> {
                    val query = call.argument<String>("query")
                    if (query == null) {
                        result.error("BAD_ARGS", "query missing", null)
                        return@setMethodCallHandler
                    }
                    mainScope.launch {
                        try {
                            val rich = withContext(Dispatchers.IO) {
                                getSearchSuggestionsRichInternal(query)
                            }
                            result.success(rich)
                        } catch (e: Exception) {
                            Log.w("TeloPlayInnertube", "suggestRich failed: ${e.message}")
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "queries" to emptyList<String>(),
                                    "items" to emptyList<Map<String, Any?>>(),
                                )
                            )
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

    // ⚠️ OpenTune-parity multi-entity search (v11)
    //
    // OpenTune-এর search screen (`OnlineSearchResult.kt`-এর allModeSections)
    // এই filter order-টাই iterate করে — Songs → Videos → Albums → Artists →
    // Community playlists → Featured playlists। এখানে exact সেই order, যাতে
    // Android আর Windows একই section sequence দেয়।
    //
    // ⚠️ কেন `searchSummary()` ব্যবহার করা হয়নি: সেই path
    // `musicCardShelfRenderer` দিয়েও যায়, যেখানে UGC video-র subtitle
    // ভুলভাবে artist/album হিসেবে parse হয় — live probe-এ `author: "Apr 10"`,
    // `album: "INCOGLY"` পাওয়া গেছে (এটাই "title refine/clean" সমস্যা)।
    // `YouTube.search` + `SearchFilter` canonical song/album/artist row দেয়,
    // তাই metadata সবসময় ঠিক থাকে (probe: album="Safar", duration=217)।
    private val searchSectionFilters = listOf(
        YouTube.SearchFilter.FILTER_SONG to "Songs",
        YouTube.SearchFilter.FILTER_VIDEO to "Videos",
        YouTube.SearchFilter.FILTER_ALBUM to "Albums",
        YouTube.SearchFilter.FILTER_ARTIST to "Artists",
        YouTube.SearchFilter.FILTER_COMMUNITY_PLAYLIST to "Community playlists",
        YouTube.SearchFilter.FILTER_FEATURED_PLAYLIST to "Featured playlists",
    )

    private val topResultOrder = listOf(
        "Songs", "Albums", "Artists", "Community playlists", "Featured playlists",
    )

    private suspend fun searchSectionsInternal(
        query: String,
        limitPerSection: Int = 20,
    ): List<Map<String, Any?>> {
        ensureVisitorData()

        // সব filter parallel — OpenTune-ও per-filter আলাদা request পাঠায়।
        val perFilter: List<Pair<String, List<YTItem>>> = coroutineScope {
            searchSectionFilters.map { (filter, title) ->
                async {
                    val page = YouTube.search(query, filter).getOrNull()
                    val items = page?.items.orEmpty()
                        .distinctBy { it.id }
                        .let { if (limitPerSection <= 0) it else it.take(limitPerSection) }
                    title to items
                }
            }.awaitAll()
        }

        val sections = perFilter.mapNotNull { (title, items) ->
            if (items.isEmpty()) null
            else mapOf("title" to title, "items" to items.map { ytItemToMap(it) })
        }

        // OpenTune/Spotify-স্টাইল "Top results" — canonical section থেকে
        // priority অনুযায়ী (song → album → artist → playlist)। নিচের
        // section-এ item repeat হবে, ঠিক OpenTune-এর top-card-এর মতোই।
        val top = perFilter
            .sortedBy { (title, _) ->
                topResultOrder.indexOf(title).let { if (it < 0) Int.MAX_VALUE else it }
            }
            .flatMap { it.second }
            .take(4)
            .map { ytItemToMap(it) }

        return if (top.isEmpty()) sections
        else listOf(mapOf("title" to "Top results", "items" to top)) + sections
    }

    // OpenTune-এর `YouTube.searchSuggestions()` দুইটা অংশ দেয় — `queries`
    // (text) আর `recommendedItems` (item preview)। আগের
    // `getSearchSuggestionsInternal()` শুধু `queries` ফেরত দিত, তাই
    // suggestion dropdown-এর preview অংশটা দুই প্ল্যাটফর্মেই হারিয়ে যেত।
    private suspend fun getSearchSuggestionsRichInternal(
        query: String,
    ): Map<String, Any?> {
        ensureVisitorData()
        val result = YouTube.searchSuggestions(query).getOrNull()
            ?: return mapOf(
                "ok" to true,
                "queries" to emptyList<String>(),
                "items" to emptyList<Map<String, Any?>>(),
            )
        return mapOf(
            "ok" to true,
            "queries" to result.queries,
            "items" to result.recommendedItems.map { ytItemToMap(it) },
        )
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

    // ========== SHARED ITEM MAPPERS (Windows CLI parity, additive only) ==========

    private fun songToFullMap(song: SongItem): Map<String, Any?> = mapOf(
        "type" to "song",
        "videoId" to song.id,
        "title" to song.title,
        "author" to (song.artists.firstOrNull()?.name ?: "Unknown"),
        "artistId" to song.artists.firstOrNull()?.id,
        "allArtistNames" to song.artists.map { it.name },
        "allArtistIds" to song.artists.map { it.id },
        "thumbnail" to song.thumbnail,
        "duration" to (song.duration ?: 0),
        "albumId" to song.album?.id,
        "albumName" to song.album?.name,
        "explicit" to song.explicit,
        "chartPosition" to song.chartPosition,
        "chartChange" to song.chartChange,
        "setVideoId" to song.setVideoId,
    )

    private fun albumItemToMap(album: AlbumItem): Map<String, Any?> = mapOf(
        "type" to "album",
        "albumId" to album.browseId,
        "playlistId" to album.playlistId,
        "title" to album.title,
        "artists" to (album.artists?.map { a -> mapOf("name" to a.name, "id" to a.id) } ?: emptyList<Map<String, Any?>>()),
        "year" to (album.year ?: 0),
        "thumbnail" to album.thumbnail,
        "explicit" to album.explicit,
        "releaseType" to album.releaseType.name,
    )

    private fun artistItemToMap(artist: ArtistItem): Map<String, Any?> = mapOf(
        "type" to "artist",
        "artistId" to artist.id,
        "title" to artist.title,
        "thumbnail" to artist.thumbnail,
        "channelId" to artist.channelId,
        "subscriberCountText" to artist.subscriberCountText,
        "monthlyListenerCountText" to artist.monthlyListenerCountText,
    )

    private fun playlistItemToMap(playlist: PlaylistItem): Map<String, Any?> = mapOf(
        "type" to "playlist",
        "playlistId" to playlist.id,
        "title" to playlist.title,
        "author" to (playlist.author?.name ?: ""),
        "authorId" to playlist.author?.id,
        "songCountText" to playlist.songCountText,
        "thumbnail" to playlist.thumbnail,
        "isEditable" to playlist.isEditable,
    )

    private fun ytItemToMap(item: YTItem): Map<String, Any?> = when (item) {
        is SongItem -> songToFullMap(item)
        is AlbumItem -> albumItemToMap(item)
        is ArtistItem -> artistItemToMap(item)
        is PlaylistItem -> playlistItemToMap(item)
    }

    private fun searchFilterFromName(name: String): YouTube.SearchFilter? = when (name.lowercase()) {
        "song", "songs" -> YouTube.SearchFilter.FILTER_SONG
        "video", "videos" -> YouTube.SearchFilter.FILTER_VIDEO
        "album", "albums" -> YouTube.SearchFilter.FILTER_ALBUM
        "artist", "artists" -> YouTube.SearchFilter.FILTER_ARTIST
        "featured", "featured_playlist", "featured-playlist" -> YouTube.SearchFilter.FILTER_FEATURED_PLAYLIST
        "community", "community_playlist", "community-playlist" -> YouTube.SearchFilter.FILTER_COMMUNITY_PLAYLIST
        else -> null
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
            "otherVersions" to albumPage.otherVersions.map { album -> albumItemToMap(album) },
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
            "channelId" to artist.channelId,
            "subscriberCountText" to artist.subscriberCountText,
            "monthlyListenerCountText" to artist.monthlyListenerCountText,
            "description" to artistPage.description,
            "songCount" to limited.size,
            "songs" to limited.map { song -> songToMap(song) },
            "sections" to artistPage.sections.map { section ->
                mapOf(
                    "title" to section.title,
                    "moreBrowseId" to section.moreEndpoint?.browseId,
                    "moreParams" to section.moreEndpoint?.params,
                    "items" to section.items.map { item -> ytItemToMap(item) },
                )
            },
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
            "albums" to relatedPage.albums.map { album -> albumItemToMap(album) },
            "artists" to relatedPage.artists.map { artist -> artistItemToMap(artist) },
            "playlists" to relatedPage.playlists.map { playlist -> playlistItemToMap(playlist) },
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
            "songsContinuation" to playlistPage.songsContinuation,
            "continuation" to playlistPage.continuation,
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
            "continuation" to chartsPage.continuation,
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
            "continuation" to homePage.continuation,
            "chips" to (homePage.chips.orEmpty().map { chip ->
                mapOf(
                    "title" to chip.title,
                    "browseId" to chip.endpoint?.browseId,
                    "params" to chip.endpoint?.params,
                )
            }),
            "sections" to homePage.sections.map { section ->
                mapOf(
                    "title" to section.title,
                    "songs" to section.items.filterIsInstance<SongItem>().map { song -> songToMap(song) },
                )
            },
        )
    }

// 10. MOODS & GENRES — YouTube.moodAndGenres()
    private suspend fun getMoodAndGenres(): Map<String, Any?> {
        ensureVisitorData()

        val list = YouTube.moodAndGenres().getOrNull()
            ?: return mapOf("ok" to false, "error" to "MOODS_GENRES_FAILED")

        return mapOf(
            "ok" to true,
            "items" to list.map { mg ->
                mapOf(
                    "title" to mg.title,
                    "items" to mg.items.map { item ->
                        mapOf(
                            "title" to item.title,
                            "stripeColor" to item.stripeColor,
                            "browseId" to item.endpoint.browseId,
                            "params" to item.endpoint.params,
                        )
                    }
                )
            }
        )
    }

    // 11. NEW RELEASES — YouTube.newReleaseAlbums()
    private suspend fun getNewReleases(): Map<String, Any?> {
        ensureVisitorData()

        val list = YouTube.newReleaseAlbums().getOrNull()
            ?: return mapOf("ok" to false, "error" to "NEW_RELEASES_FAILED")

        return mapOf(
            "ok" to true,
            "albums" to list.map { album ->
                mapOf(
                    "albumId" to album.id,
                    "title" to album.title,
                    "year" to album.year,
                    "thumbnail" to album.thumbnail,
                    "artists" to (album.artists?.map { a ->
                        mapOf("name" to a.name, "id" to a.id)
                    } ?: emptyList<Map<String, Any?>>()),
                )
            }
        )
    }

    // 12. EXPLORE — YouTube.explore()
    private suspend fun getExplore(): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.explore().getOrNull()
            ?: return mapOf("ok" to false, "error" to "EXPLORE_FAILED")

        return mapOf(
            "ok" to true,
            "newReleaseAlbums" to page.newReleaseAlbums.map { album -> albumItemToMap(album) },
            "moodAndGenres" to page.moodAndGenres.map { item ->
                mapOf(
                    "title" to item.title,
                    "stripeColor" to item.stripeColor,
                    "browseId" to item.endpoint.browseId,
                    "params" to item.endpoint.params,
                )
            },
        )
    }

    // 13. BROWSE — generic drill-down (moods/genres chips, section endpoints)
    private suspend fun browsePage(browseId: String, params: String?): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.browse(browseId, params).getOrNull()
            ?: return mapOf("ok" to false, "error" to "BROWSE_FAILED")

        return mapOf(
            "ok" to true,
            "browseId" to browseId,
            "title" to result.title,
            "thumbnail" to result.thumbnail,
            "items" to result.items.map { section ->
                mapOf(
                    "title" to section.title,
                    "items" to section.items.map { item -> ytItemToMap(item) },
                )
            },
        )
    }

    // 14. FILTERED SEARCH — YouTube.search() with SearchFilter
    private suspend fun searchFiltered(query: String, filterName: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val filter = searchFilterFromName(filterName)
            ?: return mapOf("ok" to false, "error" to "UNKNOWN_FILTER: $filterName")

        val page = YouTube.search(query, filter).getOrNull()
            ?: return mapOf("ok" to false, "error" to "SEARCH_FAILED")

        val items = if (limit <= 0) page.items else page.items.take(limit)

        return mapOf(
            "ok" to true,
            "query" to query,
            "filter" to filterName,
            "continuation" to page.continuation,
            "results" to items.map { item -> ytItemToMap(item) },
        )
    }

    // 15. SEARCH CONTINUATION
    private suspend fun searchContinuationPage(continuation: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.searchContinuation(continuation).getOrNull()
            ?: return mapOf("ok" to false, "error" to "SEARCH_CONTINUATION_FAILED")

        val items = if (limit <= 0) page.items else page.items.take(limit)

        return mapOf(
            "ok" to true,
            "continuation" to page.continuation,
            "results" to items.map { item -> ytItemToMap(item) },
        )
    }

    // 16. PLAYLIST CONTINUATION
    private suspend fun playlistContinuationPage(continuation: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.playlistContinuation(continuation).getOrNull()
            ?: return mapOf("ok" to false, "error" to "PLAYLIST_CONTINUATION_FAILED")

        val songs = if (limit <= 0) page.songs else page.songs.take(limit)

        return mapOf(
            "ok" to true,
            "continuation" to page.continuation,
            "tracks" to songs.map { song -> songToFullMap(song) },
        )
    }

    // 17. ALBUM SONGS via playlistId — YouTube.albumSongs()
    private suspend fun albumSongsPage(playlistId: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val songs = YouTube.albumSongs(playlistId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "ALBUM_SONGS_FAILED")

        val limited = if (limit <= 0) songs else songs.take(limit)

        return mapOf(
            "ok" to true,
            "playlistId" to playlistId,
            "trackCount" to limited.size,
            "tracks" to limited.map { song -> songToFullMap(song) },
        )
    }

    // 18. ARTIST ITEMS — full discography section drill-down
    private suspend fun artistItemsPage(browseId: String, params: String?, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val endpoint = BrowseEndpoint(browseId = browseId, params = params)
        val page = YouTube.artistItems(endpoint).getOrNull()
            ?: return mapOf("ok" to false, "error" to "ARTIST_ITEMS_FAILED")

        val items = if (limit <= 0) page.items else page.items.take(limit)

        return mapOf(
            "ok" to true,
            "title" to page.title,
            "continuation" to page.continuation,
            "items" to items.map { item -> ytItemToMap(item) },
        )
    }

    // 19. ARTIST ITEMS CONTINUATION
    private suspend fun artistItemsContinuationPage(continuation: String, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.artistItemsContinuation(continuation).getOrNull()
            ?: return mapOf("ok" to false, "error" to "ARTIST_ITEMS_CONTINUATION_FAILED")

        val items = if (limit <= 0) page.items else page.items.take(limit)

        return mapOf(
            "ok" to true,
            "continuation" to page.continuation,
            "items" to items.map { item -> ytItemToMap(item) },
        )
    }

    // 20. LIBRARY — logged-in user library (needs cookie, else LIBRARY_FAILED)
    private suspend fun libraryPage(browseId: String, tabIndex: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.library(browseId, tabIndex).getOrNull()
            ?: return mapOf("ok" to false, "error" to "LIBRARY_FAILED")

        return mapOf(
            "ok" to true,
            "continuation" to page.continuation,
            "items" to page.items.map { item -> ytItemToMap(item) },
        )
    }

    // 21. LIBRARY CONTINUATION
    private suspend fun libraryContinuationPage(continuation: String): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.libraryContinuation(continuation).getOrNull()
            ?: return mapOf("ok" to false, "error" to "LIBRARY_CONTINUATION_FAILED")

        return mapOf(
            "ok" to true,
            "continuation" to page.continuation,
            "items" to page.items.map { item -> ytItemToMap(item) },
        )
    }

    // 22. LIBRARY RECENT ACTIVITY
    private suspend fun libraryRecentActivityPage(): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.libraryRecentActivity().getOrNull()
            ?: return mapOf("ok" to false, "error" to "LIBRARY_RECENT_FAILED")

        return mapOf(
            "ok" to true,
            "continuation" to page.continuation,
            "items" to page.items.map { item -> ytItemToMap(item) },
        )
    }

    // 23. HISTORY — YT Music watch history (needs login)
    private suspend fun historyPage(): Map<String, Any?> {
        ensureVisitorData()

        val page = YouTube.musicHistory().getOrNull()
            ?: return mapOf("ok" to false, "error" to "HISTORY_FAILED")

        return mapOf(
            "ok" to true,
            "sections" to (page.sections.orEmpty().map { section ->
                mapOf(
                    "title" to section.title,
                    "songs" to section.songs.map { song -> songToFullMap(song) },
                )
            }),
        )
    }

    // 24. ACCOUNT INFO — logged-in account (needs cookie)
    private suspend fun accountInfoPage(): Map<String, Any?> {
        ensureVisitorData()

        val info = YouTube.accountInfo().getOrNull()
            ?: return mapOf("ok" to false, "error" to "ACCOUNT_INFO_FAILED")

        return mapOf(
            "ok" to true,
            "name" to info.name,
            "email" to info.email,
            "channelHandle" to info.channelHandle,
            "thumbnailUrl" to info.thumbnailUrl,
        )
    }

    // 25. QUEUE — resolve SongItems for videoIds / playlistId
    private suspend fun queueSongs(videoIds: List<String>, playlistId: String?, limit: Int = 0): Map<String, Any?> {
        ensureVisitorData()

        val songs = YouTube.queue(
            videoIds = videoIds.ifEmpty { null },
            playlistId = playlistId,
        ).getOrNull()
            ?: return mapOf("ok" to false, "error" to "QUEUE_FAILED")

        val limited = if (limit <= 0) songs else songs.take(limit)

        return mapOf(
            "ok" to true,
            "songs" to limited.map { song -> songToFullMap(song) },
        )
    }

    // 26. TRANSCRIPT — timed captions (synced-lyrics source)
    private suspend fun transcriptText(videoId: String): Map<String, Any?> {
        ensureVisitorData()

        val text = YouTube.transcript(videoId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "TRANSCRIPT_NOT_FOUND")

        return mapOf(
            "ok" to true,
            "videoId" to videoId,
            "transcript" to text,
            "isSynced" to true,
        )
    }

    // 27. WATCH NEXT — full up-next queue with continuation + endpoint flags
    private suspend fun watchNext(videoId: String, playlistId: String?, params: String?, continuation: String?): Map<String, Any?> {
        ensureVisitorData()

        val endpoint = WatchEndpoint(videoId = videoId, playlistId = playlistId, params = params)
        val next = YouTube.next(endpoint, continuation).getOrNull()
            ?: return mapOf("ok" to false, "error" to "NEXT_FAILED")

        return mapOf(
            "ok" to true,
            "videoId" to videoId,
            "title" to next.title,
            "currentIndex" to next.currentIndex,
            "continuation" to next.continuation,
            "hasLyrics" to (next.lyricsEndpoint != null),
            "hasRelated" to (next.relatedEndpoint != null),
            "lyricsBrowseId" to next.lyricsEndpoint?.browseId,
            "lyricsParams" to next.lyricsEndpoint?.params,
            "relatedBrowseId" to next.relatedEndpoint?.browseId,
            "songs" to next.items.map { song -> songToFullMap(song) },
        )
    }

    // 28. LIKE VIDEO — toggle (needs login)
    private suspend fun likeVideoToggle(videoId: String, like: Boolean): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.likeVideo(videoId, like)
        return if (result.isSuccess) {
            mapOf("ok" to true, "videoId" to videoId, "liked" to like)
        } else {
            mapOf("ok" to false, "error" to "LIKE_VIDEO_FAILED")
        }
    }

    // 29. LIKE PLAYLIST — toggle (needs login)
    private suspend fun likePlaylistToggle(playlistId: String, like: Boolean): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.likePlaylist(playlistId, like)
        return if (result.isSuccess) {
            mapOf("ok" to true, "playlistId" to playlistId, "liked" to like)
        } else {
            mapOf("ok" to false, "error" to "LIKE_PLAYLIST_FAILED")
        }
    }

    // 30. SUBSCRIBE CHANNEL — toggle (needs login)
    private suspend fun subscribeToggle(channelId: String, subscribe: Boolean): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.subscribeChannel(channelId, subscribe)
        return if (result.isSuccess) {
            mapOf("ok" to true, "channelId" to channelId, "subscribed" to subscribe)
        } else {
            mapOf("ok" to false, "error" to "SUBSCRIBE_FAILED")
        }
    }

    // 31. CHANNEL ID — resolve artist browseId to channelId
    private suspend fun channelIdOf(browseId: String): Map<String, Any?> {
        ensureVisitorData()

        return try {
            val channelId = YouTube.getChannelId(browseId)
            mapOf("ok" to true, "browseId" to browseId, "channelId" to channelId)
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to "CHANNEL_ID_FAILED")
        }
    }

    // 32. PLAYLIST CREATE (needs login)
    private suspend fun playlistCreate(title: String): Map<String, Any?> {
        ensureVisitorData()

        val playlistId = YouTube.createPlaylist(title).getOrNull()
            ?: return mapOf("ok" to false, "error" to "PLAYLIST_CREATE_FAILED")

        return mapOf("ok" to true, "playlistId" to playlistId)
    }

    // 33. PLAYLIST DELETE (needs login)
    private suspend fun playlistDelete(playlistId: String): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.deletePlaylist(playlistId)
        return if (result.isSuccess) {
            mapOf("ok" to true, "playlistId" to playlistId)
        } else {
            mapOf("ok" to false, "error" to "PLAYLIST_DELETE_FAILED")
        }
    }

    // 34. PLAYLIST RENAME (needs login)
    private suspend fun playlistRename(playlistId: String, name: String): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.renamePlaylist(playlistId, name)
        return if (result.isSuccess) {
            mapOf("ok" to true, "playlistId" to playlistId, "name" to name)
        } else {
            mapOf("ok" to false, "error" to "PLAYLIST_RENAME_FAILED")
        }
    }

    // 35. PLAYLIST ADD SONG (needs login)
    private suspend fun playlistAdd(playlistId: String, videoId: String): Map<String, Any?> {
        ensureVisitorData()

        val setVideoId = YouTube.addToPlaylist(playlistId, videoId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "PLAYLIST_ADD_FAILED")

        return mapOf(
            "ok" to true,
            "playlistId" to playlistId,
            "videoId" to videoId,
            "setVideoId" to setVideoId,
        )
    }

    // 36. PLAYLIST ADD PLAYLIST (needs login)
    private suspend fun playlistAddPlaylist(playlistId: String, addPlaylistId: String): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.addPlaylistToPlaylist(playlistId, addPlaylistId)
        return if (result.isSuccess) {
            mapOf("ok" to true, "playlistId" to playlistId)
        } else {
            mapOf("ok" to false, "error" to "PLAYLIST_ADD_PLAYLIST_FAILED")
        }
    }

    // 37. PLAYLIST REMOVE SONG (needs login)
    private suspend fun playlistRemove(playlistId: String, videoId: String, setVideoId: String): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.removeFromPlaylist(playlistId, videoId, setVideoId)
        return if (result.isSuccess) {
            mapOf("ok" to true, "playlistId" to playlistId)
        } else {
            mapOf("ok" to false, "error" to "PLAYLIST_REMOVE_FAILED")
        }
    }

    // 38. PLAYLIST MOVE SONG (needs login)
    private suspend fun playlistMove(playlistId: String, setVideoId: String, successorSetVideoId: String?): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.moveSongPlaylist(playlistId, setVideoId, successorSetVideoId)
        return if (result.isSuccess) {
            mapOf("ok" to true, "playlistId" to playlistId)
        } else {
            mapOf("ok" to false, "error" to "PLAYLIST_MOVE_FAILED")
        }
    }

    // 39. PLAYLIST ENTRY SET-VIDEO-IDS
    private suspend fun playlistEntrySetVideoIds(playlistId: String, videoId: String): Map<String, Any?> {
        ensureVisitorData()

        val ids = YouTube.playlistEntrySetVideoIds(playlistId, videoId).getOrNull()
            ?: return mapOf("ok" to false, "error" to "PLAYLIST_ENTRY_LOOKUP_FAILED")

        return mapOf(
            "ok" to true,
            "playlistId" to playlistId,
            "videoId" to videoId,
            "setVideoIds" to ids,
        )
    }

    // 40. REGISTER PLAYBACK — playback stats ping
    private suspend fun registerPlaybackEvent(playbackTracking: String, playlistId: String?): Map<String, Any?> {
        ensureVisitorData()

        val result = YouTube.registerPlayback(playlistId = playlistId, playbackTracking = playbackTracking)
        return if (result.isSuccess) {
            mapOf("ok" to true)
        } else {
            mapOf("ok" to false, "error" to "REGISTER_PLAYBACK_FAILED")
        }
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
            "charts" -> {
                val continuation = (params["continuation"] as? String)?.takeUnless { it.isBlank() }
                if (continuation != null) {
                    val page = YouTube.getChartsPage(continuation).getOrNull()
                        ?: return mapOf("ok" to false, "error" to "CHARTS_FAILED")
                    mapOf(
                        "ok" to true,
                        "continuation" to page.continuation,
                        "sections" to page.sections.map { section ->
                            mapOf(
                                "title" to section.title,
                                "chartType" to section.chartType.name,
                                "songs" to section.items.filterIsInstance<SongItem>().map { song -> songToFullMap(song) },
                            )
                        },
                    )
                } else getCharts()
            }
            "home" -> {
                val continuation = (params["continuation"] as? String)?.takeUnless { it.isBlank() }
                val homeParams = (params["params"] as? String)?.takeUnless { it.isBlank() }
                if (continuation != null || homeParams != null) {
                    val page = YouTube.home(continuation, homeParams).getOrNull()
                        ?: return mapOf("ok" to false, "error" to "HOME_FAILED")
                    mapOf(
                        "ok" to true,
                        "continuation" to page.continuation,
                        "sections" to page.sections.map { section ->
                            mapOf(
                                "title" to section.title,
                                "songs" to section.items.filterIsInstance<SongItem>().map { song -> songToFullMap(song) },
                            )
                        },
                    )
                } else getHome()
            }
            "moods-and-genres" -> getMoodAndGenres()
            "new-releases" -> getNewReleases()
            "explore" -> getExplore()
            "browse" -> {
                val browseId = params["browseId"] as? String
                    ?: return mapOf("ok" to false, "error" to "browseId missing")
                val browseParams = (params["params"] as? String)?.takeUnless { it.isBlank() }
                browsePage(browseId, browseParams)
            }
            "search-filter" -> {
                val query = params["query"] as? String
                    ?: return mapOf("ok" to false, "error" to "query missing")
                val filter = params["filter"] as? String ?: "song"
                val limit = (params["limit"] as? Int) ?: 0
                searchFiltered(query, filter, limit)
            }
            "search-continuation" -> {
                val continuation = params["continuation"] as? String
                    ?: return mapOf("ok" to false, "error" to "continuation missing")
                val limit = (params["limit"] as? Int) ?: 0
                searchContinuationPage(continuation, limit)
            }
            "playlist-continuation" -> {
                val continuation = params["continuation"] as? String
                    ?: return mapOf("ok" to false, "error" to "continuation missing")
                val limit = (params["limit"] as? Int) ?: 0
                playlistContinuationPage(continuation, limit)
            }
            "album-songs" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val limit = (params["limit"] as? Int) ?: 0
                albumSongsPage(playlistId, limit)
            }
            "artist-items" -> {
                val browseId = params["browseId"] as? String
                    ?: return mapOf("ok" to false, "error" to "browseId missing")
                val itemParams = (params["params"] as? String)?.takeUnless { it.isBlank() }
                val limit = (params["limit"] as? Int) ?: 0
                artistItemsPage(browseId, itemParams, limit)
            }
            "artist-items-continuation" -> {
                val continuation = params["continuation"] as? String
                    ?: return mapOf("ok" to false, "error" to "continuation missing")
                val limit = (params["limit"] as? Int) ?: 0
                artistItemsContinuationPage(continuation, limit)
            }
            "library" -> {
                val browseId = (params["browseId"] as? String)?.takeUnless { it.isBlank() }
                    ?: "FEmusic_library_landing"
                val tabIndex = (params["tabIndex"] as? Int) ?: 0
                libraryPage(browseId, tabIndex)
            }
            "library-continuation" -> {
                val continuation = params["continuation"] as? String
                    ?: return mapOf("ok" to false, "error" to "continuation missing")
                libraryContinuationPage(continuation)
            }
            "library-recent" -> libraryRecentActivityPage()
            "history" -> historyPage()
            "account-info" -> accountInfoPage()
            "queue" -> {
                @Suppress("UNCHECKED_CAST")
                val videoIds = (params["videoIds"] as? List<*>)?.mapNotNull { it as? String }.orEmpty()
                val queuePlaylistId = (params["playlistId"] as? String)?.takeUnless { it.isBlank() }
                if (videoIds.isEmpty() && queuePlaylistId == null) {
                    return mapOf("ok" to false, "error" to "videoIds or playlistId missing")
                }
                val limit = (params["limit"] as? Int) ?: 0
                queueSongs(videoIds, queuePlaylistId, limit)
            }
            "transcript" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                transcriptText(videoId)
            }
            "next" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                val nextPlaylistId = (params["playlistId"] as? String)?.takeUnless { it.isBlank() }
                val nextParams = (params["params"] as? String)?.takeUnless { it.isBlank() }
                val nextContinuation = (params["continuation"] as? String)?.takeUnless { it.isBlank() }
                watchNext(videoId, nextPlaylistId, nextParams, nextContinuation)
            }
            "like-video" -> {
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                val like = (params["like"] as? Boolean) ?: true
                likeVideoToggle(videoId, like)
            }
            "like-playlist" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val like = (params["like"] as? Boolean) ?: true
                likePlaylistToggle(playlistId, like)
            }
            "subscribe" -> {
                val channelId = params["channelId"] as? String
                    ?: return mapOf("ok" to false, "error" to "channelId missing")
                val subscribe = (params["subscribe"] as? Boolean) ?: true
                subscribeToggle(channelId, subscribe)
            }
            "channel-id" -> {
                val browseId = params["browseId"] as? String
                    ?: return mapOf("ok" to false, "error" to "browseId missing")
                channelIdOf(browseId)
            }
            "playlist-create" -> {
                val title = params["title"] as? String
                    ?: return mapOf("ok" to false, "error" to "title missing")
                playlistCreate(title)
            }
            "playlist-delete" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                playlistDelete(playlistId)
            }
            "playlist-rename" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val name = params["name"] as? String
                    ?: return mapOf("ok" to false, "error" to "name missing")
                playlistRename(playlistId, name)
            }
            "playlist-add" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                playlistAdd(playlistId, videoId)
            }
            "playlist-add-playlist" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val addPlaylistId = params["addPlaylistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "addPlaylistId missing")
                playlistAddPlaylist(playlistId, addPlaylistId)
            }
            "playlist-remove" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                val setVideoId = params["setVideoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "setVideoId missing")
                playlistRemove(playlistId, videoId, setVideoId)
            }
            "playlist-move" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val setVideoId = params["setVideoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "setVideoId missing")
                val successorSetVideoId = (params["successorSetVideoId"] as? String)?.takeUnless { it.isBlank() }
                playlistMove(playlistId, setVideoId, successorSetVideoId)
            }
            "playlist-entry-set-video-ids" -> {
                val playlistId = params["playlistId"] as? String
                    ?: return mapOf("ok" to false, "error" to "playlistId missing")
                val videoId = params["videoId"] as? String
                    ?: return mapOf("ok" to false, "error" to "videoId missing")
                playlistEntrySetVideoIds(playlistId, videoId)
            }
            "register-playback" -> {
                val playbackTracking = params["playbackTracking"] as? String
                    ?: return mapOf("ok" to false, "error" to "playbackTracking missing")
                val trackingPlaylistId = (params["playlistId"] as? String)?.takeUnless { it.isBlank() }
                registerPlaybackEvent(playbackTracking, trackingPlaylistId)
            }
            else -> mapOf("ok" to false, "error" to "unknown cmd: $cmd")
        }
    }
}