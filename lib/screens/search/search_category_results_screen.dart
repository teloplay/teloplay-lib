import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../providers/music_player_provider.dart';
import '../../providers/search_provider.dart';
import '../../widgets/cached_artwork.dart';
import '../../widgets/skeleton_loader.dart';

/// Dedicated per-category search results with infinite scroll (Fix-First
/// List #4 — "See All" pathway, unlimited/paginated beyond the mobile
/// live-preview limit).
///
/// ⚠️ Fix (Phase 0 v11 stabilization): rewritten against the real
/// [EnrichedSearchResult] shape (videoId/title/artist/album/thumbnail/
/// duration/isEnriched) — the original version was written against a
/// nonexistent `SearchResult` with `.id`/`.subtitle` fields that don't
/// exist on any type in this codebase, used `CachedArtwork(url: ...)`
/// (real param is `imageUrl`), called `MusicPlayerRepository.
/// playFromVideoId()` (real method is `playVideoId()`), and used
/// `context.pop()`/`context.push()` without importing go_router.
///
/// Per SearchOrchestrator's current scope, only [SearchCategory.songs] is
/// paginated for now (see search_provider.dart doc-comment) — other
/// categories show an empty state until that follow-up work lands.
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
      final newResults = await orchestrator.searchCategory(
        widget.query,
        widget.category,
        page: page,
      );

      if (!mounted) return;
      setState(() {
        _currentPage = page;
        if (page == 0) _results.clear();
        _results.addAll(newResults);
        _hasMore = newResults.isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
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
    if (_results.isEmpty && _isLoadingMore) {
      return _buildSkeleton();
    }

    if (_results.isEmpty && !_isLoadingMore) {
      return Center(
        child: Text(
          widget.category == SearchCategory.songs
              ? 'No songs found'
              : 'Not available yet for ${_categoryLabel(widget.category)}',
          style: TextStyle(color: theme.textSecondary, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
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
