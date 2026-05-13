import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';

/// A compact button that calls the ITFlow web UI's AI reword endpoint and
/// replaces the text in the given controller with the response.
///
/// Renders nothing if web (session) credentials aren't configured — the
/// reword endpoint lives behind a logged-in agent session, not the API key.
class AiRewordButton extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool dense;

  const AiRewordButton({
    super.key,
    required this.controller,
    this.label = 'AI reword',
    this.dense = false,
  });

  @override
  ConsumerState<AiRewordButton> createState() => _AiRewordButtonState();
}

class _AiRewordButtonState extends ConsumerState<AiRewordButton> {
  bool _busy = false;

  Future<void> _run() async {
    final input = widget.controller.text;
    if (input.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nothing to reword'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      final web = ref.read(itflowWebClientProvider);
      if (web == null) {
        throw StateError(
            'Web credentials not set. Add agent email + password in Settings to use AI reword.');
      }
      final out = await web.rewordText(input);
      if (!mounted) return;
      widget.controller.text = out;
      widget.controller.selection =
          TextSelection.collapsed(offset: out.length);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Text reworded'),
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('ApiException(null): ', '')),
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWeb = ref.watch(itflowWebClientProvider) != null;
    if (!hasWeb) return const SizedBox.shrink();

    final icon = _busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.auto_awesome, size: 16);

    if (widget.dense) {
      return IconButton(
        tooltip: widget.label,
        onPressed: _busy ? null : _run,
        icon: icon,
        visualDensity: VisualDensity.compact,
      );
    }
    return TextButton.icon(
      onPressed: _busy ? null : _run,
      icon: icon,
      label: Text(widget.label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
    );
  }
}
