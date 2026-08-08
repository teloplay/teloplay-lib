import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist_model.dart';
import '../../providers/playlist_provider.dart';
import '../../widgets/cached_artwork.dart';
import 'playlist_detail_screen.dart';

/// সব playlist-এর full list — Library "Playlists → See all" থেকে খোলা
/// হয়, এবং এখান থেকেই নতুন playlist তৈরি করা যায় (FAB)।
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.grey),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Create', style: TextStyle(color: Colors.greenAccent)),
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

  // ⚠️ নতুন — Rename dialog। playlists_screen.dart এবং
  // playlist_detail_screen.dart দুই জায়গাতেই প্রায় একই rename dialog
  // ছিল (detail screen-এ আগে থেকেই ছিল, এখানে নতুন) — দুটো ছোট, আলাদা
  // widget tree বলে এখনো shared helper-এ extract করা হয়নি
  // (over-engineering এড়াতে), কিন্তু ভবিষ্যতে চাইলে একটা common
  // `showRenameDialog()` utility বানানো যেতে পারে।
  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
  ) async {
    final controller = TextEditingController(text: playlist.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save', style: TextStyle(color: Colors.greenAccent)),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${playlist.name}" স্থায়ীভাবে মুছে যাবে।',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(playlistRepositoryProvider).deletePlaylist(playlist.id);
  }

  // ⚠️ নতুন — more_vert এখন শুধু delete-confirm খুলত, এখন Rename +
  // Delete দুটো option-সহ একটা popup menu।
  void _showOptionsMenu(
    BuildContext context,
    WidgetRef ref,
    PlaylistSummary playlist,
    Offset tapPosition,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF1E1E1E),
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        tapPosition.dx,
        tapPosition.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'rename',
          child: Text('Rename', style: TextStyle(color: Colors.white)),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Playlists', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: playlistsAsync.when(
        data: (playlists) {
          if (playlists.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_play, color: Colors.grey[600], size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No Playlists yet',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
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
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.playlist_play, color: Colors.grey[600]),
                      ),
                title: Text(playlist.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${playlist.itemCount} songs',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                // ⚠️ GestureDetector দিয়ে tap-position (globalPosition)
                // capture করা হচ্ছে — showMenu()-এর জন্য screen-coordinate
                // লাগে, IconButton.onPressed-এ position পাওয়া যায় না
                // বলে GestureDetector.onTapDown ব্যবহার করা হলো।
                trailing: GestureDetector(
                  onTapDown: (details) {
                    _showOptionsMenu(
                      context,
                      ref,
                      playlist,
                      details.globalPosition,
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_vert, color: Colors.grey),
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
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
        error: (e, _) => Center(
          child: Text(
            'Playlist load করা যায়নি',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      ),
    );
  }
}