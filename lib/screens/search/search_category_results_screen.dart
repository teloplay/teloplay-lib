import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_extensions.dart';
import '../../widgets/loading/aurora_pulse_skeleton.dart';
import '../../providers/search_provider.dart';

/// Dedicated per-category search results with infinite scroll.
class SearchCategoryResultsScreen extends ConsumerStatefulWidget {
  final String query;
  final SearchCategory category;

  const SearchCategoryResultsScreen({
    super.key,
    required this.query,
    required this.category,
  });

  @override
  ConsumerState<SearchCategoryResultsScreen> createState() => _SearchCategoryResultsScreenState();
}

class _SearchCategoryResultsScreenState extends ConsumerState<SearchCategoryResultsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  bool _isLoadingMore = false;
  final List<SearchResult> _results = [];

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
        !_isLoadingMore) {
      _loadPage(_currentPage + 1);
    }
  }

  Future<void> _loadPage(int page) async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final newResults = await ref.read(searchControllerProvider.notifier)
          .searchCategory(widget.query, widget.category, page: page);

      setState(() {
        _currentPage = page;
        if (page == 0) {
          _results.clear();
        }
        _results.addAll(newResults);
        _isLoadingMore = false;
      });
    } catch (e) {
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
          children: [
            Text(
              widget.category.label,
              style: TextStyle(color: theme.textPrimary, fontSize: 18),
            ),
            Text(
              '"${widget.query}"',
              style: TextStyle(color: theme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
      body: _results.isEmpty && _isLoadingMore
          ? _buildSkeleton(context)
          : ListView.builder(
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
                return _SearchResultTile(
                  result: _results[index],
                  category: widget.category,
                );
              },
            ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 10,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AuroraPulseSkeleton.row(),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final SearchCategory category;

  const _SearchResultTile({
    required this.result,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedArtwork(
          url: result.thumbnail,
          size: 56,
        ),
      ),
      title: Text(
        result.title,
        style: TextStyle(color: theme.textPrimary, fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.subtitle,
        style: TextStyle(color: theme.textSecondary, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: category == SearchCategory.songs
          ? IconButton(
              icon: Icon(Icons.play_arrow, color: theme.primary),
              onPressed: () => _playResult(context, result),
            )
          : null,
      onTap: () => _navigateToDetail(context, result),
    );
  }

  void _playResult(BuildContext context, SearchResult result) {
    // Delegate to player
  }

  void _navigateToDetail(BuildContext context, SearchResult result) {
    switch (category) {
      case SearchCategory.songs:
        context.push('/song/${result.id}');
        break;
      case SearchCategory.albums:
        context.push('/album/${result.id}');
        break;
      case SearchCategory.artists:
        context.push('/artist/${result.id}');
        break;
      case SearchCategory.playlists:
        context.push('/playlist/${result.id}');
        break;
    }
  }
}