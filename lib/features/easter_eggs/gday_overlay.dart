import 'dart:math';

import 'package:flutter/material.dart';

/// Shows a brief celebration overlay with the words "g'day mate" and a burst
/// of confetti. Auto-dismisses after the animation finishes.
void showGdayOverlay(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GdayOverlay(onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _GdayOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const _GdayOverlay({required this.onDone});

  @override
  State<_GdayOverlay> createState() => _GdayOverlayState();
}

class _GdayOverlayState extends State<_GdayOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Confetto> _confetti;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    _confetti = List.generate(80, (_) => _Confetto.random(_rng));
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            return CustomPaint(
              size: size,
              painter: _ConfettiPainter(_confetti, t, _rng),
              child: Center(
                child: Opacity(
                  opacity: _wordOpacity(t),
                  child: Transform.scale(
                    scale: _wordScale(t),
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFFFC107),
                          Color(0xFFE83E8C),
                          Color(0xFF6610F2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        "g'day mate",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                          color: Colors.white,
                          height: 1.0,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Word fades in fast, holds, then fades out toward the end.
  double _wordOpacity(double t) {
    if (t < 0.12) return t / 0.12;
    if (t > 0.78) return (1 - t) / 0.22;
    return 1.0;
  }

  double _wordScale(double t) {
    // Small overshoot bounce in.
    if (t < 0.18) {
      final p = t / 0.18;
      return 0.6 + (1.15 - 0.6) * Curves.easeOutBack.transform(p);
    }
    if (t < 0.32) return 1.15 - (1.15 - 1.0) * ((t - 0.18) / 0.14);
    return 1.0;
  }
}

class _Confetto {
  final double angle; // launch angle (radians)
  final double speed; // base speed factor
  final double size;
  final double startOffsetX; // horizontal start jitter [-1, 1]
  final Color color;
  final double rotationSpeed;

  const _Confetto({
    required this.angle,
    required this.speed,
    required this.size,
    required this.startOffsetX,
    required this.color,
    required this.rotationSpeed,
  });

  factory _Confetto.random(Random r) {
    const palette = [
      Color(0xFFE83E8C),
      Color(0xFFFFC107),
      Color(0xFF28A745),
      Color(0xFF17A2B8),
      Color(0xFF6610F2),
      Color(0xFFFF851B),
    ];
    // Launch angles cluster upward from the bottom-center.
    final base = -pi / 2; // straight up
    final spread = (r.nextDouble() - 0.5) * (pi * 1.1); // wide cone
    return _Confetto(
      angle: base + spread,
      speed: 600 + r.nextDouble() * 900,
      size: 6 + r.nextDouble() * 8,
      startOffsetX: (r.nextDouble() - 0.5) * 0.4,
      color: palette[r.nextInt(palette.length)],
      rotationSpeed: (r.nextDouble() - 0.5) * 14,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetto> confetti;
  final double t;
  final Random rng;

  _ConfettiPainter(this.confetti, this.t, this.rng);

  @override
  void paint(Canvas canvas, Size size) {
    final originX = size.width / 2;
    final originY = size.height + 20;
    const gravity = 1400.0;
    for (final c in confetti) {
      // Position via projectile motion. Pixels per unit-t (where t spans 2.2s).
      final tSec = t * 2.2;
      final vx = cos(c.angle) * c.speed;
      final vy = sin(c.angle) * c.speed;
      final x = originX + c.startOffsetX * size.width / 2 + vx * tSec;
      final y = originY + vy * tSec + 0.5 * gravity * tSec * tSec;
      // Fade as it falls past bottom.
      if (y > size.height + 60) continue;
      final opacity = (1.0 - (t - 0.55).clamp(0.0, 1.0) / 0.45).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = c.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(c.rotationSpeed * tSec);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: c.size, height: c.size * 1.6),
          Radius.circular(c.size / 4),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
