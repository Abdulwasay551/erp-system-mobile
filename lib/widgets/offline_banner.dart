import 'package:flutter/material.dart';
import '../theme/app_semantic_colors.dart';

/// Shown above a list/dashboard when it's rendering cached data instead of a live
/// fetch (offline, or the live fetch just failed) - so it's never ambiguous whether
/// what's on screen is current.
class OfflineDataBanner extends StatelessWidget {
  final DateTime cachedAt;
  final EdgeInsetsGeometry margin;
  const OfflineDataBanner({
    super.key,
    required this.cachedAt,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  String _relativeTime() {
    final diff = DateTime.now().difference(cachedAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final warning = context.semanticColors.warning;
    final warningContainer = context.semanticColors.warningContainer;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: warningContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline - showing data from ${_relativeTime()}',
              style: TextStyle(color: warning, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
