import 'package:flutter/material.dart';

import '../core/theme/app_theme_extension.dart';

/// P1-A — tiny inline load-failure row for list/rail sections.
/// Presentational only: message + Retry. Parents pass the invalidate call
/// that is safe for their provider. Never used for empty states (empty is
/// not an error) and never shows raw exceptions.
class InlineLoadError extends StatelessWidget {
  const InlineLoadError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: aurora.textSecondary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: aurora.textSecondary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
