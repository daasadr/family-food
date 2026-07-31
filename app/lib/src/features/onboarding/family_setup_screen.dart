import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Uživatel je přihlášený, ale ještě není v žádné rodině:
/// buď ji založí, nebo přijme pozvánku kódem.
class FamilySetupScreen extends ConsumerStatefulWidget {
  const FamilySetupScreen({super.key});

  @override
  ConsumerState<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends ConsumerState<FamilySetupScreen> {
  final _familyName = TextEditingController();
  final _inviteCode = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _familyName.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rodinný profil'),
        actions: [
          IconButton(
            tooltip: 'Odhlásit se',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Vítej${user != null ? ', ${user.name}' : ''}!',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Založ rodinu, nebo se připoj k té, která tě pozvala.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.home_outlined,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('Založit novou rodinu',
                                  style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _familyName,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Název rodiny',
                              hintText: 'např. Novákovi',
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    final name = _familyName.text.trim();
                                    if (name.isEmpty) {
                                      showMessage(
                                        context,
                                        'Zadej název rodiny.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                    _run(() => ref
                                        .read(authProvider.notifier)
                                        .createFamily(name));
                                  },
                            child: const Text('Založit rodinu'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('nebo',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.group_add_outlined,
                                  color: theme.colorScheme.tertiary),
                              const SizedBox(width: 8),
                              Text('Připojit se k rodině',
                                  style: theme.textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _inviteCode,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Kód pozvánky',
                              hintText: 'ABCDE-FGHIJ',
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    final code =
                                        _inviteCode.text.trim().toUpperCase();
                                    if (code.isEmpty) {
                                      showMessage(
                                        context,
                                        'Zadej kód pozvánky.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                    _run(() => ref
                                        .read(authProvider.notifier)
                                        .acceptInvite(code));
                                  },
                            child: const Text('Připojit se'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
