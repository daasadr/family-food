import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Detail nákupního seznamu — položky seskupené podle dne nákupu,
/// odškrtávání, přidávání a mazání (zadání 4.6).
class ShoppingListScreen extends ConsumerWidget {
  const ShoppingListScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(shoppingListProvider(listId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nákupní seznam'),
        actions: [
          listAsync.maybeWhen(
            data: (_) => IconButton(
              tooltip: 'Smazat seznam',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: listAsync.maybeWhen(
        data: (_) => FloatingActionButton(
          onPressed: () => _addItem(context, ref),
          child: const Icon(Icons.add),
        ),
        orElse: () => null,
      ),
      body: listAsync.when(
        loading: () => const LoadingView(),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(shoppingListProvider(listId)),
        ),
        data: (list) => _Body(list: list),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smazat seznam?'),
        content: const Text('Seznam i všechny jeho položky zmizí.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Smazat'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(apiServiceProvider).deleteShoppingList(listId);
      ref.invalidate(shoppingListsProvider);
      if (context.mounted) context.pop();
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Přidat položku'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Co koupit'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(
                labelText: 'Množství (nepovinné)',
                hintText: 'např. 500 g',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Přidat'),
          ),
        ],
      ),
    );

    if (added != true || nameController.text.trim().isEmpty) return;

    try {
      await ref.read(apiServiceProvider).addShoppingItem(
            listId: listId,
            name: nameController.text.trim(),
            quantity: quantityController.text.trim(),
          );
      ref.invalidate(shoppingListProvider(listId));
      ref.invalidate(shoppingListsProvider);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.list});

  final ShoppingList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grouped = list.byBuyDate;

    // Nejdřív položky s datem (chronologicky), pak ty bez data.
    final dates = grouped.keys.whereType<String>().toList()..sort();
    final undated = grouped[null] ?? const <ShoppingItem>[];

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(shoppingListProvider(list.id)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    list.isComplete ? Icons.check_circle : Icons.shopping_basket,
                    color: list.isComplete
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${shortDate(parseApiDate(list.rangeStart))} – '
                          '${shortDate(parseApiDate(list.rangeEnd))}',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          list.isComplete
                              ? 'Vše nakoupeno'
                              : '${list.checkedCount} z ${list.items.length} nakoupeno',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final date in dates) ...[
            _DayHeader(date: date),
            for (final item in grouped[date]!)
              _ItemTile(listId: list.id, item: item),
            const SizedBox(height: 12),
          ],
          if (undated.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Kdykoli',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            for (final item in undated) _ItemTile(listId: list.id, item: item),
          ],
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = parseApiDate(date);
    final isToday = isSameDay(parsed, today());
    final isPast = parsed.isBefore(today());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            isToday ? 'Dnes' : longDate(parsed),
            style: theme.textTheme.titleSmall?.copyWith(
              color: isToday
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isToday ? FontWeight.w700 : null,
            ),
          ),
          if (isPast && !isToday) ...[
            const SizedBox(width: 8),
            Icon(Icons.schedule,
                size: 14, color: theme.colorScheme.error),
          ],
        ],
      ),
    );
  }
}

class _ItemTile extends ConsumerStatefulWidget {
  const _ItemTile({required this.listId, required this.item});

  final String listId;
  final ShoppingItem item;

  @override
  ConsumerState<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends ConsumerState<_ItemTile> {
  late bool _checked = widget.item.isChecked;
  bool _busy = false;

  @override
  void didUpdateWidget(_ItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.isChecked != widget.item.isChecked) {
      _checked = widget.item.isChecked;
    }
  }

  Future<void> _toggle(bool value) async {
    // Odškrtnutí se ukáže hned; při chybě se vrátí zpět.
    setState(() {
      _checked = value;
      _busy = true;
    });
    try {
      await ref.read(apiServiceProvider).updateShoppingItem(
            itemId: widget.item.id,
            isChecked: value,
          );
      ref.invalidate(shoppingListsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _checked = !value);
        showMessage(context, e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    try {
      await ref.read(apiServiceProvider).deleteShoppingItem(widget.item.id);
      ref.invalidate(shoppingListProvider(widget.listId));
      ref.invalidate(shoppingListsProvider);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(),
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _checked,
        onChanged: _busy ? null : (v) => _toggle(v ?? false),
        title: Text(
          item.quantity != null ? '${item.name} · ${item.quantity}' : item.name,
          style: TextStyle(
            decoration: _checked ? TextDecoration.lineThrough : null,
            color: _checked ? theme.colorScheme.outline : null,
          ),
        ),
        subtitle: item.note != null
            ? Text(
                item.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        secondary: item.category != null
            ? Chip(
                label: Text(item.category!, style: theme.textTheme.labelSmall),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              )
            : null,
      ),
    );
  }
}
