import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_extension.dart';
import '../../../providers/cache_service_provider.dart';
import '../profile_providers.dart';
import 'profile_section.dart';

/// Phase 6.5 Batch 6 (Batch B) — Storage & Cache section: Cache
/// Size, Clear Cache, Offline/Cached Songs count, Storage Usage.
///
/// Uses centralized `cacheServiceProvider` from
/// `lib/providers/cache_service_provider.dart`.
class StorageCacheSection extends ConsumerWidget {
  const StorageCacheSection({super.key});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1024 * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'Downloaded/cached songs will be removed from this device. You can re-download them anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final cacheService = ref.read(cacheServiceProvider);
      await cacheService.clearAllCache();
      ref.invalidate(profileStorageInfoProvider);
      ref.invalidate(profileQuickStatsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't clear cache. Try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final storageAsync = ref.watch(profileStorageInfoProvider);
    final storage = storageAsync.maybeWhen(
      data: (s) => s,
      orElse: () => ProfileStorageInfo.empty,
    );

    return ProfileSection(
      title: 'Storage & cache',
      children: [
        ProfileTile(
          icon: Icons.sd_storage_outlined,
          label: 'Cache size',
          subtitle: _formatBytes(storage.totalCacheSizeBytes),
        ),
        ProfileTile(
          icon: Icons.offline_pin_outlined,
          label: 'Cached songs',
          subtitle: '${storage.cachedSongsCount} songs stored offline',
        ),
        ProfileTile(
          icon: Icons.delete_sweep_outlined,
          label: 'Clear cache',
          isDestructive: true,
          showDivider: false,
          onTap: () => _confirmClearCache(context, ref),
        ),
      ],
    );
  }
}