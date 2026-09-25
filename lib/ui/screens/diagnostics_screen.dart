import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/playback_log.dart';
import '../theme/app_theme.dart';

/// The last 50 song starts, step by step with timings — what happened on
/// this phone, shareable as text, without USB logs.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlaybackLog.instance,
      builder: (context, _) {
        final attempts = PlaybackLog.instance.attempts;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Diagnostics'),
            actions: [
              IconButton(
                tooltip: 'Copy all',
                icon: const Icon(Icons.copy_rounded),
                onPressed: attempts.isEmpty
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          ClipboardData(text: PlaybackLog.instance.export()),
                        );
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Copied — paste it into a message'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: attempts.isEmpty ? null : PlaybackLog.instance.clear,
              ),
            ],
          ),
          body: attempts.isEmpty
              ? Center(
                  child: Text(
                    'Play a song and its start-up steps appear here.',
                    style: TextStyle(
                        color: context.colors.mist.withValues(alpha: 0.6)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: attempts.length,
                  separatorBuilder: (_, _) => const Divider(height: 24),
                  itemBuilder: (context, i) => _AttemptView(attempts[i]),
                ),
        );
      },
    );
  }
}

class _AttemptView extends StatelessWidget {
  final PlaybackAttempt attempt;
  const _AttemptView(this.attempt);

  @override
  Widget build(BuildContext context) {
    final ok = attempt.outcome == 'playing';
    final failed = attempt.outcome == 'failed';
    final loading = attempt.outcome == 'loading';
    final colour = ok
        ? context.colors.accent
        : failed
            ? Colors.redAccent
            : context.colors.mist.withValues(alpha: 0.6);
    final time = attempt.startedAt.toLocal().toString().substring(11, 19);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              ok
                  ? Icons.check_circle_rounded
                  : failed
                      ? Icons.error_rounded
                      : loading
                          ? Icons.hourglass_top_rounded
                          : Icons.skip_next_rounded,
              color: colour,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                attempt.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(time,
                style: TextStyle(
                    fontSize: 12,
                    color: context.colors.mist.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 6),
        for (final step in attempt.steps)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              step,
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: 'monospace',
                color: context.colors.mist.withValues(alpha: 0.75),
              ),
            ),
          ),
      ],
    );
  }
}
