import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/ui_prefs.dart';

/// Choose what sits on the bottom bar (up to four, plus More) and the order
/// of everything listed under More. Drag to reorder; the arrow moves an
/// item between the two lists.
class NavigationSettingsScreen extends ConsumerStatefulWidget {
  const NavigationSettingsScreen({super.key});

  @override
  ConsumerState<NavigationSettingsScreen> createState() =>
      _NavigationSettingsScreenState();
}

class _NavigationSettingsScreenState
    extends ConsumerState<NavigationSettingsScreen> {
  List<String>? _bar;
  List<String>? _more;

  void _ensureLoaded(UiPrefs p) {
    _bar ??= [...p.bar];
    _more ??= [for (final d in p.moreDests) d.path];
  }

  Future<void> _save() =>
      ref.read(uiPrefsProvider.notifier).setNav(_bar!, _more!);

  void _toBar(String path) {
    if (_bar!.length >= maxBarItems) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'The bar holds $maxBarItems plus More. Move one off it first.')));
      return;
    }
    setState(() {
      _more!.remove(path);
      _bar!.add(path);
    });
    _save();
  }

  void _toMore(String path) {
    if (_bar!.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keep at least one item on the bar.')));
      return;
    }
    setState(() {
      _bar!.remove(path);
      _more!.insert(0, path);
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(uiPrefsProvider).value;
    if (prefs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _ensureLoaded(prefs);
    final bar = _bar!, more = _more!;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant);

    Widget tile(String path, {required bool onBar, required int index}) {
      final d = navDestFor(path)!;
      return ListTile(
        key: ValueKey(path),
        leading: Icon(d.icon),
        title: Text(d.label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: onBar ? 'Move to More' : 'Move to the bar',
              icon: Icon(onBar
                  ? Icons.arrow_downward
                  : Icons.arrow_upward),
              onPressed: () => onBar ? _toMore(path) : _toBar(path),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(uiPrefsProvider.notifier).resetNav();
              setState(() {
                _bar = null;
                _more = null;
              });
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Bottom bar (${bar.length} of $maxBarItems, then More)',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          SliverReorderableList(
            itemCount: bar.length,
            itemBuilder: (_, i) => Material(
                key: ValueKey('bar-${bar[i]}'),
                child: tile(bar[i], onBar: true, index: i)),
            onReorder: (a, b) {
              setState(() {
                if (b > a) b--;
                bar.insert(b, bar.removeAt(a));
              });
              _save();
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text('Under More', style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          SliverReorderableList(
            itemCount: more.length,
            itemBuilder: (_, i) => Material(
                key: ValueKey('more-${more[i]}'),
                child: tile(more[i], onBar: false, index: i)),
            onReorder: (a, b) {
              setState(() {
                if (b > a) b--;
                more.insert(b, more.removeAt(a));
              });
              _save();
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Text(
                  'Changes apply straight away. Settings stays at the bottom of More.',
                  style: small),
            ),
          ),
        ],
      ),
    );
  }
}
