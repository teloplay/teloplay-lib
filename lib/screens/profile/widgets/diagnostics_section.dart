import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_extension.dart';
import '../../../providers/cache_service_provider.dart';
import 'profile_section.dart';

/// Phase 6.5 Batch 6 (Batch B) — Diagnostics section: App Version,
/// Database Status, Cache Status, Audio Engine Status, Export Logs.
/// Advanced sub-section (Verify Cache Integrity, Scan Orphan Files)
/// collapsible, developer-facing.
class DiagnosticsSection extends ConsumerStatefulWidget {
  const DiagnosticsSection({super.key});

  @override
  ConsumerState<DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<DiagnosticsSection> {
  bool _advancedExpanded = false;
  bool _isVerifying = false;
  String? _verifyResultText;

  Future<void> _runVerifyIntegrity() async {
    setState(() {
      _isVerifying = true;
      _verifyResultText = null;
    });

    try {
      final cacheService = ref.read(cacheServiceProvider);
      final report = await cacheService.verifyCacheIntegrity();
      if (!mounted) return;
      setState(() {
        _verifyResultText =
            'Checked ${report.totalChecked} · OK ${report.verifiedOk} · '
            'Corrupted ${report.corrupted} · Populated ${report.checksumsPopulated}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _verifyResultText = "Verification failed. Try again.");
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _runOrphanScan() async {
    setState(() {
      _isVerifying = true;
      _verifyResultText = null;
    });

    try {
      final cacheService = ref.read(cacheServiceProvider);
      final report = await cacheService.scanForOrphanFiles();
      if (!mounted) return;
      final mb = (report.bytesReclaimed / (1024 * 1024)).toStringAsFixed(1);
      setState(() {
        _verifyResultText =
            'Removed ${report.orphanFilesFound.length} orphan file(s) · Reclaimed $mb MB';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _verifyResultText = "Scan failed. Try again.");
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return ProfileSection(
      title: 'Diagnostics',
      children: [
        const ProfileTile(
          icon: Icons.info_outline,
          label: 'App version',
          subtitle: '1.0.0+1',
        ),
        const ProfileTile(
          icon: Icons.storage_outlined,
          label: 'Database status',
          subtitle: 'Connected (Drift/SQLite)',
        ),
        const ProfileTile(
          icon: Icons.cached_outlined,
          label: 'Cache status',
          subtitle: 'Active',
        ),
        const ProfileTile(
          icon: Icons.graphic_eq,
          label: 'Audio engine status',
          subtitle: 'Ready',
        ),
        ProfileTile(
          icon: Icons.file_download_outlined,
          label: 'Export logs',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Log export coming soon')),
            );
          },
        ),
        InkWell(
          onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.tune, size: 19, color: aurora.textSecondary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Advanced',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: aurora.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: aurora.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_advancedExpanded) ...[
          Divider(height: 1, indent: 16, endIndent: 16, color: aurora.glassBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isVerifying ? null : _runVerifyIntegrity,
                        child: const Text('Verify cache integrity'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isVerifying ? null : _runOrphanScan,
                        child: const Text('Scan orphan files'),
                      ),
                    ),
                  ],
                ),
                if (_isVerifying) ...[
                  const SizedBox(height: 12),
                  const Center(child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )),
                ],
                if (_verifyResultText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _verifyResultText!,
                    style: TextStyle(fontSize: 12, color: aurora.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}