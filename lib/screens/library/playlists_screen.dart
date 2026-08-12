import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../models/playlist_model.dart';
import '../../providers/playlist_provider.dart';
import '../../widgets/cached_artwork.dart';
import 'playlist_detail_screen.dart';

/// সব playlist-এর full list — Library "Playlists → See all" থেকে খোলা
/// হয়, এবং এখান থেকেই নতুন playlist তৈরি করা যায় (FAB)।
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final theme = context.aurora;
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text('New Playlist', style: TextStyle(color: theme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: theme.textSecondary),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text('Create', style: TextStyle(color: theme.primary)),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;

    final playlistId = await ref
        .read(playlistRepositoryProvider)
        .createPlaylist(name: name.trim());

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
  ) async {
    final theme = context.aurora;
    final controller = TextEditingController(text: playlist.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text('Rename Playlist', style: TextStyle(color: theme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.textPrimary),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save', style: TextStyle(color: theme.primary)),
          ),
        ],
      ),
    );

    if (newName == null || newName.trim().isEmpty) return;
    if (newName.trim() == playlist.name) return;

    await ref.read(playlistRepositoryProvider).renamePlaylist(
          playlistId: playlist.id,
          newName: newName.trim(),
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
  ) async {
    final theme = context.aurora;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text('Delete Playlist?', style: TextStyle(color: theme.textPrimary)),
        content: Text(
          '"${playlist.name}" will be permanently deleted.',
          style: TextStyle(color: theme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: theme.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(playlistRepositoryProvider).deletePlaylist(playlist.id);
  }

  void _showOptionsMenu(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
    Offset tapPosition,
  ) async {
    final theme = context.aurora;
    final selected = await showMenu<String>(
      context: context,
      color: theme.surface,
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        tapPosition.dx,
        tapPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Text('Rename', style: TextStyle(color: theme.textPrimary)),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: theme.error)),
        ),
      ],
    );

    if (!context.mounted) return;

    if (selected == 'rename') {
      await _showRenameDialog(context, ref, playlist);
    } else if (selected == 'delete') {
      await _confirmDelete(context, ref, playlist);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        title: Text('Playlists', style: TextStyle(color: theme.textPrimary)),
        iconTheme: IconThemeData(color: theme.textPrimary),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.primary,
        onPressed: () => _showCreateDialog(context, ref),
        child: Icon(Icons.add, color: theme.background),
      ),
      body: playlistsAsync.when(
        data: (playlists) {
          if (playlists.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_play, color: theme.textDisabled, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No Playlists yet',
                    style: TextStyle(color: theme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: playlist.coverThumbnail != null
                    ? CachedArtwork(
                        imageUrl: playlist.coverThumbnail!,
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(6),
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                        placeholderIcon: Icons.playlist_play,
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.surfaceRaised,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.playlist_play, color: theme.textDisabled),
                      ),
                title: Text(playlist.name, style: TextStyle(color: theme.textPrimary)),
                subtitle: Text(
                  '${playlist.itemCount} songs',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
                trailing: GestureDetector(
                  onTapDown: (details) {
                    _showOptionsMenu(
                      context,
                      ref,
                      playlist,
                      details.globalPosition,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.more_vert, color: theme.textSecondary),
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load playlists',
            style: TextStyle(color: theme.textDisabled),
          ),
        ),
      ),
    );
  }
}