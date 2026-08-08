import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../providers/playlist_provider.dart';

/// Shared "Add to Playlist" bottom sheet — used by:
/// - MusicPlayerScreen
/// - NowPlayingScreen
/// - DesktopShell
///
/// This consolidates 3 near-identical copies into a single widget.
class AddToPlaylistSheet extends ConsumerStatefulWidget {
  final SearchResult track;

  const AddToPlaylistSheet({
    super.key,
    required this.track,
  });

  @override
  ConsumerState<AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();

  /// Show the bottom sheet — convenience static method.
  static Future<void> show({
    required BuildContext context,
    required SearchResult track,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: AddToPlaylistSheet(track: track),
        );
      },
    );
  }
}

class _AddToPlaylistSheetState extends ConsumerState<AddToPlaylistSheet> {
  final TextEditingController _newPlaylistController = TextEditingController();

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  Future<void> _createPlaylistAndAdd(BuildContext sheetContext, WidgetRef ref) async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: sheetContext,
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
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Create', style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    final playlistId = await ref.read(playlistRepositoryProvider).createPlaylist(name: name.trim());
    await ref.read(playlistRepositoryProvider).addItem(
          playlistId: playlistId,
          songId: widget.track.videoId,
          title: widget.track.title,
          author: widget.track.author,
          thumbnail: widget.track.thumbnail,
          durationSeconds: widget.track.duration?.inSeconds,
        );

    if (sheetContext.mounted) Navigator.pop(sheetContext);
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Add to Playlist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () => _createPlaylistAndAdd(context, ref),
                icon: const Icon(Icons.add, color: Colors.greenAccent, size: 18),
                label: const Text(
                  'New',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: playlistsAsync.when(
            data: (playlists) {
              if (playlists.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Text(
                    'কোনো playlist নেই — উপরে "New" চেপে তৈরি করো।',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: Icon(Icons.playlist_play, color: Colors.grey[500]),
                    title: Text(
                      playlist.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${playlist.itemCount} songs',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    onTap: () async {
                      await ref.read(playlistRepositoryProvider).addItem(
                            playlistId: playlist.id,
                            songId: widget.track.videoId,
                            title: widget.track.title,
                            author: widget.track.author,
                            thumbnail: widget.track.thumbnail,
                            durationSeconds: widget.track.duration?.inSeconds,
                          );
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Text(
                'Playlist load করা যায়নি',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}