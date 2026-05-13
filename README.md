# itflow_app

Unofficial mobile/desktop client for [ITFlow](https://itflow.org), the open-source PSA/RMM platform. Built with Flutter.

## Features

- Dashboard, tickets, clients, contacts, assets, and credentials
- Built-in ticket timer
- QR scanner for quick asset lookup (expects the format `assetid_customer_installdate`, e.g. `000037_bordertechsolutions_0126` — that's the label format my business prints, so it won't match generic QR codes out of the box)
- Biometric-protected secure storage for session credentials
- Android, iOS, Windows, and desktop targets

## Setup

The app reads build-time config (Sentry DSN, environment name) from a local `secrets.json`, which is **not** checked in.

```bash
cp secrets.example.json secrets.json   # then fill in your Sentry DSN (or leave blank to disable)
flutter pub get
flutter run --dart-define-from-file=secrets.json
```

To build a release APK:

```bash
flutter build apk --dart-define-from-file=secrets.json
```

## Stack

Riverpod · go_router · Dio (+ cookie jar) · flutter_secure_storage · Sentry · mobile_scanner

## License

Licensed under [Apache 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.

This is an unofficial client and is **not affiliated with or endorsed by** the ITFlow project. ITFlow itself is an independent open-source project licensed under GPL-3.0; no ITFlow source code is included in or redistributed by this client.
