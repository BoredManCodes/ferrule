import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/assets/asset_form_screen.dart';
import '../features/assets/asset_detail_screen.dart';
import '../features/assets/asset_scan_screen.dart';
import '../features/assets/assets_screen.dart';
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
import '../features/invoices/payment_form_screen.dart';
import '../features/lock/lock_screen.dart';
import '../features/more/more_screen.dart';
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
import 'api/providers.dart';
import 'auth/app_lock.dart';
import 'sentry/sentry_config.dart';
import 'settings/app_settings.dart';
import 'settings/crash_consent.dart';

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
      if (auth.isLoading || consent.isLoading || settings.isLoading) {
        return null;
      }
      final loggedIn = auth.value != null;
      final consentNeeded =
          sentryConfigured && consent.value == CrashConsent.unset;
      final lockRequired = ref.read(lockRequiredProvider);
      final loc = state.matchedLocation;
      final atConsent = loc == '/consent';
      final atSetup = loc == '/setup';
      final atLock = loc == '/lock';
      final atPrivacy = loc == '/privacy';
      // Privacy policy is always reachable — it has to be readable before
      // the user agrees to anything (consent, sign-in, app lock).
      if (atPrivacy) return null;
      if (consentNeeded && !atConsent) return '/consent';
      if (!consentNeeded && atConsent) return loggedIn ? '/' : '/setup';
      if (!loggedIn && !atSetup && !atConsent) return '/setup';
      if (!loggedIn && atLock) return '/setup';
      if (loggedIn && atSetup) return lockRequired ? '/lock' : '/';
      if (lockRequired && !atLock) return '/lock';
      if (!lockRequired && atLock) return '/';
      return null;
    },
    refreshListenable: _AuthListenable(ref),
    routes: [
      GoRoute(
          path: '/consent', builder: (_, __) => const CrashConsentScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
      GoRoute(path: '/lock', builder: (_, __) => const LockScreen()),
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
                builder: (_, __) => const CreateTicketScreen(),
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
            builder: (_, __) => const AssetsScreen(),
            routes: [
              GoRoute(
                  path: 'new', builder: (_, __) => const AssetFormScreen()),
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
            builder: (_, __) => const CredentialsScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const CredentialFormScreen(),
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
                    invoiceId: int.parse(s.pathParameters['id']!)),
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
              path: '/settings', builder: (_, __) => const SettingsScreen()),
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
  }
}
