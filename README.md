# Ferrule

> *ferrule* (noun) - the metal sleeve crimped onto the end of a cable, pencil, or umbrella, used to bind the strands together and stop them fraying.

A cross-platform mobile and desktop client for [ITFlow](https://itflow.org), the open-source MSP/PSA platform. Ferrule is a thin cap over an ITFlow backend: it binds the loose ends (REST endpoints, agent CSRF flows, PDF exports, guest links) into one client surface without changing what's inside.

Built with Flutter. Targets Android, iOS, and Windows from a single Dart codebase.

[![Play Store - closed testing](https://img.shields.io/badge/Play%20Store-closed%20testing-3ddc84?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=au.com.bordertechsolutions.ferrule)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Flutter](https://img.shields.io/badge/flutter-stable-02569B?logo=flutter)](https://flutter.dev)

## What it does

| Area | Read | Create | Action |
|---|---|---|---|
| Clients, contacts, assets, credentials, tickets | yes | upstream-dependent | tap-through linking between every detail screen |
| Invoices | yes (incl. line items) | no | download PDF, copy or open the guest-view link, Make Payment form |
| Quotes | yes (incl. line items) | no | download PDF, copy or open the guest-view link |
| Expenses | yes | yes (camera or file receipt upload) | - |
| Products, vendors, locations, networks, certificates, software, documents, domains | yes | no | tap-through linking |
| Tickets | yes | no | timer, reply view |

Detail screens cross-link related records: tap a client on an invoice, a contact on an asset, a credential on a ticket, and so on. Linked IDs render as names, not numbers.

## Architecture

Ferrule talks to two surfaces of the same backend through one Dio client:

```
                +-----------------------------+
                |        Flutter app          |
                |  Riverpod 3 + GoRouter      |
                +--------------+--------------+
                               |
                       +-------+-------+
                       | Dio + cookies |
                       +---+-------+---+
                           |       |
            /api/v1/* JSON |       | /agent/* HTML + CSRF
                           v       v
                +--------------------------------+
                |         Your ITFlow            |
                |   (PHP 8, MySQL, self-hosted)  |
                +--------------------------------+
```

- **REST** (`/api/v1/*`): module reads. Clean, paginated, scoped to an API key's client.
- **Agent scrape** (`/agent/*`): everything the REST API doesn't cover. CSRF token harvested from the rendered modal, session retry on lapse, multipart POSTs for things like `add_expense`.

This split is why some features need to land on both repos at once: when REST doesn't expose what the app needs, the fork below ships the endpoint and Ferrule consumes it.

## Backend (PHP fork)

API additions for things the upstream ITFlow REST API doesn't yet expose live in [BoredManCodes/itflow](https://github.com/BoredManCodes/itflow):

- `GET /api/v1/quote_items/read.php` - line items for a quote, JOINed to `quotes` for client scope.
- `GET /api/v1/ticket_replies/read.php` and `POST /api/v1/ticket_replies/create.php` - read and create ticket conversation replies.

All additions are designed to be upstreamable and follow the existing `validate_api_key.php` + `LIKE '$client_id'` scoping conventions.

## Setup

The app reads build-time config (Sentry DSN, environment name) from a local `secrets.json`, which is **not** checked in.

```bash
cp secrets.example.json secrets.json   # fill in your Sentry DSN, or leave blank to disable
flutter pub get
flutter run --dart-define-from-file=secrets.json
```

To build a release Android App Bundle:

```bash
flutter build appbundle --dart-define-from-file=secrets.json
```

To build a release APK:

```bash
flutter build apk --dart-define-from-file=secrets.json
```

### First-run flow

1. Enter your ITFlow base URL and API key.
2. (Optional) Add agent email + password to unlock the scrape-only features (Make Payment, PDF downloads, expense create).
3. (Optional) Enable biometric unlock on launch (off by default).
4. Done. The app caches everything to secure storage; you won't be asked again.

### QR scanner

The lookup format expected is `assetid_customer_installdate`, e.g. `000037_bordertechsolutions_0126`. That's the label format my business prints, so it won't match generic QR codes out of the box.

## Releasing

Closed-testing releases ship through a self-contained PowerShell + Node pipeline in `scripts/`.

```pwsh
# Build the AAB, upload to Play Console alpha track as a draft.
.\scripts\release-internal.ps1 -Track alpha -NoPromote

# Save the draft and Send for review on Publishing overview (Playwright-driven Chromium).
node .\scripts\promote-closed-testing.mjs --track <track-id> --release-name 1.0.2 --version-code 6
```

The promote script handles the bit the Android Publisher API doesn't expose: clicking **Edit release -> Next -> Save** on the review page, then **Send for review** on Publishing overview. One command from `git push` to "in front of Google reviewers".

Internal-testing flow (`-Track internal`, no `-NoPromote`) uses `scripts/promote-via-browser.mjs` instead, which clicks **Save and publish** for an immediate roll-out.

## Stack

- **Frontend**: Flutter, Dart 3, [Riverpod 3](https://riverpod.dev), [GoRouter](https://pub.dev/packages/go_router)
- **HTTP**: [Dio](https://pub.dev/packages/dio) + `dio_cookie_manager`, [html](https://pub.dev/packages/html) for parsing scraped pages
- **Storage**: [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
- **Auth**: [local_auth](https://pub.dev/packages/local_auth) for biometrics
- **Telemetry**: [sentry_flutter](https://pub.dev/packages/sentry_flutter) (opt-in)
- **Camera & files**: [mobile_scanner](https://pub.dev/packages/mobile_scanner), [image_picker](https://pub.dev/packages/image_picker), [file_picker](https://pub.dev/packages/file_picker)
- **Sharing**: [share_plus](https://pub.dev/packages/share_plus), [path_provider](https://pub.dev/packages/path_provider)

## Privacy

All network traffic goes to **your** ITFlow instance and nowhere else, except optional Sentry crash reports if you've configured a DSN. The privacy policy is bundled as `PRIVACY.md` and renders in-app at *Settings -> Privacy policy* so it works offline.

## License

Licensed under [Apache 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.

This is an unofficial client and is **not affiliated with or endorsed by** the ITFlow project. ITFlow itself is an independent open-source project licensed under GPL-3.0; no ITFlow source code is included in or redistributed by this client.
