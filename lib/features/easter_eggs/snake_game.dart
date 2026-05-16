import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pushes the snake game as a full-screen route.
Future<void> openFerruleSnake(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const _SnakeGameScreen(),
    ),
  );
}

enum _Dir { up, down, left, right }

extension on _Dir {
  Point<int> get delta {
    switch (this) {
      case _Dir.up:
        return const Point(0, -1);
      case _Dir.down:
        return const Point(0, 1);
      case _Dir.left:
        return const Point(-1, 0);
      case _Dir.right:
        return const Point(1, 0);
    }
  }

  bool isOpposite(_Dir other) =>
      (this == _Dir.up && other == _Dir.down) ||
      (this == _Dir.down && other == _Dir.up) ||
      (this == _Dir.left && other == _Dir.right) ||
      (this == _Dir.right && other == _Dir.left);
}

class _SnakeGameScreen extends StatefulWidget {
  const _SnakeGameScreen();

  @override
  State<_SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends State<_SnakeGameScreen> {
  static const int _cols = 18;
  static const int _rows = 28;
  static const int _startLen = 4;

  final _rng = Random();
  late List<Point<int>> _snake;
  late Point<int> _food;
  _Dir _dir = _Dir.right;
  _Dir _pendingDir = _Dir.right;
  Timer? _ticker;
  bool _playing = false;
  bool _gameOver = false;
  int _score = 0;
  int _best = 0;
  Duration _tickInterval = const Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final cx = _cols ~/ 2;
    final cy = _rows ~/ 2;
    _snake = List.generate(_startLen, (i) => Point(cx - i, cy));
    _dir = _Dir.right;
    _pendingDir = _Dir.right;
    _score = 0;
    _gameOver = false;
    _spawnFood();
    _tickInterval = const Duration(milliseconds: 180);
  }

  void _start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
    setState(() => _playing = true);
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _playing = false);
  }

  void _spawnFood() {
    while (true) {
      final p = Point(_rng.nextInt(_cols), _rng.nextInt(_rows));
      if (!_snake.contains(p)) {
        _food = p;
        return;
      }
    }
  }

  void _tick() {
    _dir = _pendingDir;
    final head = _snake.first;
    final next = Point(head.x + _dir.delta.x, head.y + _dir.delta.y);

    final hitWall = next.x < 0 || next.y < 0 || next.x >= _cols || next.y >= _rows;
    final hitSelf = _snake.contains(next);
    if (hitWall || hitSelf) {
      _stop();
      HapticFeedback.heavyImpact();
      setState(() {
        _gameOver = true;
        if (_score > _best) _best = _score;
      });
      return;
    }

    setState(() {
      _snake.insert(0, next);
      if (next == _food) {
        _score++;
        _spawnFood();
        HapticFeedback.lightImpact();
        // Gradually speed up: every 4 fruit shaves 8ms off the tick.
        if (_score % 4 == 0) {
          final ms = max(70, _tickInterval.inMilliseconds - 8);
          _tickInterval = Duration(milliseconds: ms);
          _ticker?.cancel();
          _ticker = Timer.periodic(_tickInterval, (_) => _tick());
        }
      } else {
        _snake.removeLast();
      }
    });
  }

  void _setDir(_Dir d) {
    if (d.isOpposite(_dir)) return;
    _pendingDir = d;
    if (!_playing && !_gameOver) _start();
  }

  void _onSwipe(Offset delta) {
    final dx = delta.dx;
    final dy = delta.dy;
    if (dx.abs() > dy.abs()) {
      _setDir(dx > 0 ? _Dir.right : _Dir.left);
    } else {
      _setDir(dy > 0 ? _Dir.down : _Dir.up);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ferrule Snake'),
        backgroundColor: scheme.surfaceContainerHigh,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  _Stat(label: 'Score', value: _score.toString()),
                  const Spacer(),
                  _Stat(label: 'Best', value: _best.toString()),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: AspectRatio(
                  aspectRatio: _cols / _rows,
                  child: GestureDetector(
                    onPanEnd: (d) => _onSwipe(d.velocity.pixelsPerSecond),
                    onTap: () {
                      if (_gameOver) {
                        setState(_reset);
                      } else if (!_playing) {
                        _start();
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.3)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CustomPaint(
                          painter: _BoardPainter(
                            snake: _snake,
                            food: _food,
                            cols: _cols,
                            rows: _rows,
                            snakeColor: scheme.primary,
                            snakeHeadColor: scheme.primary,
                            foodColor: scheme.tertiary,
                            gridColor:
                                scheme.outline.withValues(alpha: 0.08),
                          ),
                          child: _gameOver || !_playing
                              ? Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: scheme.surface
                                          .withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _gameOver
                                              ? 'Game over'
                                              : 'Swipe or tap to start',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        if (_gameOver) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                              'Tap the board to play again',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // On-screen D-pad for folks who prefer taps to swipes.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                children: [
                  _DirBtn(icon: Icons.keyboard_arrow_up, onTap: () => _setDir(_Dir.up)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DirBtn(icon: Icons.keyboard_arrow_left, onTap: () => _setDir(_Dir.left)),
                      const SizedBox(width: 56),
                      _DirBtn(icon: Icons.keyboard_arrow_right, onTap: () => _setDir(_Dir.right)),
                    ],
                  ),
                  _DirBtn(icon: Icons.keyboard_arrow_down, onTap: () => _setDir(_Dir.down)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                )),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

class _DirBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _DirBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, size: 28),
          ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final int cols;
  final int rows;
  final Color snakeColor;
  final Color snakeHeadColor;
  final Color foodColor;
  final Color gridColor;
  _BoardPainter({
    required this.snake,
    required this.food,
    required this.cols,
    required this.rows,
    required this.snakeColor,
    required this.snakeHeadColor,
    required this.foodColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    // Light grid lines.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i < cols; i++) {
      canvas.drawLine(
          Offset(i * cellW, 0), Offset(i * cellW, size.height), gridPaint);
    }
    for (var j = 1; j < rows; j++) {
      canvas.drawLine(
          Offset(0, j * cellH), Offset(size.width, j * cellH), gridPaint);
    }

    // Food: rounded cell.
    final foodRect = Rect.fromLTWH(
      food.x * cellW + 2,
      food.y * cellH + 2,
      cellW - 4,
      cellH - 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(foodRect, Radius.circular(cellW / 3)),
      Paint()..color = foodColor,
    );

    // Snake.
    for (var i = 0; i < snake.length; i++) {
      final s = snake[i];
      final rect = Rect.fromLTWH(
        s.x * cellW + 1,
        s.y * cellH + 1,
        cellW - 2,
        cellH - 2,
      );
      final color = i == 0
          ? snakeHeadColor
          : Color.lerp(snakeColor, snakeHeadColor.withValues(alpha: 0.6),
              i / max(1, snake.length))!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellW / 4)),
        Paint()..color = color,
      );
      if (i == 0) {
        // Tiny "eye" highlight on the head.
        final eyePaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
        canvas.drawCircle(
          rect.center.translate(cellW / 6, -cellH / 6),
          cellW / 12,
          eyePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
