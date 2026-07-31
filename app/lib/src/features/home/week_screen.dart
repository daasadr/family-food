import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Domovská obrazovka — vždy otevře aktuální týden, aby bylo vidět,
/// co už je naplánované a kde jsou mezery (zadání 4.2).
class WeekScreen extends ConsumerWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(selectedWeekProvider);
    final weekAsync = ref.watch(weekPlanProvider(weekStart));
    final family = ref.watch(familyProvider);

    final currentWeek = startOfWeek(today());
    final maxWeek = startOfWeek(
      DateTime(today().year, today().month + 3, today().day),
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Jídelníček'),
            family.maybeWhen(
              data: (f) => Text(
                f.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Měsíční kalendář',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push('/calendar'),
          ),
          IconButton(
            tooltip: 'Nastavení',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          _WeekSwitcher(
            weekStart: weekStart,
            canGoBack: weekStart.isAfter(currentWeek),
            canGoForward: weekStart.isBefore(maxWeek),
            onChange: (delta) =>
                ref.read(selectedWeekProvider.notifier).shift(delta),
            onToday: () => ref.read(selectedWeekProvider.notifier).goToToday(),
          ),
          Expanded(
            child: weekAsync.when(
              loading: () => const LoadingView(),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(weekPlanProvider(weekStart)),
              ),
              data: (week) => RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(weekPlanProvider(weekStart)),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: week.days.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final day = week.days[index];
                    return _DayCard(
                      summary: day,
                      onTap: () => context.push('/day/${day.date}'),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekSwitcher extends StatelessWidget {
  const _WeekSwitcher({
    required this.weekStart,
    required this.canGoBack,
    required this.canGoForward,
    required this.onChange,
    required this.onToday,
  });

  final DateTime weekStart;
  final bool canGoBack;
  final bool canGoForward;
  final void Function(int delta) onChange;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final isCurrentWeek = isSameDay(weekStart, startOfWeek(today()));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Předchozí týden',
            onPressed: canGoBack ? () => onChange(-1) : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  weekRangeLabel(weekStart),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (!isCurrentWeek)
                  TextButton(
                    onPressed: onToday,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Zpět na tento týden'),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Další týden',
            onPressed: canGoForward ? () => onChange(1) : null,
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.summary, required this.onTap});

  final DaySummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = parseApiDate(summary.date);
    final isToday = isSameDay(date, today());
    final isPast = date.isBefore(today());

    return Card(
      color: isToday ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weekdayShort(date),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isPast
                            ? theme.colorScheme.outline
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${date.day}.',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isPast ? theme.colorScheme.outline : null,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SlotIndicators(summary: summary),
                    const SizedBox(height: 6),
                    Text(
                      _statusText(summary),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(DaySummary s) {
    if (s.slotCount == 0) return 'Žádné sloty — zkontroluj šablonu';
    if (s.isFullyPlanned) return 'Naplánováno celé';
    if (s.confirmedCount == 0 && s.proposedCount == 0) {
      return 'Zatím nic naplánováno';
    }
    return '${s.confirmedCount} potvrzeno · ${s.proposedCount} k rozhodnutí · '
        '${s.emptyCount} volných';
  }
}

/// Malé značky pro každý slot dne: plná = potvrzeno, obrys = jen návrh,
/// šedá = prázdno (zadání 4.2).
class _SlotIndicators extends StatelessWidget {
  const _SlotIndicators({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dots = <Widget>[];

    Widget dot(Color color, {bool filled = true}) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        );

    for (var i = 0; i < summary.confirmedCount; i++) {
      dots.add(dot(scheme.primary));
    }
    for (var i = 0; i < summary.proposedCount; i++) {
      dots.add(dot(scheme.tertiary, filled: false));
    }
    for (var i = 0; i < summary.emptyCount; i++) {
      dots.add(dot(scheme.outlineVariant, filled: false));
    }

    return Wrap(spacing: 6, runSpacing: 6, children: dots);
  }
}
