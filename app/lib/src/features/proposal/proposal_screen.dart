import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Detail jídla: fotka, popis, hlasy, diskuze, potvrzení/odemknutí (zadání 4.4).
class ProposalScreen extends ConsumerStatefulWidget {
  const ProposalScreen({
    super.key,
    required this.date,
    required this.proposalId,
  });

  final String date;
  final String proposalId;

  @override
  ConsumerState<ProposalScreen> createState() => _ProposalScreenState();
}

class _ProposalScreenState extends ConsumerState<ProposalScreen> {
  final _commentController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Po každé změně je potřeba obnovit i den a týden, aby seděly indikátory.
  void _invalidateAll() {
    ref.invalidate(dayPlanProvider(widget.date));
    ref.invalidate(commentsProvider(widget.proposalId));
    ref.invalidate(weekPlanProvider(startOfWeek(parseApiDate(widget.date))));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _invalidateAll();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayAsync = ref.watch(dayPlanProvider(widget.date));

    return Scaffold(
      appBar: AppBar(title: const Text('Detail jídla')),
      body: dayAsync.when(
        loading: () => const LoadingView(),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(dayPlanProvider(widget.date)),
        ),
        data: (day) {
          final slot = _findSlot(day);
          final proposal = _findProposal(day);

          if (slot == null || proposal == null) {
            return const EmptyView(
              icon: Icons.search_off,
              title: 'Návrh už neexistuje',
              subtitle: 'Nejspíš ho někdo mezitím smazal.',
            );
          }

          return _Body(
            date: widget.date,
            slot: slot,
            proposal: proposal,
            busy: _busy,
            commentController: _commentController,
            onVote: () => _run(() async {
              final api = ref.read(apiServiceProvider);
              proposal.votedByMe
                  ? await api.unvote(proposal.id)
                  : await api.vote(proposal.id);
            }),
            onConfirm: () => _run(() async {
              await ref.read(apiServiceProvider).confirmProposal(proposal.id);
            }),
            onUnlock: () => _run(() async {
              await ref.read(apiServiceProvider).unlockProposal(proposal.id);
            }),
            onComment: () {
              final text = _commentController.text.trim();
              if (text.isEmpty) return;
              _run(() async {
                await ref.read(apiServiceProvider).addComment(
                      proposalId: proposal.id,
                      text: text,
                    );
                _commentController.clear();
              });
            },
            onDelete: () => _run(() async {
              await ref.read(apiServiceProvider).deleteProposal(proposal.id);
              if (context.mounted) context.pop();
            }),
          );
        },
      ),
    );
  }

  MealSlot? _findSlot(DayPlan day) {
    for (final slot in day.slots) {
      for (final p in slot.proposals) {
        if (p.id == widget.proposalId) return slot;
      }
    }
    return null;
  }

  MealProposal? _findProposal(DayPlan day) {
    for (final slot in day.slots) {
      for (final p in slot.proposals) {
        if (p.id == widget.proposalId) return p;
      }
    }
    return null;
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.date,
    required this.slot,
    required this.proposal,
    required this.busy,
    required this.commentController,
    required this.onVote,
    required this.onConfirm,
    required this.onUnlock,
    required this.onComment,
    required this.onDelete,
  });

  final String date;
  final MealSlot slot;
  final MealProposal proposal;
  final bool busy;
  final TextEditingController commentController;
  final VoidCallback onVote;
  final VoidCallback onConfirm;
  final VoidCallback onUnlock;
  final VoidCallback onComment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final isAuthor = user?.id == proposal.proposedBy.id;
    final comments = ref.watch(commentsProvider(proposal.id));
    final alternatives =
        slot.proposals.where((p) => p.id != proposal.id).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text(
                '${slot.label} · ${longDate(parseApiDate(date))}',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      proposal.title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (proposal.isConfirmed)
                    Chip(
                      avatar: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Potvrzeno'),
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Navrhl/a ${proposal.proposedBy.name}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (proposal.photoUrl != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    proposal.photoUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              ],
              if (proposal.description != null &&
                  proposal.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(proposal.description!, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onVote,
                      icon: Icon(proposal.votedByMe
                          ? Icons.favorite
                          : Icons.favorite_border),
                      label: Text(
                        proposal.voteCount == 0
                            ? 'Hlasovat'
                            : '${proposal.voteCount} '
                                '${_hlasy(proposal.voteCount)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: proposal.isConfirmed
                        ? OutlinedButton.icon(
                            onPressed: busy ? null : onUnlock,
                            icon: const Icon(Icons.lock_open_outlined),
                            label: const Text('Odemknout'),
                          )
                        : FilledButton.icon(
                            onPressed: busy ? null : onConfirm,
                            icon: const Icon(Icons.check),
                            label: const Text('Potvrdit'),
                          ),
                  ),
                ],
              ),
              if (isAuthor && !proposal.isConfirmed) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: busy ? null : () => _confirmDelete(context),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Smazat návrh'),
                ),
              ],
              if (alternatives.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Další návrhy na tento slot',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final alt in alternatives)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restaurant_outlined),
                    title: Text(alt.title),
                    subtitle: Text('${alt.voteCount} ${_hlasy(alt.voteCount)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.pushReplacement('/day/$date/proposal/${alt.id}'),
                  ),
              ],
              const SizedBox(height: 24),
              Text('Diskuze', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              comments.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, _) => Text(
                  'Komentáře se nepodařilo načíst.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                data: (list) => list.isEmpty
                    ? Text(
                        'Zatím bez komentářů. Napiš první!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        children: [
                          for (final c in list) _CommentTile(comment: c),
                        ],
                      ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onComment(),
                    decoration: const InputDecoration(
                      hintText: 'Napsat komentář…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? null : onComment,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smazat návrh?'),
        content: Text('„${proposal.title}“ zmizí i s hlasy a komentáři.'),
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
    if (ok == true) onDelete();
  }

  String _hlasy(int count) => switch (count) {
        1 => 'hlas',
        2 || 3 || 4 => 'hlasy',
        _ => 'hlasů',
      };
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final MealComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              comment.author.name.characters.first.toUpperCase(),
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.author.name,
                        style: theme.textTheme.labelLarge),
                    const SizedBox(width: 8),
                    Text(
                      commentTimestamp(comment.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
