import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../models/now_playing_model.dart' show playbackErrorFor;
import '../../models/search_models.dart';
import '../../providers/music_player_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/app_router.dart' show seeAllLocation;
import '../../widgets/cached_artwork.dart';
import '../../widgets/inline_load_error.dart';
import '../../widgets/track_menu.dart';

/// Phase 6.5B — Global Search Architecture. SearchController's
/// multi-entity state (songs/albums/artists/playlists) consumed,
/// section-wise rendered — empty categories are fully hidden (locked UI
/// rule, see search_provider.dart SearchState doc-comment).
///
/// Phase 6.5 Batch 3: recent searches/suggestion dropdown behavior
/// unchanged, only the "showing results" part upgraded to multi-section.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _searchSubmitted = false;

  /// P1-K — result tab filter. Null = All. Pure view filter over the
  /// already-fetched [SearchState]: selecting a tab issues ZERO new
  /// searches and never touches routes (back navigation unaffected).
  /// Reset on every fresh submit so a new query always starts at All.
  SearchCategory? _activeTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    setState(() {
      _searchSubmitted = true;
      _activeTab = null;
    });
    _focusNode.unfocus();
    ref.read(searchControllerProvider.notifier).search(query);
    ref.read(suggestionControllerProvider.notifier).clear();
  }

  // ⚠️ Fix-First List #6 — Live Search Result videoId Validation.
  // Previously an empty/missing videoId would still navigate to
  // SongDetailsScreen, which then failed its own lookup and showed a
  // generic "Song not found" — misleading, since the real cause was an
  // invalid search result, not a missing library entry. Now caught here,
  // before navigation, with a message that actually explains what
  // happened.
  void _openSong(SearchResult song) {
    if (song.videoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This result is missing playback data and can\'t be opened.'),
        ),
      );
      return;
    }
    context.push('/song/${song.videoId}', extra: song);
  }

  void _openAlbum(AlbumSearchResult album) {
    context.push('/album/${album.albumId}');
  }

  void _openArtist(ArtistSearchResult artist) {
    context.push('/artist/${artist.artistId}');
  }

  void _openPlaylist(PlaylistSearchResult playlist) {
    context.push('/library/playlists/${playlist.playlistId}');
  }

  void _seeAll(SearchCategory category) {
    // P0-04 — the `/search/category` builder reads queryParameters, not
    // `extra`. Single URL builder lives in app_router.dart (unit-tested).
    final query = _searchController.text.trim();
    context.push(seeAllLocation(query, category));
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    final searchState = ref.watch(searchControllerProvider);
    final suggestionState = ref.watch(suggestionControllerProvider);

    final showRecentSearches = _searchController.text.isEmpty;
    final showSuggestions =
        _searchController.text.isNotEmpty && !_searchSubmitted;
    final showResults = !showRecentSearches && !showSuggestions;

    return Scaffold(
      backgroundColor: aurora.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                autofocus: true,
                style: TextStyle(color: aurora.textPrimary),
                onTapOutside: (_) {},
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums, playlists...',
                  hintStyle: TextStyle(color: aurora.textSecondary),
                  prefixIcon: Icon(Icons.search, color: aurora.textSecondary),
                  suffixIcon: searchState.isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: aurora.primary),
                          ),
                        )
                      : _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: aurora.textSecondary),
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(searchControllerProvider.notifier)
                                    .clear();
                                ref
                                    .read(
                                        suggestionControllerProvider.notifier)
                                    .clear();
                                setState(() {
                                  _searchSubmitted = false;
                                  _activeTab = null;
                                });
                              },
                            )
                          : null,
                  filled: true,
                  fillColor: aurora.surfaceRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: aurora.primary, width: 1),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchSubmitted = false);
                  ref
                      .read(searchControllerProvider.notifier)
                      .onQueryChanged(value);
                  ref
                      .read(suggestionControllerProvider.notifier)
                      .onQueryChanged(value);
                },
                onSubmitted: (value) {
                  // P1-K — fresh submit always restarts at the All tab.
                  setState(() {
                    _searchSubmitted = true;
                    _activeTab = null;
                  });
                  ref.read(searchControllerProvider.notifier).search(value);
                  ref.read(suggestionControllerProvider.notifier).clear();
                },
              ),
            ),
            if (showRecentSearches)
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final recentAsync = ref.watch(recentSearchesProvider);
                    return recentAsync.when(
                      data: (recent) {
                        if (recent.isEmpty) {
                          return Center(
                            child: Text(
                              'Search for songs, artists, albums, or playlists',
                              style: TextStyle(color: aurora.textSecondary),
                            ),
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            Text('Recent searches',
                                style: TextStyle(
                                    color: aurora.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: recent.map((queryString) {
                                return _RecentChip(
                                  query: queryString,
                                  onTap: () => _selectQuery(queryString),
                                  onDelete: () async {
                                    await ref
                                        .read(searchHistoryRepositoryProvider)
                                        .removeSearch(queryString);
                                    ref.invalidate(recentSearchesProvider);
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      // P1-A — recents failing is not "no recents".
                      error: (_, __) => InlineLoadError(
                        message: "Couldn't load recent searches",
                        onRetry: () => ref.invalidate(recentSearchesProvider),
                      ),
                    );
                  },
                ),
              ),
            if (showSuggestions)
              Expanded(
                child: suggestionState.suggestions.isEmpty &&
                        suggestionState.songPreviews.isEmpty &&
                        !suggestionState.isLoading
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          ...suggestionState.suggestions.map((suggestion) {
                            return ListTile(
                              // P1-M — desktop hover affordance (token fill).
                              hoverColor: aurora.surfaceElevated,
                              leading: Icon(Icons.search,
                                  size: 18, color: aurora.textSecondary),
                              title: Text(suggestion,
                                  style:
                                      TextStyle(color: aurora.textPrimary)),
                              onTap: () => _selectQuery(suggestion),
                            );
                          }),
                          if (suggestionState.songPreviews.isNotEmpty) ...[
                            Divider(height: 1, color: aurora.glassBorder),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 12, 16, 4),
                              child: Text(
                                'Songs',
                                style: TextStyle(
                                  color: aurora.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ...suggestionState.songPreviews.map((song) {
                              return ListTile(
                                // P1-M — desktop hover affordance.
                                hoverColor: aurora.surfaceElevated,
                                leading: CachedArtwork(
                                  imageUrl: song.thumbnail,
                                  cacheKey: song.videoId,
                                  width: 40,
                                  height: 40,
                                  borderRadius: BorderRadius.circular(4),
                                  memCacheWidth: 80,
                                  memCacheHeight: 80,
                                  placeholderIcon: Icons.music_note,
                                ),
                                title: Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: aurora.textPrimary,
                                        fontSize: 13)),
                                subtitle: Text(song.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: aurora.textSecondary,
                                        fontSize: 11)),
                                onTap: () => _openSong(song),
                              );
                            }),
                          ],
                        ],
                      ),
              ),
            // P1-K — tab filter bar. View-only: no new searches, no routes.
            // Shown only when at least one category has results.
            if (showResults &&
                searchState.error == null &&
                !searchState.isEmpty)
              _SearchTabBar(
                activeTab: _activeTab,
                hasSongs: searchState.songs.isNotEmpty,
                hasAlbums: searchState.albums.isNotEmpty,
                hasArtists: searchState.artists.isNotEmpty,
                hasPlaylists: searchState.playlists.isNotEmpty,
                onSelect: (tab) => setState(() => _activeTab = tab),
              ),
            if (showResults)
              Expanded(
                child: searchState.error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          // A8 — curated error via the shared classifier;
                          // raw exception text never reaches the user.
                          // Retry re-dispatches the submitted query
                          // through the existing search path.
                          child: InlineLoadError(
                            message: playbackErrorFor(
                                    searchState.error!)
                                .message,
                            onRetry: () => ref
                                .read(searchControllerProvider.notifier)
                                .search(searchState.query),
                          ),
                        ),
                      )
                    : searchState.isEmpty
                        ? Center(
                            child: Text(
                              searchState.isLoading
                                  ? 'Searching...'
                                  : 'No results',
                              style: TextStyle(color: aurora.textSecondary),
                            ),
                          )
                        : _MultiCategoryResults(
                            state: searchState,
                            repo: repo,
                            activeTab: _activeTab,
                            onOpenSong: _openSong,
                            onOpenAlbum: _openAlbum,
                            onOpenArtist: _openArtist,
                            onOpenPlaylist: _openPlaylist,
                            onSeeAll: _seeAll,
                          ),
              ),
          ],
        ),
      ),
    );
  }
}

/// P1-K — result tab filter bar. Pure view filter: tapping a tab only
/// flips local state (zero searches, zero routes). `null` = All.
class _SearchTabBar extends StatelessWidget {
  final SearchCategory? activeTab;
  final bool hasSongs;
  final bool hasAlbums;
  final bool hasArtists;
  final bool hasPlaylists;
  final void Function(SearchCategory?) onSelect;

  const _SearchTabBar({
    required this.activeTab,
    required this.hasSongs,
    required this.hasAlbums,
    required this.hasArtists,
    required this.hasPlaylists,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final tabs = <(String, SearchCategory?)>[
      ('All', null),
      if (hasSongs) ('Songs', SearchCategory.songs),
      if (hasAlbums) ('Albums', SearchCategory.albums),
      if (hasArtists) ('Artists', SearchCategory.artists),
      if (hasPlaylists) ('Playlists', SearchCategory.playlists),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, tab) = tabs[index];
          final selected = activeTab == tab;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => onSelect(tab),
            selectedColor: aurora.primary.withValues(alpha: 0.25),
            backgroundColor: aurora.surfaceRaised,
            side: BorderSide(
              color: selected ? aurora.primary : aurora.glassBorder,
            ),
            labelStyle: TextStyle(
              color: selected ? aurora.textPrimary : aurora.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          );
        },
      ),
    );
  }
}

/// Top Result → Songs → Albums → Artists → Playlists, section-wise —
/// each section only shown when that category has at least 1 result
/// (locked rule, see SearchState doc-comment).
class _MultiCategoryResults extends StatelessWidget {
  final SearchState state;
  final dynamic repo;
  final SearchCategory? activeTab;
  final void Function(SearchResult) onOpenSong;
  final void Function(AlbumSearchResult) onOpenAlbum;
  final void Function(ArtistSearchResult) onOpenArtist;
  final void Function(PlaylistSearchResult) onOpenPlaylist;
  final void Function(SearchCategory) onSeeAll;

  const _MultiCategoryResults({
    required this.state,
    required this.repo,
    required this.activeTab,
    required this.onOpenSong,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.onOpenPlaylist,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final topResult = activeTab == null ? state.topResult : null;

    // Defensive: chips only offer non-empty categories, so an empty tab
    // means stale state — show a named empty instead of a blank list.
    final tabEmpty = switch (activeTab) {
      null => false,
      SearchCategory.songs => state.songs.isEmpty,
      SearchCategory.albums => state.albums.isEmpty,
      SearchCategory.artists => state.artists.isEmpty,
      SearchCategory.playlists => state.playlists.isEmpty,
    };
    if (tabEmpty) {
      return Center(
        child: Text(
          'No ${activeTab!.name} results for this search',
          style: TextStyle(color: aurora.textSecondary),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // P1-K — typo-correction notice. Informational only: the results
        // below ARE for [query]; no revert action (original had nothing).
        if (state.correctedFrom != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.spellcheck_rounded,
                    size: 16, color: aurora.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing results for "${state.query}"',
                    style: TextStyle(
                        color: aurora.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (topResult != null) ...[
          _SectionHeader(title: 'Top Result'),
          _TopResultTile(
            entry: topResult,
            aurora: aurora,
            repo: repo,
            onOpenSong: onOpenSong,
            onOpenAlbum: onOpenAlbum,
            onOpenArtist: onOpenArtist,
            onOpenPlaylist: onOpenPlaylist,
          ),
        ],
        if ((activeTab == null || activeTab == SearchCategory.songs) &&
            state.songs.isNotEmpty) ...[
          _SectionHeader(
            title: 'Songs',
            onSeeAll: () => onSeeAll(SearchCategory.songs),
          ),
          ...state.songs.asMap().entries.map((entry) {
            final index = entry.key;
            final song = entry.value as SearchResult;
            return _SongTile(
              song: song,
              repo: repo,
              allSongs: state.songs.cast<SearchResult>(),
              index: index,
              onTap: () => onOpenSong(song),
            );
          }),
        ],
        if ((activeTab == null || activeTab == SearchCategory.albums) &&
            state.albums.isNotEmpty) ...[
          _SectionHeader(
            title: 'Albums',
            onSeeAll: () => onSeeAll(SearchCategory.albums),
          ),
          ...state.albums.map((album) => _AlbumTile(
                album: album,
                onTap: () => onOpenAlbum(album),
              )),
        ],
        if ((activeTab == null || activeTab == SearchCategory.artists) &&
            state.artists.isNotEmpty) ...[
          _SectionHeader(
            title: 'Artists',
            onSeeAll: () => onSeeAll(SearchCategory.artists),
          ),
          ...state.artists.map((artist) => _ArtistTile(
                artist: artist,
                onTap: () => onOpenArtist(artist),
              )),
        ],
        if ((activeTab == null || activeTab == SearchCategory.playlists) &&
            state.playlists.isNotEmpty) ...[
          _SectionHeader(
            title: 'Playlists',
            onSeeAll: () => onSeeAll(SearchCategory.playlists),
          ),
          ...state.playlists.map((playlist) => _PlaylistTile(
                playlist: playlist,
                onTap: () => onOpenPlaylist(playlist),
              )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: aurora.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                'See all',
                style: TextStyle(color: aurora.primary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopResultTile extends StatelessWidget {
  final ({SearchEntityType type, Object item}) entry;
  final dynamic aurora;
  final dynamic repo;
  final void Function(SearchResult) onOpenSong;
  final void Function(AlbumSearchResult) onOpenAlbum;
  final void Function(ArtistSearchResult) onOpenArtist;
  final void Function(PlaylistSearchResult) onOpenPlaylist;

  const _TopResultTile({
    required this.entry,
    required this.aurora,
    required this.repo,
    required this.onOpenSong,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.onOpenPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    switch (entry.type) {
      case SearchEntityType.song:
        final song = entry.item as SearchResult;
        return _SongTile(
          song: song,
          repo: repo,
          allSongs: [song],
          index: 0,
          onTap: () => onOpenSong(song),
        );
      case SearchEntityType.album:
        return _AlbumTile(
          album: entry.item as AlbumSearchResult,
          onTap: () => onOpenAlbum(entry.item as AlbumSearchResult),
        );
      case SearchEntityType.artist:
        return _ArtistTile(
          artist: entry.item as ArtistSearchResult,
          onTap: () => onOpenArtist(entry.item as ArtistSearchResult),
        );
      case SearchEntityType.playlist:
        return _PlaylistTile(
          playlist: entry.item as PlaylistSearchResult,
          onTap: () => onOpenPlaylist(entry.item as PlaylistSearchResult),
        );
    }
  }
}

class _SongTile extends ConsumerWidget {
  final SearchResult song;
  final dynamic repo;
  final List<SearchResult> allSongs;
  final int index;
  final VoidCallback onTap;

  const _SongTile({
    required this.song,
    required this.repo,
    required this.allSongs,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    return ListTile(
      // P1-M — desktop hover affordance.
      hoverColor: aurora.surfaceElevated,
      onTap: onTap,
      // P1-L — long-press menu (same actions as every other song row).
      onLongPress: () => showTrackMenu(context: context, ref: ref, track: song),
      leading: CachedArtwork(
        imageUrl: song.thumbnail,
        cacheKey: song.videoId,
        width: 48,
        height: 48,
        borderRadius: BorderRadius.circular(4),
        memCacheWidth: 96,
        memCacheHeight: 96,
        placeholderIcon: Icons.music_note,
      ),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: aurora.textPrimary, fontSize: 14)),
      subtitle: Text(song.author,
          style: TextStyle(color: aurora.textSecondary, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.playlist_add,
                color: aurora.textSecondary, size: 20),
            onPressed: () => repo.addToQueue(song),
          ),
          IconButton(
            icon: Icon(Icons.play_arrow, color: aurora.primary, size: 20),
            onPressed: () => repo.playFromContext(
              tracks: allSongs,
              startIndex: index,
              source: QueueSource.search,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final AlbumSearchResult album;
  final VoidCallback onTap;

  const _AlbumTile({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return ListTile(
      // P1-M — desktop hover affordance.
      hoverColor: aurora.surfaceElevated,
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: album.artworkUrl != null
            ? Image.network(
                album.artworkUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 48,
                  height: 48,
                  color: aurora.surfaceRaised,
                  child: Icon(Icons.album, color: aurora.textSecondary),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                color: aurora.surfaceRaised,
                child: Icon(Icons.album, color: aurora.textSecondary),
              ),
      ),
      title: Text(album.albumName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: aurora.textPrimary, fontSize: 14)),
      subtitle: album.artistName != null
          ? Text('Album · ${album.artistName}',
              style: TextStyle(color: aurora.textSecondary, fontSize: 12))
          : Text('Album',
              style: TextStyle(color: aurora.textSecondary, fontSize: 12)),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final ArtistSearchResult artist;
  final VoidCallback onTap;

  const _ArtistTile({required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return ListTile(
      // P1-M — desktop hover affordance.
      hoverColor: aurora.surfaceElevated,
      onTap: onTap,
      leading: ClipOval(
        child: artist.artworkUrl != null
            ? Image.network(
                artist.artworkUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 48,
                  height: 48,
                  color: aurora.surfaceRaised,
                  child: Icon(Icons.person, color: aurora.textSecondary),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                color: aurora.surfaceRaised,
                child: Icon(Icons.person, color: aurora.textSecondary),
              ),
      ),
      title: Text(artist.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: aurora.textPrimary, fontSize: 14)),
      subtitle: Text('Artist',
          style: TextStyle(color: aurora.textSecondary, fontSize: 12)),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final PlaylistSearchResult playlist;
  final VoidCallback onTap;

  const _PlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return ListTile(
      // P1-M — desktop hover affordance.
      hoverColor: aurora.surfaceElevated,
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: playlist.coverThumbnail != null
            ? Image.network(
                playlist.coverThumbnail!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 48,
                  height: 48,
                  color: aurora.surfaceRaised,
                  child:
                      Icon(Icons.queue_music, color: aurora.textSecondary),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                color: aurora.surfaceRaised,
                child: Icon(Icons.queue_music, color: aurora.textSecondary),
              ),
      ),
      title: Text(playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: aurora.textPrimary, fontSize: 14)),
      subtitle: Text(
          'Playlist · ${playlist.itemCount} song${playlist.itemCount == 1 ? '' : 's'}',
          style: TextStyle(color: aurora.textSecondary, fontSize: 12)),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip(
      {required this.query, required this.onTap, required this.onDelete});
  final String query;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.only(left: 14, right: 26, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: aurora.surfaceRaised,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 14, color: aurora.textSecondary),
                const SizedBox(width: 6),
                Text(query,
                    style: TextStyle(color: aurora.textPrimary, fontSize: 13)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: aurora.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}