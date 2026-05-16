<div align="center">

```
███████╗███████╗██████╗ ██████╗ ██╗   ██╗██╗     ███████╗
██╔════╝██╔════╝██╔══██╗██╔══██╗██║   ██║██║     ██╔════╝
█████╗  █████╗  ██████╔╝██████╔╝██║   ██║██║     █████╗
██╔══╝  ██╔══╝  ██╔══██╗██╔══██╗██║   ██║██║     ██╔══╝
██║     ███████╗██║  ██║██║  ██║╚██████╔╝███████╗███████╗
╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝
       a thin metal cap for your ITFlow backend
```

[![Play Store · closed testing](https://img.shields.io/badge/Play%20Store-closed%20testing-3ddc84?logo=googleplay&logoColor=white)](https://play.google.com/store/apps/details?id=au.com.bordertechsolutions.ferrule)
[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Riverpod](https://img.shields.io/badge/Riverpod-3.x-0553B1)](https://riverpod.dev)
[![Dart](https://img.shields.io/badge/Dart-3-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/BoredManCodes/ferrule/pulls)

</div>

```
$ man ferrule
NAME
       ferrule - mobile/desktop client for an ITFlow MSP backend

DESCRIPTION
       A ferrule is the metal sleeve crimped onto the end of a
       cable, pencil, or umbrella to keep the strands bound and
       stop them fraying.

       This Ferrule does the same job for an ITFlow instance: it
       binds the loose ends (REST endpoints, agent CSRF flows,
       PDF exports, guest links) into one client surface without
       changing what's inside.

SEE ALSO
       itflow(1), flutter(1), make-coffee-first(1)
```

## `$ ferrule --what-does-it-do`

```
$ ls /modules
clients/    contacts/   assets/        credentials/  tickets/
invoices/   quotes/     expenses/      products/     vendors/
locations/  networks/   certificates/  software/     documents/
domains/    dashboard/  timer/

$ stat invoices/
  Read       full list + detail + line items
  PDF        download via the OS share sheet
  Guest      copy or open the shareable client URL
  Action     Make Payment form (scrapes the agent modal for CSRF)

$ stat quotes/
  Read       full list + detail + line items
  PDF        download via the OS share sheet
  Guest      copy or open the shareable client URL

$ stat expenses/
  Read       full list + detail
  Create     receipt upload (camera or file: jpg/png/gif/webp/pdf)

$ stat everything-else/
  Read       list + detail screens with linked-record tap-through
             (clients <-> contacts <-> assets <-> credentials <-> tickets ...)
```

Tap a client on an invoice, a contact on an asset, a credential on a ticket - linked IDs render as names and behave like hyperlinks, not magic numbers.

## `$ ferrule --how-does-it-work`

Two surfaces of the same backend, one Dio client:

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

- **REST** (`/api/v1/*`): clean, paginated, scoped to an API key's client. Used wherever an endpoint exists.
- **Agent scrape** (`/agent/*`): everything REST doesn't cover. CSRF harvested from the rendered modal, session retry on lapse, multipart POSTs for things like `add_expense`.

When REST doesn't expose what the app needs, the fork below ships the endpoint and Ferrule eats it for breakfast.

## `$ ferrule --backend`

API additions live in [BoredManCodes/itflow](https://github.com/BoredManCodes/itflow):

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/quote_items/read.php` | Line items for a quote, JOINed to `quotes` for client scope |
| `GET /api/v1/ticket_replies/read.php` | Conversation replies for a ticket |
| `POST /api/v1/ticket_replies/create.php` | Post a new reply to a ticket |

All additions follow the existing `validate_api_key.php` + `LIKE '$client_id'` scoping pattern and are designed to be upstreamable.

## `$ ferrule --install`

```pwsh
# 1. clone
git clone https://github.com/BoredManCodes/ferrule.git
cd ferrule

# 2. config (leave Sentry blank to disable)
cp secrets.example.json secrets.json

# 3. run
flutter pub get
flutter run --dart-define-from-file=secrets.json
```

Release builds:

```pwsh
flutter build appbundle --dart-define-from-file=secrets.json   # Play / closed testing
flutter build apk       --dart-define-from-file=secrets.json   # sideload
flutter build windows   --dart-define-from-file=secrets.json   # desktop
```

### First-run flow

1. Enter your ITFlow base URL and API key.
2. *(Optional)* Add agent email + password to unlock scrape-only features (Make Payment, PDF downloads, expense create).
3. *(Optional)* Turn on biometric unlock at launch. Off by default.
4. Done. Everything caches to secure storage; you won't be asked again.

### QR scanner

Asset lookup expects `assetid_customer_installdate`, e.g. `000037_bordertechsolutions_0126`. That's the label format my business prints, so generic QR codes won't match out of the box.

## `$ ferrule --release`

Closed-testing ships through a self-contained PowerShell + Node pipeline in `scripts/`:

```pwsh
# 1. build + upload to Play alpha as a draft
.\scripts\release-internal.ps1 -Track alpha -NoPromote

# 2. Save + Send for review (Playwright drives Chromium)
node .\scripts\promote-closed-testing.mjs `
  --track <track-id> `
  --release-name 1.0.2 `
  --version-code 6
```

The promote script handles the part the Android Publisher API doesn't expose: **Edit release -> Next -> Save** on the review page, then **Send for review** on Publishing overview. One command from `git push` to "queued for Google review". Took an afternoon to write, saves twenty minutes per release.

Internal testing? Same `release-internal.ps1` without `-NoPromote`. `scripts/promote-via-browser.mjs` clicks **Save and publish** for an immediate roll-out.

## `$ ferrule --stack`

| Layer | Bits |
|---|---|
| Framework | Flutter, Dart 3 |
| State | [Riverpod 3](https://riverpod.dev) (async caching, autoDispose families) |
| Routing | [GoRouter](https://pub.dev/packages/go_router) (typed deep links) |
| HTTP | [Dio](https://pub.dev/packages/dio) + `dio_cookie_manager`, [html](https://pub.dev/packages/html) parser |
| Storage | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) (keychain / Keystore) |
| Auth | [local_auth](https://pub.dev/packages/local_auth) for biometrics |
| Telemetry | [sentry_flutter](https://pub.dev/packages/sentry_flutter), opt-in |
| Capture | [mobile_scanner](https://pub.dev/packages/mobile_scanner), [image_picker](https://pub.dev/packages/image_picker), [file_picker](https://pub.dev/packages/file_picker) |
| Share | [share_plus](https://pub.dev/packages/share_plus), [path_provider](https://pub.dev/packages/path_provider) |

## `$ ferrule --privacy`

```
$ traceroute your.data
 1  your.itflow.instance  (the only hop)
 2  *  *  *
 3  *  *  *
```

All network traffic goes to **your** ITFlow instance and nowhere else, except optional Sentry crash reports if you've configured a DSN. The privacy policy is bundled as `PRIVACY.md` and renders in-app at *Settings -> Privacy policy* so it works offline and survives a GitHub outage.

## `$ ferrule --easter-eggs`

```
$ history | grep -i easter
```

There's at least one. The other one is reading the source. Pull requests welcome.

## `$ ferrule --license`

Apache 2.0 - see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Unofficial client. **Not affiliated with or endorsed by** the ITFlow project. ITFlow itself is an independent open-source project licensed under GPL-3.0; no ITFlow source code is included in or redistributed by this client.

---

<div align="center">

```
guest@ferrule:~$ exit
Connection to ferrule closed. Have a good one.
```

</div>
