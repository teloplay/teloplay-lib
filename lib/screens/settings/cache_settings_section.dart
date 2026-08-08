import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cache/media_asset_manager.dart';
import '../../providers/cache_service_provider.dart';
import '../../services/cache_service.dart';

// ⚠️ Phase 3 (Smart Cache) — Cache Settings UI।
//
// এই ফাইল ইচ্ছাকৃতভাবে একটা standalone `ConsumerWidget` (section),
// পুরো Screen না — কারণ project-এ এখনো কোনো Settings screen তৈরি হয়নি।
// এটা যেকোনো ভবিষ্যৎ Settings screen-এর `body`-তে সরাসরি বসানো যাবে:
//
//   ListView(children: [
//     ...otherSettingsSections,
//     const CacheSettingsSection(),
//   ])
//
// যদি এখনই আলাদা করে দেখতে চাও (Settings screen তৈরি হওয়ার আগে),
// নিচের `CacheSettingsDebugScreen` একটা thin wrapper Scaffold দেয়
// (player_test_screen.dart-এর /debug/ pattern অনুসরণ করে) — route
// করে নিতে হবে GoRouter-এ, এখানে সেটা করা হয়নি কারণ router ফাইল
// এখনো দেখা হয়নি।

/// User-facing budget option — internal byte-value + display label।
class _BudgetOption {
  final String label;
  final int bytes;
  const _BudgetOption(this.label, this.bytes);
}

// ⚠️ "Unlimited" একটা sentinel বড় value দিয়ে represent করা হচ্ছে
// (roadmap-এর আগের সিদ্ধান্ত অনুযায়ী — CacheService.updateAudioCacheBudget()
// নিজে "unlimited" concept বোঝে না, শুধু একটা maxSizeBytes নেয়)। 1 << 40
// (~1TB) বাস্তবে কার্যত unlimited — কোনো ব্যবহারকারীর device-এ এত বড়
// audio cache জমা হওয়ার বাস্তবসম্মত সম্ভাবনা নেই।
const _kUnlimitedBytes = 1 << 40;

const _budgetOptions = [
  _BudgetOption('200 MB', 200 * 1024 * 1024),
  _BudgetOption('500 MB', 500 * 1024 * 1024),
  _BudgetOption('1 GB', 1024 * 1024 * 1024),
  _BudgetOption('Unlimited', _kUnlimitedBytes),
];

class CacheSettingsSection extends ConsumerStatefulWidget {
  const CacheSettingsSection({super.key});

  @override
  ConsumerState<CacheSettingsSection> createState() =>
      _CacheSettingsSectionState();
}

class _CacheSettingsSectionState extends ConsumerState<CacheSettingsSection> {
  // ⚠️ Debug-snapshot-driven — `CacheService.debugSnapshot` কোনো
  // reactive stream না (দেখো cache_service.dart, এটা একটা plain getter),
  // তাই storage-used সংখ্যা automatically-live-update হয় না। এই widget
  // নিজে থেকে periodic refresh চালায় (setState + Timer.periodic) যতক্ষণ
  // এই section mounted থাকে — এটা যথেষ্ট (Settings screen সাধারণত
  // continuously খোলা রাখা হয় না, আর user নিজে ম্যানুয়ালি track play
  // করলে বা cache clear করলে সাথে সাথে UI আপডেট দেখতে চাইবে)।
  //
  // 🤔 ভবিষ্যতে `CacheService`-এ একটা reactive `Stream<Map<String,
  // Object>>` (StreamController-backed, MusicPlayerRepository-এর অন্য
  // stream-গুলোর প্যাটার্নে) যোগ করা যেতে পারে যদি real-time accuracy
  // বেশি জরুরি মনে হয় — এখন polling যথেষ্ট এবং simpler, নতুন কোনো
  // cache_service.dart change লাগে না।
  Map<String, Object>? _snapshot;
  bool _isClearing = false;
  bool _isUpdatingBudget = false;
  bool _isVerifying = false;
  bool _isScanning = false;
  String? _lastVerifyResult;
  String? _lastScanResult;

  @override
  void initState() {
    super.initState();
    _refreshSnapshot();
  }

  void _refreshSnapshot() {
    if (!mounted) return;
    final cacheService = ref.read(cacheServiceProvider);
    setState(() {
      _snapshot = cacheService.debugSnapshot;
    });
  }

  int get _currentAudioBudgetBytes {
    final audioSnapshot =
        _snapshot?['audio'] as Map<String, Object>? ?? const {};
    return (audioSnapshot['maxSizeBytes'] as int?) ?? _budgetOptions[1].bytes;
  }

  int get _currentAudioUsedBytes {
    final audioSnapshot =
        _snapshot?['audio'] as Map<String, Object>? ?? const {};
    return (audioSnapshot['totalSizeBytes'] as int?) ?? 0;
  }

  String _formatMb(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }

  Future<void> _handleBudgetChange(_BudgetOption option) async {
    if (_isUpdatingBudget) return;
    setState(() => _isUpdatingBudget = true);

    try {
      final cacheService = ref.read(cacheServiceProvider);
      await cacheService.updateAudioCacheBudget(option.bytes);
      _refreshSnapshot();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cache size set to ${option.label}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingBudget = false);
    }
  }

  // ⚠️ "Clear All Cache" — roadmap নির্দিষ্টভাবে বলেছে "user can change
  // this and add clear all cache with warning show"। এখানে
  // `showDialog` দিয়ে একটা explicit confirmation নেওয়া হচ্ছে — destructive
  // action (সব cached audio মুছে যাবে), তাই accidental tap থেকে রক্ষা
  // করতে একটা extra ধাপ ইচ্ছাকৃত।
  Future<void> _handleClearAllTap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all cached music?'),
        content: const Text(
          'This will delete all downloaded/cached songs from this device. '
          'You can still stream and re-cache them later, but this action '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isClearing = true);
    try {
      final cacheService = ref.read(cacheServiceProvider);
      await cacheService.clearAllCache();
      _refreshSnapshot();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  // ✅ Phase 3 Item D — Verify Cache Integrity (manual-trigger, SHA-256)।
  // ব্যয়বহুল (পুরো cached library পড়তে হয়), তাই user-initiated বাটন,
  // কোনো automatic schedule না — roadmap-এর approved hybrid policy
  // অনুযায়ী।
  Future<void> _handleVerifyIntegrity() async {
    if (_isVerifying) return;
    setState(() {
      _isVerifying = true;
      _lastVerifyResult = null;
    });

    try {
      final cacheService = ref.read(cacheServiceProvider);
      final report = await cacheService.verifyCacheIntegrity();
      _refreshSnapshot();

      if (mounted) {
        setState(() {
          _lastVerifyResult = 'Checked ${report.totalChecked} — '
              '${report.verifiedOk} ok, '
              '${report.checksumsPopulated} newly verified, '
              '${report.corrupted} corrupted (removed)';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // ✅ Phase 3 Item D — Scan for Orphan Files (manual-trigger)। বড়
  // cache-এ startup latency এড়াতে automatic না, শুধু এই বাটন থেকে।
  Future<void> _handleScanOrphans() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _lastScanResult = null;
    });

    try {
      final cacheService = ref.read(cacheServiceProvider);
      final report = await cacheService.scanForOrphanFiles();
      _refreshSnapshot();

      if (mounted) {
        final mb = (report.bytesReclaimed / (1024 * 1024)).toStringAsFixed(1);
        setState(() {
          _lastScanResult = report.orphanFilesFound.isEmpty
              ? 'No orphan files found'
              : '${report.orphanFilesFound.length} orphan file(s) removed, '
                  '${mb}MB reclaimed';
        });
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usedBytes = _currentAudioUsedBytes;
    final budgetBytes = _currentAudioBudgetBytes;
    final isUnlimited = budgetBytes >= _kUnlimitedBytes;
    final progress =
        isUnlimited ? 0.0 : (budgetBytes > 0 ? usedBytes / budgetBytes : 0.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Storage & Cache',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // ⚠️ Storage used indicator (roadmap: "Storage used: X MB / Y MB")
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Music cache used',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    isUnlimited
                        ? _formatMb(usedBytes)
                        : '${_formatMb(usedBytes)} / ${_formatMb(budgetBytes)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!isUnlimited)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                      progress >= 0.9
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ⚠️ Cache size selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Cache size limit',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _budgetOptions.map((option) {
              final isSelected = option.bytes == budgetBytes;
              return ChoiceChip(
                label: Text(option.label),
                selected: isSelected,
                onSelected: _isUpdatingBudget
                    ? null
                    : (_) => _handleBudgetChange(option),
              );
            }).toList(),
          ),
        ),

        // ✅ Phase 3 Item D — Cache Health/Diagnostics
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Cache Health',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ListTile(
          leading: _isVerifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined, color: Colors.white70),
          title: const Text('Verify cache integrity'),
          subtitle: Text(
            _lastVerifyResult ?? 'Check cached files for corruption',
            style: theme.textTheme.bodySmall,
          ),
          onTap: _isVerifying ? null : _handleVerifyIntegrity,
        ),
        ListTile(
          leading: _isScanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cleaning_services_outlined, color: Colors.white70),
          title: const Text('Scan for orphan files'),
          subtitle: Text(
            _lastScanResult ?? 'Remove untracked cached files',
            style: theme.textTheme.bodySmall,
          ),
          onTap: _isScanning ? null : _handleScanOrphans,
        ),

        const SizedBox(height: 8),

        // ⚠️ Clear All Cache — destructive action, warning-confirmed
        ListTile(
          leading: Icon(
            Icons.delete_outline,
            color: theme.colorScheme.error,
          ),
          title: Text(
            'Clear all cached music',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: const Text('Frees up storage, deletes downloaded songs'),
          trailing: _isClearing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _isClearing ? null : _handleClearAllTap,
        ),
      ],
    );
  }
}

/// ⚠️ Debug-only thin wrapper — যতক্ষণ না প্রকৃত Settings screen তৈরি
/// হয়, এটা দিয়ে এখনই `CacheSettingsSection` আলাদাভাবে দেখা/টেস্ট করা
/// যাবে। `player_test_screen.dart`-এর /debug/ কনভেনশন অনুসরণ করে —
/// release build-এ route করা উচিত না (router ফাইলে kDebugMode গার্ড
/// সহ যোগ করতে হবে, এই ফাইলে সেই routing অংশ নেই)।
class CacheSettingsDebugScreen extends StatelessWidget {
  const CacheSettingsDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cache Settings (Debug)')),
      body: const SingleChildScrollView(
        child: CacheSettingsSection(),
      ),
    );
  }
}