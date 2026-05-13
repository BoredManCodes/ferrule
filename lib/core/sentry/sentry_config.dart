const sentryDsn = String.fromEnvironment('SENTRY_DSN');
const sentryEnv = String.fromEnvironment(
  'SENTRY_ENV',
  defaultValue: 'production',
);

bool get sentryConfigured => sentryDsn.isNotEmpty;
