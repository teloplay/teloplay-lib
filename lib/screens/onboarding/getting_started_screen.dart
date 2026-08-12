import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/settings_repository.dart';

/// Onboarding checklist screen — shown on first app open.
class GettingStartedScreen extends ConsumerStatefulWidget {
  const GettingStartedScreen({super.key});

  @override
  ConsumerState<GettingStartedScreen> createState() => _GettingStartedScreenState();
}

class _GettingStartedScreenState extends ConsumerState<GettingStartedScreen> {
  final List<OnboardingItem> _items = [
    OnboardingItem(
      id: 'play_first_song',
      icon: Icons.play_circle_outline,
      title: 'Start playing',
      description: 'Search and play your first song',
      actionLabel: 'Search',
      actionRoute: '/search',
    ),
    OnboardingItem(
      id: 'try_mini_player',
      icon: Icons.picture_in_picture_alt_outlined,
      title: 'Try the Mini Player',
      description: 'Tap the mini player to expand it',
      actionLabel: null,
      actionRoute: null,
    ),
    OnboardingItem(
      id: 'explore_library',
      icon: Icons.library_music_outlined,
      title: 'Explore your Library',
      description: 'Visit your Library to see your collections',
      actionLabel: 'Go to Library',
      actionRoute: '/library',
    ),
    OnboardingItem(
      id: 'build_queue',
      icon: Icons.queue_music_outlined,
      title: 'Build your Queue',
      description: 'Add a song to your playback queue',
      actionLabel: null,
      actionRoute: null,
    ),
    OnboardingItem(
      id: 'customize_experience',
      icon: Icons.palette_outlined,
      title: 'Customize your experience',
      description: 'Visit Settings to personalize your app',
      actionLabel: 'Go to Settings',
      actionRoute: '/settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    final completionAsync = ref.watch(onboardingCompletionProvider);

    return Scaffold(
      backgroundColor: theme.background.withOpacity(0.9),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: theme.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: completionAsync.when(
              data: (completed) => _buildContent(context, completed),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _buildContent(context, {}),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, bool> completed) {
    final theme = context.aurora;
    final completedCount = completed.values.where((v) => v).length;
    final allComplete = completedCount == _items.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.close, color: theme.textSecondary),
                onPressed: () => _dismiss(context),
              ),
              const Spacer(),
              _ProgressRing(
                completed: completedCount,
                total: _items.length,
                theme: theme,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Getting Started',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Checklist
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final isDone = completed[item.id] ?? false;
              return _ChecklistItem(
                item: item,
                isDone: isDone,
                theme: theme,
                onAction: () => _handleAction(context, item),
              );
            },
          ),
        ),
        if (allComplete) ...[
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'You\\'re all set! 🎉',
              style: TextStyle(
                color: theme.success,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  void _dismiss(BuildContext context) async {
    await ref.read(settingsRepositoryProvider).setBool('onboarding_dismissed', true);
    if (mounted) Navigator.of(context).pop();
  }

  void _handleAction(BuildContext context, OnboardingItem item) {
    if (item.actionRoute != null) {
      Navigator.of(context).pop();
      context.push(item.actionRoute!);
    }
  }
}

class OnboardingItem {
  final String id;
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final String? actionRoute;

  OnboardingItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.actionRoute,
  });
}

class _ProgressRing extends StatelessWidget {
  final int completed;
  final int total;
  final dynamic theme;

  const _ProgressRing({
    required this.completed,
    required this.total,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final progress = completed / total;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: 1,
            strokeWidth: 3,
            backgroundColor: theme.surface,
            valueColor: AlwaysStoppedAnimation(theme.textDisabled),
          ),
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation(theme.primary),
          ),
          Center(
            child: Text(
              '$completed/$total',
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final OnboardingItem item;
  final bool isDone;
  final dynamic theme;
  final VoidCallback onAction;

  const _ChecklistItem({
    required this.item,
    required this.isDone,
    required this.theme,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDone ? theme.success.withOpacity(0.15) : theme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDone ? Icons.check : item.icon,
              color: isDone ? theme.success : theme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                if (!isDone && item.actionLabel != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(item.actionLabel!),
                  ),
                ],
              ],
            ),
          ),
          if (isDone)
            Icon(Icons.check_circle, color: theme.success, size: 20),
        ],
      ),
    );
  }
}