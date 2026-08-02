import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Přehled nákupních seznamů + generování nového (zadání 4.6).
class ShoppingListsScreen extends ConsumerWidget {
  const ShoppingListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(shoppingListsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nákupní seznamy')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openGenerator(context, ref),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Vytvořit seznam'),
      ),
      body: lists.when(
        loading: () => const LoadingView(),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(shoppingListsProvider),
        ),
        data: (items) => items.isEmpty
            ? const EmptyView(
                icon: Icons.shopping_basket_outlined,
                title: 'Zatím žádný nákupní seznam',
                subtitle: 'Vyber časové rozmezí a nech AI sestavit seznam '
                    'z naplánovaných jídel — včetně toho, kdy co koupit.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(shoppingListsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _ListCard(summary: items[index]),
                ),
              ),
      ),
    );
  }

  Future<void> _openGenerator(BuildContext context, WidgetRef ref) async {
    final listId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _GenerateSheet(),
    );

    if (listId != null && context.mounted) {
      ref.invalidate(shoppingListsProvider);
      context.push('/shopping/$listId');
    }
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.summary});

  final ShoppingListSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = parseApiDate(summary.rangeStart);
    final end = parseApiDate(summary.rangeEnd);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/shopping/${summary.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                summary.isComplete
                    ? Icons.check_circle
                    : Icons.shopping_basket_outlined,
                color: summary.isComplete
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${shortDate(start)} – ${shortDate(end)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.checkedCount} z ${summary.itemCount} '
                      '${_polozek(summary.itemCount)} nakoupeno',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (summary.itemCount > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: summary.checkedCount / summary.itemCount,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  String _polozek(int count) => switch (count) {
        1 => 'položky',
        _ => 'položek',
      };
}

/// Výběr rozmezí a spuštění generování.
class _GenerateSheet extends ConsumerStatefulWidget {
  const _GenerateSheet();

  @override
  ConsumerState<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends ConsumerState<_GenerateSheet> {
  late DateTime _start = startOfWeek(today());
  late DateTime _end = startOfWeek(today()).add(const Duration(days: 6));
  bool _includeProposed = false;
  bool _busy = false;

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today().subtract(const Duration(days: 7)),
      lastDate: DateTime(today().year, today().month + 3, today().day),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      helpText: 'Rozmezí nákupu',
      saveText: 'Vybrat',
    );
    if (picked != null) {
      setState(() {
        _start = picked.start;
        _end = picked.end;
      });
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final list = await ref.read(apiServiceProvider).generateShoppingList(
            rangeStart: apiDate(_start),
            rangeEnd: apiDate(_end),
            includeProposed: _includeProposed,
          );
      if (mounted) Navigator.of(context).pop(list.id);
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(context, e.message, isError: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Nový nákupní seznam',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'AI projde naplánovaná jídla a sestaví seznam surovin. '
              'U každé určí, kdy ji koupit, aby vydržela čerstvá.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickRange,
              icon: const Icon(Icons.date_range),
              label: Text('${shortDate(_start)} – ${shortDate(_end)}'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Zahrnout i nepotvrzená jídla'),
              subtitle: const Text('Návrhy, o kterých se ještě hlasuje'),
              value: _includeProposed,
              onChanged:
                  _busy ? null : (v) => setState(() => _includeProposed = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _generate,
              child: _busy
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Sestavuji seznam…'),
                      ],
                    )
                  : const Text('Vygenerovat'),
            ),
          ],
        ),
      ),
    );
  }
}
