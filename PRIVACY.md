# Privacy Policy — Ferrule

_Last updated: 2026-05-15_

Ferrule is an unofficial client for [ITFlow](https://itflow.org). It runs entirely on your own device and talks to the ITFlow instance you point it at. There is no Ferrule server, no Ferrule account, and no central database operated by the developer.

## What Ferrule stores on your device

All of the following are kept in your operating system's secure storage (Keychain on iOS/macOS, Keystore on Android, DPAPI on Windows). Nothing is uploaded anywhere by the app:

- **Instance URL** — the address of your ITFlow installation.
- **API key** — issued by you in the ITFlow admin UI.
- **Vault decrypt password** — used locally to read/write encrypted credential entries on your ITFlow instance (optional).
- **Agent email and password** — used to drive the ITFlow web UI for logging time against tickets, since the v1 API does not expose that endpoint (optional).
- **App preferences** — theme, accent colour, display name, biometric-unlock toggle, crash-report opt-in choice. These live in regular app preferences, not in secure storage.

Removing the app, or tapping **Sign out** in Settings, deletes all of the above from your device.

## What Ferrule sends over the network

- **To your ITFlow instance** — every action you take in the app (viewing tickets, clients, assets, etc.) results in an HTTPS request to the instance URL you configured. The developer of Ferrule does not see this traffic.
- **To your ITFlow instance, as a logged-in session** — when you submit time from the Labour Timer, the app signs in as you using the stored agent credentials, fetches a CSRF token, and posts the time entry. This emulates what your browser would do on the ITFlow website.
- **To Stripe** — only if you tap the optional "Support development" button, which opens Stripe's hosted donation page in your browser. Ferrule itself does not see any payment information.
- **To Sentry (sentry.io)** — only if you opt in to **Send crash reports** in Settings. Reports include stack traces, OS version, and app version. The Sentry SDK is configured with `sendDefaultPii = false`, meaning the SDK will not attach IP addresses, usernames, or other personal identifiers it would otherwise capture by default. Ferrule does not deliberately add personal information, ITFlow data, API keys, or credentials to crash reports. Crash reporting is **off by default** and can be toggled at any time in Settings → Privacy.

That is the complete list. Ferrule does not contact any other servers, does not include analytics or advertising SDKs, and does not phone home for licensing, telemetry, or "is the user still active" pings.

## Biometric / device unlock

If you enable **Require unlock on launch**, the app asks your operating system to verify a biometric or device PIN. The result is a yes/no — no biometric data is ever read, transmitted, or stored by Ferrule.

## Camera (QR scanner)

The QR scanner uses the device camera to decode asset labels. Frames are processed on-device and discarded. Nothing from the camera leaves your device.

## Children

Ferrule is a B2B tool for IT service providers. It is not directed at children and we do not knowingly collect data from children.

## Changes to this policy

If this policy changes materially, the change will be visible in the app's commit history and in a new "Last updated" date above. There is no in-app notification, because there is no Ferrule server with which to send one.

## Contact

Source, issues, and contact: https://github.com/BoredManCodes/ferrule
