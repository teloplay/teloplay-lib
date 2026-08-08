import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';

class PlayerMetadata extends ConsumerWidget {
  const PlayerMetadata({
    super.key,
    required this.track,
    required this.onAddToPlaylist,
    this.textAlign = TextAlign.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final SearchResult track;
  final ValueChanged<SearchResult> onAddToPlaylist;
  final TextAlign textAlign;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final isFav = ref.watch(isFavoriteProvider(track.videoId));

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: textAlign == TextAlign.center
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                track.title,
                style: AppTheme.trackTitleStyle.copyWith(
                  color: aurora.textPrimary,
                  fontSize: 13,
                ),
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                ref.read(libraryRepositoryProvider).toggleFavorite(
                      songId: track.videoId,
                      title: track.title,
                      author: track.author,
                      thumbnail: track.thumbnail,
                      durationSeconds: track.duration?.inSeconds,
                    );
              },
              child: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? aurora.error : aurora.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => onAddToPlaylist(track),
              child: Icon(
                Icons.playlist_add,
                color: aurora.textSecondary,
                size: 20,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          track.author,
          style: AppTheme.trackArtistStyle.copyWith(
            color: aurora.textSecondary,
            fontSize: 11,
          ),
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}