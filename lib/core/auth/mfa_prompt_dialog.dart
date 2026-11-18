import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for the 6-digit code from the person's authenticator app.
/// Returns null on cancel.
Future<String?> showMfaPromptDialog(
  BuildContext context, {
  required String email,
  String? error,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MfaPromptDialog(email: email, error: error),
  );
}

class _MfaPromptDialog extends StatefulWidget {
  final String email;
  final String? error;
  const _MfaPromptDialog({required this.email, this.error});

  @override
  State<_MfaPromptDialog> createState() => _MfaPromptDialogState();
}

class _MfaPromptDialogState extends State<_MfaPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.length == 6;

  void _submit() {
    if (_valid) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.shield_outlined),
      title: const Text('2FA code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ITFlow wants the code from your authenticator app for '
            '${widget.email}.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(letterSpacing: 8, fontFeatures: const [
              FontFeature.tabularFigures(),
            ]),
            decoration: InputDecoration(
              hintText: '000000',
              errorText: widget.error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            'Ferrule remembers this device afterwards, for as many days as '
            'your ITFlow allows, then asks again.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Verify'),
        ),
      ],
    );
  }
}
