# Changelog

## 1.1.0 - 2026-05-16

- New Trips section under More, with a quick start/stop button in the home AppBar so you can begin a trip without changing tabs.
- GPS mode captures your starting fix when you tap Start, then on Stop captures the end fix, reverse-geocodes both addresses, and calculates miles via Google Distance Matrix (straight-line fallback if Google can't be reached). A review form opens pre-filled, so all you add is the purpose, driver and client before saving.
- Manual mode for trips without GPS. Pick it on first use or in Settings, Trips. The app just times the trip, you enter source, destination and miles by hand when you stop.
- Persistent system notification while a trip is being tracked, so you don't forget to stop it.
- Active trip state survives the app being killed: you can stop a trip the next day from where it left off.
- Trips submit through the existing agent web flow (ITFlow's v1 API has no trips endpoint), so the agent email and password in Settings are required to log them.

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
