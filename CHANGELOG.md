# Changelog

## 1.0.4 - 2026-05-16

- Clarify on the connect screen that the vault decrypt password is shown by ITFlow when the API key is created, not something the user chooses.
- After a failed connection attempt, show a checklist (Save Changes in ITFlow, correct URL, trimmed key, reachable from the device).
- New Settings → Support → Get help. Routes app issues to support@bordertechsolutions.com.au and server/ITFlow issues to the ITFlow project, with a quick "open it in a browser to see which" tip.

## 1.0.3 - 2026-05-16

- Reply to tickets directly from the ticket detail screen. Internal notes and Public (no email) replies work over the REST API without needing agent credentials; Public + email still requires agent email/password in Settings.
- Reworked the reply sheet so it opens focused on the reply text with time-worked tucked into an optional section.

## 1.0.2 - 2026-05-15

- Show linked client, vendor, contact, location and domain names (not raw IDs) on expense, invoice, quote, document, software, vendor, network, location and certificate detail screens. Tap a linked row to open it.

## 1.0.1 - 2026-05-15

- Add Expense entry with receipt upload (image or PDF) from camera or files.

## 1.0.0 - 2026-05-15

- Initial Play Store release.
- Dashboard, tickets, clients, contacts, assets, and credentials.
- Built-in ticket timer.
- QR scanner for quick asset lookup.
- Biometric-protected secure storage for session credentials.
- Optional biometric unlock on launch.
