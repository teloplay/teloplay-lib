import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/playback/playback_engine.dart';
import '../providers/library_provider.dart';
import '../providers/music_player_provider.dart';
import '../widgets/playlist/add_to_playlist_sheet.dart';
import 'context_menu.dart';

/// P1-L — one shared song-menu opener so every track row shows the same
/// working actions. Wraps the existing [showContextMenu] (variant-aware,
/// desktop-popup/mobile-sheet adaptive) with the standard callback set:
/// Play Next / Add To Queue / Add To Playlist / Favorite / Go To
/// Artist-Album (only when ids exist). No new menu system, no new repo
/// surface beyond `MusicPlayerRepository.playNext`.
///
/// Callers pass [onRemove] for playlist/queue rows and [onDeleteDownload]
/// for cached rows. Share is intentionally unwired (no share infra exists;
/// the row hides via null-skip instead of showing dead).
Future<void> showTrackMenu({
  required BuildContext context,
  required WidgetRef ref,
  required SearchResult track,
  ContextMenuType type = ContextMenuType.song,
  VoidCallback? onRemove,
  Future<void> Function()? onDeleteDownload,
}) {
  final repo = ref.read(musicPlayerRepositoryProvider);
  final libraryRepo = ref.read(libraryRepositoryProvider);
  return showContextMenu(
    context: context,
    title: track.title,
    subtitle: track.author,
    type: type,
    onPlayNext: () => repo.playNext(track),
    onAddToQueue: () => repo.addToQueue(track),
    onAddToPlaylist: () =>
        AddToPlaylistSheet.show(context: context, track: track),
    onToggleFavorite: () => libraryRepo.toggleFavorite(
      songId: track.videoId,
      title: track.title,
      author: track.author,
      thumbnail: track.thumbnail,
    ),
    onGoToArtist: track.artistId != null && track.artistId!.isNotEmpty
        ? () => context.push('/artist/${track.artistId}')
        : null,
    onGoToAlbum: track.albumId != null && track.albumId!.isNotEmpty
        ? () => context.push('/album/${track.albumId}')
        : null,
    onRemove: onRemove,
    onDownload: onDeleteDownload == null
        ? null
        : () {
            onDeleteDownload();
          },
  );
}
