# Changelog

## 1.2.0 - 2026-11-18

- New sign-in screen that asks which kind of account you have and explains each way in: ITFlow admins sign in with email and password, technicians use a setup code, and anyone can still paste an API key.
- Setup codes for technicians who aren't ITFlow admins. An admin opens Settings, Set up a technician, picks the technician and gets a QR code holding a key that acts as them. The technician scans it, picks it from a screenshot, or pastes the text the admin sent. Nothing to change on the ITFlow server. The key lasts a year and the app warns a month before it runs out.
- A short welcome tour after signing in, and one-time tips on Home, Tickets, a ticket, the timer, Trips and More. Settings, Help replays the tour and brings the tips back.
- Choose what's on the bottom bar: More, Customize (or Settings, Navigation) moves any section onto the bar or off it and reorders both lists, so Contacts can sit where Assets was.
- Sign in with your ITFlow email and password. The app creates its own API key acting as you, renews it before it expires, and revokes the old one. Settings shows when it renews and has Rotate now. Pasting an existing key still works under Advanced.
- Agent banners from ITFlow show on the home screen, client pages and tickets, the same ones the web UI shows. Notices and Heads ups can be hidden; Urgent ones can't. Agents who can edit a client can add, change, archive and delete its banners, and admins get Agent Banners under More for every client's.
- Internal notes now stay internal. On current ITFlow the old internal code meant "public and send a text", so notes logged from the app went out as public replies.
- Reply statuses come from your instance instead of a fixed list that called On Hold "In Progress" and Resolved "Closed". A New ticket starts on Open.
- Replies load over the API, so the conversation shows without agent credentials. Internal notes and emailed public replies also post over the API; a public note without email still needs agent credentials.
- Ticket edits save over the API and keep the ticket's other assets and tags. New tickets take a client and contact. Resolving and deleting assets work with keys that reach every client.
- The ticket page shows the agent's name, the booked time with its end and Onsite, and the due date separately.
- Works with ITFlow's new look: trips, expenses, payments, replies, statuses and the instance colour are read from the redesigned pages, and the API key is sent in the X-API-Key header instead of the address.
- When ITFlow turns something away (a missing vendor, an invoice with nothing owed, AI reword not set up) the app now shows ITFlow's own message instead of reporting success.

## 1.1.2 - 2026-05-16

- Trent Buckley in the About dialog is now a tappable link to his site.
- Fixed instance name not appearing in the home title bar after a fresh sign-in when only the API key (no agent web credentials) was entered. The company name now refreshes off the public login page so it loads without web creds.

## 1.1.1 - 2026-05-16

- Trips screen now lists your past trips below the active trip card. Pulls the all-time list from the ITFlow web UI (no v1 API for trips). Pull-to-refresh and newly logged trips appear automatically.

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
