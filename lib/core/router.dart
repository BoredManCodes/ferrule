import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/assets/asset_form_screen.dart';
import '../features/assets/asset_detail_screen.dart';
import '../features/assets/asset_scan_screen.dart';
import '../features/assets/assets_screen.dart';
import '../features/banners/banner_screens.dart';
import '../features/clients/client_detail_screen.dart';
import '../features/clients/clients_screen.dart';
import '../features/consent/crash_consent_screen.dart';
import '../features/contacts/contact_detail_screen.dart';
import '../features/contacts/contacts_screen.dart';
import '../features/credentials/credential_detail_screen.dart';
import '../features/credentials/credential_form_screen.dart';
import '../features/credentials/credentials_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/expenses/expense_form_screen.dart';
import '../features/invoices/pay_qr_screen.dart';
import '../features/invoices/payment_form_screen.dart';
import '../features/invoices/quick_pay.dart';
import '../features/lock/lock_screen.dart';
import '../features/more/more_screen.dart';
import '../features/onboarding/welcome_tour_screen.dart';
import '../features/settings/navigation_settings_screen.dart';
import '../features/settings/setup_code_screen.dart';
import '../features/readonly/readonly_screens.dart';
import '../features/settings/privacy_policy_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/tickets/create_ticket_screen.dart';
import '../features/tickets/edit_ticket_screen.dart';
import '../features/tickets/ticket_detail_screen.dart';
import '../features/tickets/tickets_screen.dart';
import '../features/timer/timer_screen.dart';
import '../features/trips/active_trip_screen.dart';
import '../features/trips/new_trip_screen.dart';
import '../features/trips/start_trip_screen.dart';
import '../features/trips/trip_form_data.dart';
import '../features/trips/trips_screen.dart';
import 'api/providers.dart';
import 'auth/app_lock.dart';
import 'sentry/sentry_config.dart';
import 'settings/app_settings.dart';
import 'settings/crash_consent.dart';
import 'settings/ui_prefs.dart';

/// Where to send someone at [loc], or null to stay. Gates in order:
/// crash consent, sign-in, app lock, then the welcome tour. Each gate's
/// own screen is left alone while that gate is open, so two gates can't
/// bounce between each other (1.2.1 looped /consent <-> /welcome).
String? appRedirect({
  required String loc,
  required bool loggedIn,
  required bool consentNeeded,
  required bool lockRequired,
  required bool tourDone,
}) {
  // Privacy policy is always reachable; it has to be readable before
  // the user agrees to anything (consent, sign-in, app lock).
  if (loc == '/privacy') return null;
  String? go(String to) => to == loc ? null : to;

  if (consentNeeded) return go('/consent');
  if (!loggedIn) return go('/setup');
  if (lockRequired) return go('/lock');
  if (loc == '/consent' || loc == '/setup' || loc == '/lock') return '/';
  if (!tourDone) return go('/welcome');
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Don't `watch` credentialsProvider here — that would rebuild the whole
  // GoRouter on every auth change and reset the navigation stack. Instead,
  // read fresh inside redirect and use refreshListenable for re-evaluation.
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth = ref.read(credentialsProvider);
      final consent = ref.read(crashConsentProvider);
      final settings = ref.read(appSettingsProvider);
      final ui = ref.read(uiPrefsProvider);
      if (auth.isLoading ||
          consent.isLoading ||
          settings.isLoading ||
          ui.isLoading) {
        return null;
      }
      return appRedirect(
        loc: state.matchedLocation,
        loggedIn: auth.value != null,
        consentNeeded:
            sentryConfigured && consent.value == CrashConsent.unset,
        lockRequired: ref.read(lockRequiredProvider),
        tourDone: ui.value?.tourDone ?? true,
      );
    },
    refreshListenable: _AuthListenable(ref),
    routes: [
      GoRoute(
          path: '/consent', builder: (_, __) => const CrashConsentScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
      GoRoute(path: '/lock', builder: (_, __) => const LockScreen()),
      GoRoute(
          path: '/welcome', builder: (_, __) => const WelcomeTourScreen()),
      GoRoute(
          path: '/privacy',
          builder: (_, __) => const PrivacyPolicyScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: '/tickets',
            builder: (_, __) => const TicketsScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, s) => CreateTicketScreen(
                  initialClientId:
                      int.tryParse(s.uri.queryParameters['client_id'] ?? ''),
                ),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    TicketDetailScreen(id: int.parse(s.pathParameters['id']!)),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (_, s) => EditTicketScreen(
                    ticketId: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/assets',
            builder: (_, s) => AssetsScreen(clientId: _clientParam(s)),
            routes: [
              GoRoute(
                  path: 'new',
                  builder: (_, s) =>
                      AssetFormScreen(initialClientId: _clientParam(s))),
              GoRoute(
                  path: 'scan',
                  builder: (_, __) => const AssetScanScreen()),
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    AssetDetailScreen(id: int.parse(s.pathParameters['id']!)),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (_, s) => AssetFormScreen(
                  assetId: int.parse(s.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/credentials',
            builder: (_, s) => CredentialsScreen(clientId: _clientParam(s)),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, s) =>
                    CredentialFormScreen(initialClientId: _clientParam(s)),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => CredentialDetailScreen(
                  id: int.parse(s.pathParameters['id']!),
                ),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (_, s) => CredentialFormScreen(
                  credentialId: int.parse(s.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
          GoRoute(
            path: '/banners',
            builder: (_, s) => BannersScreen(
              clientId: int.tryParse(s.uri.queryParameters['client_id'] ?? ''),
              clientName: s.uri.queryParameters['client_name'],
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, s) => BannerFormScreen(
                  clientId:
                      int.tryParse(s.uri.queryParameters['client_id'] ?? ''),
                ),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => BannerFormScreen(
                  id: int.parse(s.pathParameters['id']!),
                  clientId:
                      int.tryParse(s.uri.queryParameters['client_id'] ?? ''),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/clients',
            builder: (_, __) => const ClientsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    ClientDetailScreen(id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/contacts',
            builder: (_, __) => const ContactsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    ContactDetailScreen(id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/documents',
            builder: (_, __) => const DocumentsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => DocumentDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/domains',
            builder: (_, __) => const DomainsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => DomainDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/quick-pay',
            builder: (_, s) => QuickPayScreen(
              clientId: int.parse(s.uri.queryParameters['client']!),
              ticketId: int.tryParse(s.uri.queryParameters['ticket'] ?? ''),
              defaultLineName: s.uri.queryParameters['line'],
            ),
          ),
          GoRoute(
            path: '/invoices',
            builder: (_, __) => const InvoicesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => InvoiceDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
              GoRoute(
                path: ':id/pay',
                builder: (_, s) => PaymentFormScreen(
                    invoiceId: int.parse(s.pathParameters['id']!),
                    initialMethod: s.uri.queryParameters['method'],
                    quick: s.uri.queryParameters['quick'] == '1'),
              ),
              GoRoute(
                path: ':id/qr',
                builder: (_, s) => PayQrScreen(
                    invoiceId: int.parse(s.pathParameters['id']!),
                    quick: s.uri.queryParameters['quick'] == '1'),
              ),
            ],
          ),
          GoRoute(
            path: '/locations',
            builder: (_, __) => const LocationsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => LocationDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/networks',
            builder: (_, __) => const NetworksScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => NetworkDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/software',
            builder: (_, __) => const SoftwareScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => SoftwareDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/vendors',
            builder: (_, __) => const VendorsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => VendorDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/products',
            builder: (_, __) => const ProductsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => ProductDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/quotes',
            builder: (_, __) => const QuotesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => QuoteDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/expenses',
            builder: (_, __) => const ExpensesScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const ExpenseFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => ExpenseDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/certificates',
            builder: (_, __) => const CertificatesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => CertificateDetailScreen(
                    id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: '/timer', builder: (_, __) => const TimerScreen()),
          GoRoute(
            path: '/trips',
            builder: (_, __) => const TripsScreen(),
            routes: [
              GoRoute(
                path: 'start',
                builder: (_, __) => const StartTripScreen(),
              ),
              GoRoute(
                path: 'active',
                builder: (_, __) => const ActiveTripScreen(),
              ),
              GoRoute(
                path: 'new',
                builder: (_, s) =>
                    NewTripScreen(draft: s.extra as TripDraft?),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'navigation',
                builder: (_, __) => const NavigationSettingsScreen(),
              ),
              GoRoute(
                path: 'setup-code',
                builder: (_, __) => const SetupCodeScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(credentialsProvider, (_, __) => notifyListeners());
    ref.listen(crashConsentProvider, (_, __) => notifyListeners());
    ref.listen(appSettingsProvider, (_, __) => notifyListeners());
    ref.listen(appLockProvider, (_, __) => notifyListeners());
    ref.listen(uiPrefsProvider, (_, __) => notifyListeners());
  }
}

/// `?client=ID` narrows a list, or a new record, to one client.
int? _clientParam(GoRouterState s) =>
    int.tryParse(s.uri.queryParameters['client'] ?? '');
