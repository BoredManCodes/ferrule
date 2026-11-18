import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/ui_prefs.dart';

class _Page {
  final IconData icon;
  final String title;
  final String body;
  const _Page(this.icon, this.title, this.body);
}

const _pages = [
  _Page(
    Icons.dashboard_outlined,
    'Your ITFlow, in your pocket',
    'Home shows open tickets, assets, vault entries and clients at a glance. '
        'Banners your team posts in ITFlow show across the top, and on the '
        'client and ticket they belong to.',
  ),
  _Page(
    Icons.confirmation_number_outlined,
    'Work tickets',
    'Open a ticket to reply, edit it or resolve it. Pick Internal note to '
        'keep it to your team, Public reply to show it to the client, or '
        'Public + email to send it to them too.',
  ),
  _Page(
    Icons.timer_outlined,
    'Log your time',
    'Tap Start Timer on a ticket. The timer keeps running while you use the '
        'rest of the app (a bar across the top shows it), and stopping it '
        'logs the time to the ticket with your note.',
  ),
  _Page(
    Icons.route_outlined,
    'Trips and expenses',
    'The play button on Home starts a trip: GPS works out the distance, or '
        'type it in yourself. Add expenses with a photo of the receipt under '
        'Expenses, and take payments from an invoice.',
  ),
  _Page(
    Icons.tune,
    'Make it yours',
    'Use Contacts more than Assets? Swap them: More > Customize puts any '
        'section on the bottom bar. Settings has the theme, app lock and this '
        'tour again under Help.',
  ),
];

/// Shown once after the first sign-in; Settings > Help replays it.
class WelcomeTourScreen extends ConsumerStatefulWidget {
  const WelcomeTourScreen({super.key});

  @override
  ConsumerState<WelcomeTourScreen> createState() => _WelcomeTourScreenState();
}

class _WelcomeTourScreenState extends ConsumerState<WelcomeTourScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(uiPrefsProvider.notifier).setTourDone(true);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p.icon,
                              size: 56, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 32),
                        Text(p.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        Text(p.body,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.45)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut),
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
