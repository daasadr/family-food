import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Měsíční kalendář — „zobrazit další dny“ z domovské obrazovky.
/// Listovat lze až 2 měsíce dopředu (celkem 3 včetně aktuálního, zadání 4.2).
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = DateTime(today().year, today().month);

  static const _monthNames = [
    'Leden',
    'Únor',
    'Březen',
    'Duben',
    'Květen',
    'Červen',
    'Červenec',
    'Srpen',
    'Září',
    'Říjen',
    'Listopad',
    'Prosinec',
  ];

  DateTime get _firstMonth => DateTime(today().year, today().month);
  DateTime get _lastMonth => DateTime(today().year, today().month + 2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = _weeksOfMonth(_month);

    return Scaffold(
      appBar: AppBar(title: const Text('Kalendář')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _month.isAfter(_firstMonth)
                      ? () => setState(() =>
                          _month = DateTime(_month.year, _month.month - 1))
                      : null,
                ),
                Expanded(
                  child: Text(
                    '${_monthNames[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _month.isBefore(_lastMonth)
                      ? () => setState(() =>
                          _month = DateTime(_month.year, _month.month + 1))
                      : null,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final day in ['po', 'út', 'st', 'čt', 'pá', 'so', 'ne'])
                  Expanded(
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                for (final weekStart in weeks)
                  _WeekRow(month: _month.month, weekStart: weekStart),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(
                  color: theme.colorScheme.primary,
                  label: 'potvrzeno',
                  filled: true,
                ),
                const SizedBox(width: 16),
                _Legend(
                  color: theme.colorScheme.tertiary,
                  label: 'jen návrhy',
                  filled: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pondělky všech týdnů, které zasahují do daného měsíce.
  List<DateTime> _weeksOfMonth(DateTime month) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    final weeks = <DateTime>[];
    var cursor = startOfWeek(first);
    while (!cursor.isAfter(last)) {
      weeks.add(cursor);
      cursor = cursor.add(const Duration(days: 7));
    }
    return weeks;
  }
}

class _WeekRow extends ConsumerWidget {
  const _WeekRow({required this.month, required this.weekStart});

  final int month;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekAsync = ref.watch(weekPlanProvider(weekStart));

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _DayCell(
                date: weekStart.add(Duration(days: i)),
                inMonth: weekStart.add(Duration(days: i)).month == month,
                summary: weekAsync.whenOrNull(
                  data: (week) => _summaryFor(
                    week,
                    apiDate(weekStart.add(Duration(days: i))),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  DaySummary? _summaryFor(WeekPlan week, String date) {
    for (final day in week.days) {
      if (day.date == date) return day;
    }
    return null;
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.summary,
  });

  final DateTime date;
  final bool inMonth;
  final DaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = isSameDay(date, today());
    final beyondWindow = date.isAfter(
      DateTime(today().year, today().month + 3, today().day),
    );

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: (!inMonth || beyondWindow)
            ? null
            : () => context.push('/day/${apiDate(date)}'),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isToday ? theme.colorScheme.primaryContainer : null,
            border: Border.all(
              color: isToday
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: inMonth ? null : theme.colorScheme.outline,
                  fontWeight: isToday ? FontWeight.w700 : null,
                ),
              ),
              const SizedBox(height: 4),
              if (summary != null && inMonth)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (summary!.confirmedCount > 0)
                      _Pip(color: theme.colorScheme.primary, filled: true),
                    if (summary!.proposedCount > 0)
                      _Pip(color: theme.colorScheme.tertiary, filled: false),
                  ],
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          border: Border.all(color: color, width: 1.5),
          shape: BoxShape.circle,
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.filled,
  });

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pip(color: color, filled: filled),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
