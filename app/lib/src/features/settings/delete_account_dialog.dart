import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Potvrzení smazání účtu.
///
/// Poslednímu členovi rodiny s účtem mizí i celá rodina a její jídelníček,
/// takže tenhle případ dostane červené varování s výčtem toho, o co přijde,
/// a musí přesně opsat název rodiny. Kdo v rodině zůstává nebo v žádné není,
/// potvrdí jen tlačítkem.
///
/// Vrací `true`, když se účet smazal.
Future<bool> showDeleteAccountDialog(BuildContext context, WidgetRef ref) async {
  DeletionPreview preview;
  try {
    preview = await ref.read(apiServiceProvider).deletionPreview();
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return false;
  }

  if (!context.mounted) return false;

  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeleteAccountDialog(preview: preview),
  );

  return deleted ?? false;
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.preview});

  final DeletionPreview preview;

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _requiresTyping => widget.preview.willDeleteFamily;

  /// Porovnání stejně shovívavé jako na backendu — bez ohledu na velikost
  /// písmen a okolní mezery.
  bool get _nameMatches {
    if (!_requiresTyping) return true;
    final expected = widget.preview.familyName?.trim().toLowerCase() ?? '';
    return _controller.text.trim().toLowerCase() == expected;
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiServiceProvider).deleteAccount(
            confirmFamilyName: _requiresTyping ? _controller.text.trim() : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = widget.preview;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 32),
      title: Text(_requiresTyping ? 'Smaže se i celá rodina' : 'Smazat účet?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_requiresTyping)
              ..._familyWarning(theme, preview)
            else
              ..._simpleWarning(theme, preview),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Zrušit'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: (_busy || !_nameMatches) ? null : _delete,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_requiresTyping ? 'Smazat účet i rodinu' : 'Smazat účet'),
        ),
      ],
    );
  }

  /// Poslední člen rodiny — nejtvrdší varianta.
  List<Widget> _familyWarning(ThemeData theme, DeletionPreview preview) {
    final data = preview.familyData;

    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jsi poslední člen rodiny „${preview.familyName}".',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Se smazáním účtu nenávratně zmizí i celá rodina a všechno, '
              'co je v ní uložené.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
            if (data != null && !data.isEmpty) ...[
              const SizedBox(height: 12),
              for (final line in data.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '· $line',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Pokud si chceš data nechat nebo někdy založit novou rodinu, '
        'účet si můžeš ponechat — stačí dialog zavřít.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      Text(
        'Pro potvrzení opiš název rodiny:',
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      SelectableText(
        preview.familyName ?? '',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.error,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          isDense: true,
          hintText: 'Název rodiny',
          suffixIcon: _nameMatches
              ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  /// V rodině někdo zůstává, nebo uživatel v žádné není.
  List<Widget> _simpleWarning(ThemeData theme, DeletionPreview preview) {
    return [
      Text(
        'Tvůj účet, návrhy jídel, hlasy a komentáře se nenávratně smažou.',
        style: theme.textTheme.bodyMedium,
      ),
      if (preview.memberCount > 1) ...[
        const SizedBox(height: 12),
        Text(
          'Rodina „${preview.familyName}" zůstane ostatním členům '
          'i s celým jídelníčkem.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
      if (preview.newOwnerName != null) ...[
        const SizedBox(height: 8),
        Text(
          'Vlastnictví rodiny převezme ${preview.newOwnerName}.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    ];
  }
}
