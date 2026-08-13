import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme_extension.dart';

/// Context menu types with variant-aware item sets.
enum ContextMenuType {
  song,          // Generic song (search, home, etc.)
  playlistTrack, // Song inside a playlist
  queueItem,     // Song inside queue
  downloaded,    // Downloaded/cached song
  artist,        // Artist page context
}

/// Universal context menu widget for all song/artist contexts.
class ContextMenu extends StatelessWidget {
  final String title;
  final String? subtitle;
  final ContextMenuType type;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onGoToArtist;
  final VoidCallback? onGoToAlbum;
  final VoidCallback? onShare;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;

  const ContextMenu({
    super.key,
    required this.title,
    this.subtitle,
    required this.type,
    this.onPlayNext,
    this.onAddToQueue,
    this.onAddToPlaylist,
    this.onToggleFavorite,
    this.onGoToArtist,
    this.onGoToAlbum,
    this.onShare,
    this.onDownload,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    final items = _buildItems();

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: theme.surface, indent: 16, endIndent: 16),
            // Menu items
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;
              return _MenuItem(
                icon: item.icon,
                label: item.label,
                shortcut: item.shortcut,
                onTap: () {
                  Navigator.of(context).pop();
                  item.onTap?.call();
                },
                theme: theme,
                isLast: isLast,
              );
            }),
          ],
        ),
      ),
    );
  }

  List<_MenuItemData> _buildItems() {
    final items = <_MenuItemData>[
      _MenuItemData(Icons.play_arrow, 'Play Next', 'N', onPlayNext),
      _MenuItemData(Icons.add, 'Add To Queue', 'Q', onAddToQueue),
      _MenuItemData(Icons.playlist_add, 'Add To Playlist', null, onAddToPlaylist),
      _MenuItemData(Icons.favorite_border, 'Favorite', 'S', onToggleFavorite),
    ];

    if (onGoToArtist != null) {
      items.add(_MenuItemData(Icons.person, 'Go To Artist', null, onGoToArtist));
    }
    if (onGoToAlbum != null) {
      items.add(_MenuItemData(Icons.album, 'Go To Album', null, onGoToAlbum));
    }

    items.add(_MenuItemData(Icons.share, 'Share', null, onShare));

    // Context-specific additions
    if (type == ContextMenuType.playlistTrack && onRemove != null) {
      items.add(_MenuItemData(Icons.delete, 'Remove from Playlist', null, onRemove));
    }
    if (type == ContextMenuType.queueItem && onRemove != null) {
      items.add(_MenuItemData(Icons.delete, 'Remove from Queue', null, onRemove));
    }
    if (type == ContextMenuType.downloaded && onDownload != null) {
      items.add(_MenuItemData(Icons.delete_forever, 'Delete Download', null, onDownload));
    }

    return items;
  }
}

class _MenuItemData {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback? onTap;
  _MenuItemData(this.icon, this.label, this.shortcut, this.onTap);
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;
  final dynamic theme;
  final bool isLast;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.shortcut,
    required this.onTap,
    required this.theme,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            if (shortcut != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  shortcut!,
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Show context menu as overlay (desktop) or bottom sheet (mobile).
Future<void> showContextMenu({
  required BuildContext context,
  required String title,
  String? subtitle,
  required ContextMenuType type,
  VoidCallback? onPlayNext,
  VoidCallback? onAddToQueue,
  VoidCallback? onAddToPlaylist,
  VoidCallback? onToggleFavorite,
  VoidCallback? onGoToArtist,
  VoidCallback? onGoToAlbum,
  VoidCallback? onShare,
  VoidCallback? onDownload,
  VoidCallback? onRemove,
}) async {
  final isDesktop = MediaQuery.of(context).size.width > 800;

  if (isDesktop) {
    // Desktop: show as popup menu at cursor/tap position
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    await showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          overlay.localToGlobal(Offset.zero),
          overlay.localToGlobal(overlay.size.bottomRight(Offset.zero)),
        ),
        Offset.zero & overlay.size,
      ),
      color: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: ContextMenu(
            title: title,
            subtitle: subtitle,
            type: type,
            onPlayNext: onPlayNext,
            onAddToQueue: onAddToQueue,
            onAddToPlaylist: onAddToPlaylist,
            onToggleFavorite: onToggleFavorite,
            onGoToArtist: onGoToArtist,
            onGoToAlbum: onGoToAlbum,
            onShare: onShare,
            onDownload: onDownload,
            onRemove: onRemove,
          ),
        ),
      ],
    );
  } else {
    // Mobile: show as bottom sheet
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
        ),
        child: ContextMenu(
          title: title,
          subtitle: subtitle,
          type: type,
          onPlayNext: onPlayNext,
          onAddToQueue: onAddToQueue,
          onAddToPlaylist: onAddToPlaylist,
          onToggleFavorite: onToggleFavorite,
          onGoToArtist: onGoToArtist,
          onGoToAlbum: onGoToAlbum,
          onShare: onShare,
          onDownload: onDownload,
          onRemove: onRemove,
        ),
      ),
    );
  }
}