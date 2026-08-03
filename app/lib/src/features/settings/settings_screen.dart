import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final family = ref.watch(familyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nastavení')),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: CircleAvatar(
                child: Text(user.name.characters.first.toUpperCase()),
              ),
              title: Text(user.name),
              subtitle: Text(user.email),
            ),
          const Divider(),
          family.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => ErrorView(
              message: err.toString(),
              onRetry: () => ref.invalidate(familyProvider),
            ),
            data: (f) => Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Rodina'),
                  subtitle: Text('${f.name} · ${f.members.length} '
                      '${_clenove(f.members.length)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/family'),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Šablona jídel'),
                  subtitle: const Text('Které sloty se plánují každý den'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/template'),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Odhlásit se'),
            onTap: () => ref.read(authProvider.notifier).logout(),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Smazat účet',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Nevratně odstraní účet i tvá data'),
            onTap: () => _deleteAccount(context, ref),
          ),
        ],
      ),
    );
  }

  /// Smazání účtu podle GDPR — vyžadují ho i Google Play a App Store.
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Opravdu smazat účet?'),
        content: const Text(
          'Účet, tvé návrhy jídel, hlasy a komentáře se nenávratně smažou. '
          'Pokud jsi v rodině sám, zmizí i celý jídelníček rodiny.\n\n'
          'Tuhle akci nelze vzít zpět.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Smazat účet'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(apiServiceProvider).deleteAccount();
      // Odhlášení uklidí tokeny a vrátí na přihlašovací obrazovku.
      await ref.read(authProvider.notifier).logout();
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }

  String _clenove(int count) => switch (count) {
        1 => 'člen',
        2 || 3 || 4 => 'členové',
        _ => 'členů',
      };
}

/// Správa rodiny — členové a pozvánky (zadání 4.1).
class FamilySettingsScreen extends ConsumerWidget {
  const FamilySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(familyProvider);
    final invites = ref.watch(invitesProvider);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rodina')),
      body: family.when(
        loading: () => const LoadingView(),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(familyProvider),
        ),
        data: (f) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Členové',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final member in f.members)
              ListTile(
                leading: CircleAvatar(
                  child: Text(member.name.characters.first.toUpperCase()),
                ),
                title: Text(member.name),
                subtitle: Text(member.email),
                trailing: member.isOwner
                    ? const Chip(
                        label: Text('vlastník'),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Pozvánky',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  TextButton.icon(
                    onPressed: () => _createInvite(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nová'),
                  ),
                ],
              ),
            ),
            invites.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Pozvánky se nepodařilo načíst.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Zatím žádné pozvánky.'),
                    )
                  : Column(
                      children: [
                        for (final invite in list)
                          ListTile(
                            leading: Icon(_inviteIcon(invite.status)),
                            title: Text(invite.email ?? 'Sdílený kód'),
                            subtitle: Text(_inviteStatus(invite)),
                            trailing: invite.status == 'pending'
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _revoke(
                                        context, ref, invite.id),
                                  )
                                : null,
                          ),
                      ],
                    ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => _leave(context, ref, f, me),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Opustit rodinu'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _inviteIcon(String status) => switch (status) {
        'accepted' => Icons.check_circle_outline,
        'expired' => Icons.timer_off_outlined,
        'revoked' => Icons.block,
        _ => Icons.mail_outline,
      };

  String _inviteStatus(Invite invite) => switch (invite.status) {
        'accepted' => 'přijata',
        'expired' => 'vypršela',
        'revoked' => 'zrušena',
        _ => 'čeká na přijetí',
      };

  Future<void> _createInvite(BuildContext context, WidgetRef ref) async {
    try {
      final invite = await ref.read(apiServiceProvider).createInvite();
      ref.invalidate(invitesProvider);
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pozvánka vytvořena'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pošli tento kód tomu, koho zveš. '
                  'Zobrazí se jen teď — později už ho nepůjde zjistit.'),
              const SizedBox(height: 16),
              SelectableText(
                invite.code ?? '',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFeatures: const [],
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hotovo'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }

  Future<void> _revoke(
      BuildContext context, WidgetRef ref, String inviteId) async {
    try {
      await ref.read(apiServiceProvider).revokeInvite(inviteId);
      ref.invalidate(invitesProvider);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }

  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    Family family,
    AppUser? me,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Opustit rodinu?'),
        content: Text('Přijdeš o přístup k jídelníčku rodiny ${family.name}. '
            'Zpět se dostaneš jen novou pozvánkou.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Opustit'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(authProvider.notifier).leaveFamily();
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }
}

/// Nastavení šablony slotů (zadání 4.5).
class TemplateSettingsScreen extends ConsumerStatefulWidget {
  const TemplateSettingsScreen({super.key});

  @override
  ConsumerState<TemplateSettingsScreen> createState() =>
      _TemplateSettingsScreenState();
}

class _TemplateSettingsScreenState
    extends ConsumerState<TemplateSettingsScreen> {
  List<TemplateSlot>? _draft;
  bool _busy = false;

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;

    if (!draft.any((s) => s.enabled)) {
      showMessage(context, 'Aspoň jeden slot musí zůstat zapnutý.',
          isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(apiServiceProvider).saveTemplate(draft);
      ref.invalidate(templateProvider);
      // Nové sloty se projeví až v dnech, které se načtou znovu.
      ref.invalidate(weekPlanProvider);
      ref.invalidate(dayPlanProvider);
      if (mounted) {
        showMessage(context, 'Šablona uložena.');
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = ref.watch(templateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Šablona jídel'),
        actions: [
          TextButton(
            onPressed: _busy || _draft == null ? null : _save,
            child: const Text('Uložit'),
          ),
        ],
      ),
      body: template.when(
        loading: () => const LoadingView(),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(templateProvider),
        ),
        data: (t) {
          _draft ??= [...t.slots];
          final draft = _draft!;

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Zapnuté sloty se generují do každého dne. '
                  'Vypnutí slotu neodstraní už naplánovaná jídla.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              for (var i = 0; i < draft.length; i++)
                SwitchListTile(
                  title: Text(draft[i].label),
                  value: draft[i].enabled,
                  onChanged: _busy
                      ? null
                      : (value) => setState(
                            () => draft[i] = draft[i].copyWith(enabled: value),
                          ),
                ),
            ],
          );
        },
      ),
    );
  }
}
