import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'timer_state.dart';

class TimerBanner extends ConsumerWidget {
  const TimerBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTimerProvider).value;
    if (active == null) return const SizedBox.shrink();
    // Subscribe to the 1Hz tick so the elapsed time re-renders while running.
    ref.watch(timerTickProvider);
    final scheme = Theme.of(context).colorScheme;
    final elapsed = active.elapsed();
    return Material(
      color: active.running ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => context.push('/timer'),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: active.running ? Colors.red : Colors.amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active.ticketLabel ?? 'Ticket #${active.ticketId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${active.running ? 'Running' : 'Paused'} · ${formatDuration(elapsed)}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(active.running ? Icons.pause : Icons.play_arrow),
                color: scheme.onPrimaryContainer,
                onPressed: () {
                  final notifier = ref.read(activeTimerProvider.notifier);
                  if (active.running) {
                    notifier.pause();
                  } else {
                    notifier.resume();
                  }
                },
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
