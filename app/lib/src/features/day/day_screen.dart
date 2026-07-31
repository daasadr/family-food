import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Detail dne — sloty podle šablony, u každého návrhy jídel (zadání 4.3).
class DayScreen extends ConsumerWidget {
  const DayScreen({super.key, required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayAsync = ref.watch(dayPlanProvider(date));
    final parsed = parseApiDate(date);

    return Scaffold(
      appBar: AppBar(
        title: Text(longDate(parsed)),
        actions: [
          IconButton(
            tooltip: 'Přidat mimořádný slot',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _addCustomSlot(context, ref),
          ),
        ],
      ),
      body: dayAsync.when(
        loading: () => const LoadingView(),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(dayPlanProvider(date)),
        ),
        data: (day) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dayPlanProvider(date)),
          child: day.slots.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 80),
                    EmptyView(
                      icon: Icons.no_meals_outlined,
                      title: 'Pro tento den nejsou žádné sloty',
                      subtitle:
                          'Zapni si sloty v nastavení šablony, nebo přidej '
                          'mimořádný slot tlačítkem nahoře.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: day.slots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _SlotCard(
                    date: date,
                    slot: day.slots[index],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _addCustomSlot(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mimořádný slot'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Název',
            hintText: 'např. Narozeninový dort',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Přidat'),
          ),
        ],
      ),
    );

    if (label == null || label.isEmpty || !context.mounted) return;

    try {
      await ref.read(apiServiceProvider).addCustomSlot(date: date, label: label);
      ref.invalidate(dayPlanProvider(date));
      ref.invalidate(weekPlanProvider(startOfWeek(parseApiDate(date))));
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }
}

class _SlotCard extends ConsumerWidget {
  const _SlotCard({required this.date, required this.slot});

  final String date;
  final MealSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final confirmed = slot.confirmedProposal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_slotIcon(slot.slotType),
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slot.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (confirmed != null)
                  Chip(
                    avatar: Icon(Icons.lock_outline,
                        size: 16, color: theme.colorScheme.onPrimaryContainer),
                    label: const Text('Potvrzeno'),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    visualDensity: VisualDensity.compact,
                  )
                else if (slot.isCustomSlot)
                  IconButton(
                    tooltip: 'Smazat slot',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deleteSlot(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (slot.isEmpty)
              OutlinedButton.icon(
                onPressed: () =>
                    context.push('/day/$date/slot/${slot.id}/propose'),
                icon: const Icon(Icons.add),
                label: const Text('Navrhnout jídlo'),
              )
            else ...[
              for (final proposal in _sorted(slot.proposals))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProposalTile(date: date, proposal: proposal),
                ),
              if (confirmed == null)
                TextButton.icon(
                  onPressed: () =>
                      context.push('/day/$date/slot/${slot.id}/propose'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Přidat další návrh'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Potvrzené nahoru, pak podle počtu hlasů.
  List<MealProposal> _sorted(List<MealProposal> proposals) {
    final list = [...proposals];
    list.sort((a, b) {
      if (a.isConfirmed != b.isConfirmed) return a.isConfirmed ? -1 : 1;
      return b.voteCount.compareTo(a.voteCount);
    });
    return list;
  }

  Future<void> _deleteSlot(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiServiceProvider).deleteSlot(slot.id);
      ref.invalidate(dayPlanProvider(date));
      ref.invalidate(weekPlanProvider(startOfWeek(parseApiDate(date))));
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }

  IconData _slotIcon(SlotType type) => switch (type) {
        SlotType.breakfast => Icons.free_breakfast_outlined,
        SlotType.lunch => Icons.lunch_dining_outlined,
        SlotType.dinner => Icons.dinner_dining_outlined,
        SlotType.snack1 || SlotType.snack2 => Icons.bakery_dining_outlined,
        SlotType.custom => Icons.celebration_outlined,
      };
}

class _ProposalTile extends ConsumerWidget {
  const _ProposalTile({required this.date, required this.proposal});

  final String date;
  final MealProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/day/$date/proposal/${proposal.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: proposal.isConfirmed
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (proposal.photoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  proposal.photoUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.restaurant, size: 32),
                ),
              )
            else
              Icon(Icons.restaurant_outlined,
                  size: 32, color: theme.colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proposal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'navrhl${_feminineHint(proposal.proposedBy.name)} '
                    '${proposal.proposedBy.name}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _VoteButton(date: date, proposal: proposal),
            if (proposal.commentCount > 0) ...[
              const SizedBox(width: 8),
              Icon(Icons.chat_bubble_outline,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 2),
              Text('${proposal.commentCount}',
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  /// Bez znalosti rodu neuvádíme koncovku — „navrhl/a“.
  String _feminineHint(String _) => '/a';
}

class _VoteButton extends ConsumerStatefulWidget {
  const _VoteButton({required this.date, required this.proposal});

  final String date;
  final MealProposal proposal;

  @override
  ConsumerState<_VoteButton> createState() => _VoteButtonState();
}

class _VoteButtonState extends ConsumerState<_VoteButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);
      if (widget.proposal.votedByMe) {
        await api.unvote(widget.proposal.id);
      } else {
        await api.vote(widget.proposal.id);
      }
      ref.invalidate(dayPlanProvider(widget.date));
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voted = widget.proposal.votedByMe;

    return TextButton.icon(
      onPressed: _busy ? null : _toggle,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        foregroundColor: voted ? theme.colorScheme.primary : null,
      ),
      icon: Icon(
        voted ? Icons.favorite : Icons.favorite_border,
        size: 18,
      ),
      label: Text('${widget.proposal.voteCount}'),
    );
  }
}
