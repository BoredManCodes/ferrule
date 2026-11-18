import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/providers.dart';
import '../../core/settings/app_settings.dart';
import '../assets/asset_repository.dart';
import '../clients/client_repository.dart';
import '../credentials/credential_repository.dart';
import '../easter_eggs/gday_overlay.dart';
import '../easter_eggs/rapid_tap.dart';
import '../tickets/ticket_repository.dart';
import '../trips/active_trip.dart';
import '../trips/trip_actions.dart';
import '../banners/agent_banners.dart';
import '../../core/auth/api_key_provisioning.dart';
import '../onboarding/tips.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(ticketsProvider);
    final assets = ref.watch(assetsProvider);
    final clients = ref.watch(clientsProvider);
    final credentials = ref.watch(credentialsListProvider);

    final settings = ref.watch(appSettingsProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: RapidTap(
          count: 5,
          onTrigger: () => showGdayOverlay(context),
          child: Text(settings?.effectiveTitle ?? 'ITFlow'),
        ),
        actions: [
          const _TripQuickAction(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ticketsProvider);
          ref.invalidate(assetsProvider);
          ref.invalidate(clientsProvider);
          ref.invalidate(credentialsListProvider);
          ref.invalidate(globalBannersProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _KeyExpiryWarning(),
            const AgentBannerStrip(),
            const FirstVisitTip(
              id: 'home.welcome',
              margin: EdgeInsets.only(bottom: 12),
              text:
                  'Tap a card to jump to that list. The play button up top starts a trip, and banners your team posts in ITFlow show here.',
            ),
            Text('Overview',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _StatCard(
                  title: 'Open Tickets',
                  icon: Icons.confirmation_number_outlined,
                  value: tickets.whenOrNull(
                          data: (t) =>
                              t.where((x) => !x.isResolved).length.toString()) ??
                      '…',
                  onTap: () => context.go('/tickets'),
                  color: Colors.orange,
                ),
                _StatCard(
                  title: 'Assets',
                  icon: Icons.devices_other_outlined,
                  value: assets.whenOrNull(
                          data: (a) => a.length.toString()) ??
                      '…',
                  onTap: () => context.go('/assets'),
                  color: Colors.blue,
                ),
                _StatCard(
                  title: 'Credentials',
                  icon: Icons.vpn_key_outlined,
                  value: credentials.whenOrNull(
                          data: (s) => s.items.length.toString()) ??
                      '…',
                  onTap: () => context.go('/credentials'),
                  color: Colors.purple,
                ),
                _StatCard(
                  title: 'Clients',
                  icon: Icons.business_outlined,
                  value: clients.whenOrNull(
                          data: (c) =>
                              c.where((x) => !x.archived).length.toString()) ??
                      '…',
                  onTap: () => context.go('/clients'),
                  color: Colors.teal,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Recent Tickets',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => context.go('/tickets'),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            tickets.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      Text('Unable to load tickets.\n$e', style: const TextStyle(fontSize: 12)),
                ),
              ),
              data: (list) {
                final recent = [...list]
                  ..sort((a, b) => (b.createdAt ?? DateTime(0))
                      .compareTo(a.createdAt ?? DateTime(0)));
                final top = recent.take(6).toList();
                if (top.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No tickets yet')),
                    ),
                  );
                }
                return Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < top.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          onTap: () => context.push('/tickets/${top[i].id}'),
                          leading: CircleAvatar(
                            backgroundColor: top[i].isResolved
                                ? Colors.green.withValues(alpha: 0.15)
                                : Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                            child: Icon(
                              top[i].isResolved
                                  ? Icons.check
                                  : Icons.confirmation_number_outlined,
                              size: 18,
                              color: top[i].isResolved
                                  ? Colors.green
                                  : Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                            ),
                          ),
                          title: Text(top[i].subject ?? '(no subject)',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text([
                            top[i].displayNumber,
                            if (top[i].createdAt != null)
                              DateFormat.MMMd().format(top[i].createdAt!),
                          ].join(' • ')),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TripQuickAction extends ConsumerWidget {
  const _TripQuickAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWebCreds = ref.watch(itflowWebClientProvider) != null;
    final active = ref.watch(activeTripProvider).value;
    if (active != null) {
      // Trip in progress — show a Stop button that opens the active-trip
      // screen (where the actual stop logic runs). Pulses with the accent so
      // it's easy to spot from the home page.
      final scheme = Theme.of(context).colorScheme;
      return IconButton(
        tooltip: 'Trip in progress — tap to stop',
        icon: Icon(Icons.stop_circle, color: scheme.error),
        onPressed: () => context.push('/trips/active'),
      );
    }
    return IconButton(
      tooltip: hasWebCreds
          ? 'Start trip'
          : 'Add agent credentials in Settings to track trips',
      icon: const Icon(Icons.play_circle_outline),
      onPressed: hasWebCreds ? () => startTripFlow(context, ref) : null,
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final Color color;

  const _StatCard({
    required this.title,
    required this.icon,
    required this.value,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward,
                      size: 16,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: Theme.of(context).textTheme.headlineMedium),
                  Text(title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// A key from a setup code (or pasted in) can't be renewed by the app, so
/// say so a month before it stops working.
class _KeyExpiryWarning extends ConsumerWidget {
  const _KeyExpiryWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider).value;
    final exp = creds?.apiKeyExpiresAt;
    if (creds == null || creds.apiKeyManaged || exp == null) {
      return const SizedBox.shrink();
    }
    final left = exp.difference(DateTime.now());
    if (left > keyExpiryWarning) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final days = left.inDays;
    final when = days <= 0 ? 'today' : 'in $days day${days == 1 ? '' : 's'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'The ITFlow key on this phone stops working $when. Ask an admin to make you '
        'a new setup code (Ferrule > Settings > Set up a technician), then '
        'sign out and scan it.',
        style: TextStyle(color: scheme.onErrorContainer, height: 1.35),
      ),
    );
  }
}
