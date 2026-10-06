import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../models/search_models.dart';
import '../../providers/music_player_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/cached_artwork.dart';
import '../../widgets/inline_load_error.dart';
import '../../widgets/skeleton_loader.dart';

/// Dedicated per-category search results with infinite scroll (Fix-First
/// List #4 — "See All" pathway, unlimited/paginated beyond the mobile
/// live-preview limit).
///
/// Songs paginate over YouTube results (unchanged path). Batch C adds the
/// three local-library categories (albums/artists/playlists): the full
/// filtered set comes from the existing repo methods and is sliced in
/// memory with the same page contract — no catalog API is involved.
/// Query + category travel in the URL (`?q=&category=`); back returns via
/// `pop` to the existing search state. No raw exceptions surface.
class SearchCategoryResultsScreen extends ConsumerStatefulWidget {
  final String query;
  final SearchCategory category;

  const SearchCategoryResultsScreen({
    super.key,
    required this.query,
    required this.category,
  });

  @override
  ConsumerState<SearchCategoryResultsScreen> createState() =>
      _SearchCategoryResultsScreenState();
}

class _SearchCategoryResultsScreenState
    extends ConsumerState<SearchCategoryResultsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  final List<EnrichedSearchResult> _results = [];
  final List<AlbumSearchResult> _albums = [];
  final List<ArtistSearchResult> _artists = [];
  final List<PlaylistSearchResult> _playlists = [];

  /// Batch C — page-0 failure flag. Named error + Retry (not silent,
  /// not raw). Later-page failures keep existing results and stop.
  bool _page0Failed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage(0);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadPage(_currentPage + 1);
    }
  }

  Future<void> _loadPage(int page) async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final orchestrator = ref.read(searchOrchestratorProvider);
      switch (widget.category) {
        case SearchCategory.songs:
          // C10 — songs path byte-for-byte preserved.
          final newResults = await orchestrator.searchCategory(
            widget.query,
            widget.category,
            page: page,
          );
          if (!mounted) return;
          setState(() {
            _currentPage = page;
            if (page == 0) {
              _results.clear();
              _page0Failed = false;
            }
            _results.addAll(newResults);
            _hasMore = newResults.isNotEmpty;
            _isLoadingMore = false;
          });
        case SearchCategory.albums:
          final newAlbums = await orchestrator.searchCategoryAlbums(
            widget.query,
            page: page,
          );
          if (!mounted) return;
          setState(() {
            _currentPage = page;
            if (page == 0) {
              _albums.clear();
              _page0Failed = false;
            }
            _albums.addAll(newAlbums);
            _hasMore = newAlbums.isNotEmpty;
            _isLoadingMore = false;
          });
        case SearchCategory.artists:
          final newArtists = await orchestrator.searchCategoryArtists(
            widget.query,
            page: page,
          );
          if (!mounted) return;
          setState(() {
            _currentPage = page;
            if (page == 0) {
              _artists.clear();
              _page0Failed = false;
            }
            _artists.addAll(newArtists);
            _hasMore = newArtists.isNotEmpty;
            _isLoadingMore = false;
          });
        case SearchCategory.playlists:
          final newPlaylists = await orchestrator.searchCategoryPlaylists(
            widget.query,
            page: page,
          );
          if (!mounted) return;
          setState(() {
            _currentPage = page;
            if (page == 0) {
              _playlists.clear();
              _page0Failed = false;
            }
            _playlists.addAll(newPlaylists);
            _hasMore = newPlaylists.isNotEmpty;
            _isLoadingMore = false;
          });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        if (page == 0) _page0Failed = true;
      });
    }
  }

  void _retryFirstPage() {
    setState(() {
      _page0Failed = false;
      _currentPage = 0;
      _hasMore = true;
    });
    _loadPage(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _categoryLabel(widget.category),
              style: TextStyle(color: theme.textPrimary, fontSize: 18),
            ),
            Text(
              '"${widget.query}"',
              style: TextStyle(color: theme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(AuroraColors theme) {
    return switch (widget.category) {
      SearchCategory.songs => _buildSongBody(theme),
      SearchCategory.albums => _buildAlbumBody(theme),
      SearchCategory.artists => _buildArtistBody(theme),
      SearchCategory.playlists => _buildPlaylistBody(theme),
    };
  }

  /// Shared page-0 states: skeleton while first loading, curated error +
  /// Retry on first-page failure, named empty otherwise. Later pages keep
  /// existing rows on failure (stop, don't wipe).
  Widget _page0State({
    required AuroraColors theme,
    required bool isEmpty,
    required String emptyMessage,
    required Widget whenPopulated,
  }) {
    if (isEmpty && _isLoadingMore) return _buildSkeleton();
    if (isEmpty && _page0Failed) {
      return Center(
        child: InlineLoadError(
          message: "Couldn't load ${_categoryLabel(widget.category).toLowerCase()}",
          onRetry: _retryFirstPage,
        ),
      );
    }
    if (isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: TextStyle(color: theme.textSecondary, fontSize: 14),
        ),
      );
    }
    return whenPopulated;
  }

  Widget _buildSongBody(AuroraColors theme) {
    return _page0State(
      theme: theme,
      isEmpty: _results.isEmpty,
      emptyMessage: 'No songs found',
      whenPopulated: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _results.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _results.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _SongResultTile(result: _results[index]);
        },
      ),
    );
  }

  Widget _buildAlbumBody(AuroraColors theme) {
    return _page0State(
      theme: theme,
      isEmpty: _albums.isEmpty,
      emptyMessage: 'No albums found',
      whenPopulated: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _albums.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _albums.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _AlbumResultTile(album: _albums[index]);
        },
      ),
    );
  }

  Widget _buildArtistBody(AuroraColors theme) {
    return _page0State(
      theme: theme,
      isEmpty: _artists.isEmpty,
      emptyMessage: 'No artists found',
      whenPopulated: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _artists.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _artists.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _ArtistResultTile(artist: _artists[index]);
        },
      ),
    );
  }

  Widget _buildPlaylistBody(AuroraColors theme) {
    return _page0State(
      theme: theme,
      isEmpty: _playlists.isEmpty,
      emptyMessage: 'No playlists found',
      whenPopulated: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _playlists.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _playlists.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _PlaylistResultTile(playlist: _playlists[index]);
        },
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 10,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SkeletonLoader(height: 56),
      ),
    );
  }

  String _categoryLabel(SearchCategory c) {
    switch (c) {
      case SearchCategory.songs:
        return 'Songs';
      case SearchCategory.albums:
        return 'Albums';
      case SearchCategory.artists:
        return 'Artists';
      case SearchCategory.playlists:
        return 'Playlists';
    }
  }
}

class _SongResultTile extends ConsumerWidget {
  final EnrichedSearchResult result;

  const _SongResultTile({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedArtwork(
          imageUrl: result.thumbnail,
          width: 56,
          height: 56,
        ),
      ),
      title: Text(
        result.title,
        style: TextStyle(color: theme.textPrimary, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.artist,
        style: TextStyle(color: theme.textSecondary, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: Icon(Icons.play_arrow, color: theme.primary),
        onPressed: () => _play(ref),
      ),
      onTap: () => _play(ref),
    );
  }

  void _play(WidgetRef ref) {
    final musicRepo = ref.read(musicPlayerRepositoryProvider);
    musicRepo.playVideoId(result.videoId);
  }
}

/// Batch C — album row. Identity from the existing [AlbumSearchResult]
/// (name + artist + artwork-or-fallback, never invented); tap uses the
/// canonical album route with existing detail behavior.
class _AlbumResultTile extends StatelessWidget {
  final AlbumSearchResult album;

  const _AlbumResultTile({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    return ListTile(
      hoverColor: theme.surfaceElevated,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedArtwork(
          imageUrl: album.artworkUrl ?? '',
          cacheKey: album.albumId,
          width: 56,
          height: 56,
          placeholderIcon: Icons.album_rounded,
        ),
      ),
      title: Text(
        album.albumName,
        style: TextStyle(color: theme.textPrimary, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: album.artistName != null
          ? Text(
              album.artistName!,
              style: TextStyle(color: theme.textSecondary, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.textSecondary,
      ),
      onTap: () => context.push('/album/${album.albumId}'),
    );
  }
}

/// Batch C — artist row. Same contract as [_AlbumResultTile] against
/// [ArtistSearchResult]; tap uses the canonical artist route.
class _ArtistResultTile extends StatelessWidget {
  final ArtistSearchResult artist;

  const _ArtistResultTile({required this.artist});

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    return ListTile(
      hoverColor: theme.surfaceElevated,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedArtwork(
          imageUrl: artist.artworkUrl ?? '',
          cacheKey: artist.artistId,
          width: 56,
          height: 56,
          placeholderIcon: Icons.person_rounded,
        ),
      ),
      title: Text(
        artist.artistName,
        style: TextStyle(color: theme.textPrimary, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.textSecondary,
      ),
      onTap: () => context.push('/artist/${artist.artistId}'),
    );
  }
}

/// Batch C — playlist row. Same contract against [PlaylistSearchResult]
/// (own playlists only); tap uses the canonical playlist-detail route.
class _PlaylistResultTile extends StatelessWidget {
  final PlaylistSearchResult playlist;

  const _PlaylistResultTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    return ListTile(
      hoverColor: theme.surfaceElevated,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedArtwork(
          imageUrl: playlist.coverThumbnail ?? '',
          cacheKey: playlist.playlistId,
          width: 56,
          height: 56,
          placeholderIcon: Icons.playlist_play_rounded,
        ),
      ),
      title: Text(
        playlist.name,
        style: TextStyle(color: theme.textPrimary, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.itemCount} song${playlist.itemCount == 1 ? '' : 's'}',
        style: TextStyle(color: theme.textSecondary, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.textSecondary,
      ),
      onTap: () => context.push('/library/playlists/${playlist.playlistId}'),
    );
  }
}
