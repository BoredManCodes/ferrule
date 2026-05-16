# Privacy Policy — Ferrule

_Last updated: 2026-05-16_

Ferrule is an unofficial client for [ITFlow](https://itflow.org). It runs entirely on your own device and talks to the ITFlow instance you point it at. There is no Ferrule server, no Ferrule account, and no central database operated by the developer.

## What Ferrule stores on your device

All of the following are kept in your operating system's secure storage (Keychain on iOS/macOS, Keystore on Android, DPAPI on Windows). Nothing is uploaded anywhere by the app:

- **Instance URL** — the address of your ITFlow installation.
- **API key** — issued by you in the ITFlow admin UI.
- **Vault decrypt password** — used locally to read/write encrypted credential entries on your ITFlow instance (optional).
- **Agent email and password** — used to drive the ITFlow web UI for logging time against tickets, since the v1 API does not expose that endpoint (optional).
- **App preferences** — theme, accent colour, display name, biometric-unlock toggle, crash-report opt-in choice, trip-tracking mode. These live in regular app preferences, not in secure storage.
- **Active trip state** — while a GPS trip is being tracked, the start time, the starting GPS coordinates, and the reverse-geocoded starting address are saved to secure storage so the trip survives if you close the app. The state is cleared the moment you stop or discard the trip.

Removing the app, or tapping **Sign out** in Settings, deletes all of the above from your device.

## What Ferrule sends over the network

- **To your ITFlow instance** — every action you take in the app (viewing tickets, clients, assets, etc.) results in an HTTPS request to the instance URL you configured. The developer of Ferrule does not see this traffic.
- **To your ITFlow instance, as a logged-in session** — when you submit time from the Labour Timer, the app signs in as you using the stored agent credentials, fetches a CSRF token, and posts the time entry. This emulates what your browser would do on the ITFlow website.
- **To Google Maps Platform (maps.googleapis.com)** — only when you actively use GPS trip tracking. When you start a GPS trip and again when you stop it, the app sends your current latitude/longitude to Google's Geocoding API to turn coordinates into a human-readable address, and (on stop) sends the start and end coordinates to Google's Distance Matrix API to calculate driving distance. These requests are made on your behalf using a Google Maps API key embedded in the app. Manual-mode trips do not contact Google. The app does not stream a continuous location feed; only the two points captured at start and stop are sent.
- **To Stripe** — only if you tap the optional "Support development" button, which opens Stripe's hosted donation page in your browser. Ferrule itself does not see any payment information.
- **To Sentry (sentry.io)** — only if you opt in to **Send crash reports** in Settings. Reports include stack traces, OS version, and app version. The Sentry SDK is configured with `sendDefaultPii = false`, meaning the SDK will not attach IP addresses, usernames, or other personal identifiers it would otherwise capture by default. Ferrule does not deliberately add personal information, ITFlow data, API keys, or credentials to crash reports. Crash reporting is **off by default** and can be toggled at any time in Settings → Privacy.

That is the complete list. Ferrule does not contact any other servers, does not include analytics or advertising SDKs, and does not phone home for licensing, telemetry, or "is the user still active" pings.

## Biometric / device unlock

If you enable **Require unlock on launch**, the app asks your operating system to verify a biometric or device PIN. The result is a yes/no — no biometric data is ever read, transmitted, or stored by Ferrule.

## Camera (QR scanner)

The QR scanner uses the device camera to decode asset labels. Frames are processed on-device and discarded. Nothing from the camera leaves your device.

## Location (GPS trip tracking)

Location is read only when you actively start a GPS trip. The app takes one high-accuracy fix at the moment you tap **Start**, and another at the moment you tap **Stop**. No background tracking, no continuous polling, no route polyline is collected. While a trip is in progress the persistent notification on your device is the only signal the app uses. As described above, the two captured points are sent to Google's Geocoding and Distance Matrix APIs to turn them into addresses and a mileage figure, and the resulting trip (date, source address, destination address, miles, purpose, driver, client) is submitted to your own ITFlow instance when you confirm it. You can avoid contacting Google entirely by choosing **Manual** mode in Settings → Trips; manual trips never read your location.

## Children

Ferrule is a B2B tool for IT service providers. It is not directed at children and we do not knowingly collect data from children.

## Changes to this policy

If this policy changes materially, the change will be visible in the app's commit history and in a new "Last updated" date above. There is no in-app notification, because there is no Ferrule server with which to send one.

## Contact

Source, issues, and contact: https://github.com/BoredManCodes/ferrule
