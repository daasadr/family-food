import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Nový návrh jídla do slotu. Název lze psát volně, nebo vybrat
/// z předvytvořené i rodinné galerie (zadání 4.4 a 5).
class ProposeMealScreen extends ConsumerStatefulWidget {
  const ProposeMealScreen({
    super.key,
    required this.date,
    required this.slotId,
  });

  final String date;
  final String slotId;

  @override
  ConsumerState<ProposeMealScreen> createState() => _ProposeMealScreenState();
}

class _ProposeMealScreenState extends ConsumerState<ProposeMealScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _search = TextEditingController();

  String? _photoUrl;
  String _searchQuery = '';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'Zadej název jídla.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(apiServiceProvider).createProposal(
            slotId: widget.slotId,
            title: title,
            description: _description.text.trim(),
            photoUrl: _photoUrl,
          );
      ref.invalidate(dayPlanProvider(widget.date));
      ref.invalidate(
        weekPlanProvider(startOfWeek(parseApiDate(widget.date))),
      );
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gallery = ref.watch(galleryProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(title: const Text('Navrhnout jídlo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Název jídla',
              hintText: 'např. Svíčková na smetaně',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Poznámka (nepovinné)',
              hintText: 'Příloha, kdo vaří, na co nezapomenout…',
            ),
          ),
          if (_photoUrl != null) ...[
            const SizedBox(height: 16),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _photoUrl!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 140,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _photoUrl = null),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('Vybrat z galerie', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Hledat jídlo…',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
            ),
            onSubmitted: (value) => setState(() => _searchQuery = value.trim()),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: gallery.when(
              loading: () => const LoadingView(),
              error: (err, _) => Center(
                child: Text(
                  'Galerii se nepodařilo načíst.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Text(
                        'Nic nenalezeno.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => _GalleryCard(
                        item: items[index],
                        onTap: () {
                          setState(() {
                            _title.text = items[index].title;
                            _photoUrl = items[index].photoUrl;
                          });
                        },
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Přidat návrh'),
          ),
        ],
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({required this.item, required this.onTap});

  final GalleryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item.photoUrl,
                height: 90,
                width: 130,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 90,
                  width: 130,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.restaurant_outlined),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
