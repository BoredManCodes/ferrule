import 'dart:async';

import 'package:flutter/material.dart';

/// Wraps [child] in a transparent gesture detector that counts how many times
/// the user has tapped within [window]. Each tap resets the timeout; when the
/// running count reaches [count], [onTrigger] fires and the counter resets.
class RapidTap extends StatefulWidget {
  final Widget child;
  final int count;
  final Duration window;
  final VoidCallback onTrigger;
  const RapidTap({
    super.key,
    required this.child,
    required this.count,
    required this.onTrigger,
    this.window = const Duration(milliseconds: 1500),
  });

  @override
  State<RapidTap> createState() => _RapidTapState();
}

class _RapidTapState extends State<RapidTap> {
  int _hits = 0;
  Timer? _reset;

  void _onTap() {
    _hits++;
    _reset?.cancel();
    if (_hits >= widget.count) {
      _hits = 0;
      widget.onTrigger();
      return;
    }
    _reset = Timer(widget.window, () => _hits = 0);
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}
