# On-site Payments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cash tender, pay-by-phone QR, and quick payment (from a client or a ticket) against upstream ITFlow.

**Architecture:** All app-side. New web-client calls drive ITFlow's own agent forms (`add_invoice`, `billing_item_save`, `add_ticket_to_invoice`, `mark_invoice_sent`). A repository chains them; screens hand off to the existing Make Payment form or a new QR screen.

**Tech Stack:** Flutter, Riverpod, go_router, dio, html parser, qr_flutter, wakelock_plus (new).

**Spec:** `docs/superpowers/specs/2026-11-21-onsite-payments-design.md`

## Global Constraints

- Upstream ITFlow only, no fork changes.
- Placeholder scope: `On-site payment, details to follow`. Line name default: `On-site service`. Ticket line: `<displayNumber>: <subject>`.
- Mark-sent method: `Hand Delivered`.
- Cash reference: `Cash, tendered <X>, change <Y>` (2dp), only when reference empty.
- Commits: no co-author, no Claude mention. Messages shown to the user first.

## Review Focus

- Tendered typed with commas or blank: change hidden, no crash; blank tendered does not block save.
- Amount edited after tendered: change recomputes.
- Ticket without a client: no quick-pay action shown.
- Server refuses a step mid-chain: error names the step, invoice id kept so the user can open it.
- Instance without a payment provider: QR still shows (guest page just has no Pay button); screen says so in a hint line.

---

### Task 1: Cash tender maths

**Files:** Create `lib/features/invoices/cash_tender.dart`; Test `test/cash_tender_test.dart`

**Interfaces:** Produces `double? cashChange(double amount, String tendered)` (null when tendered blank/unparsable) and `String cashReference(double tendered, double change)`.

- [ ] Tests: `cashChange(42.5, '50')` == 7.5; `cashChange(42.5, '')` null; `cashChange(42.5, '40')` == -2.5; `cashChange(10, '1,000')` == 990; `cashReference(50, 7.5)` == `Cash, tendered 50.00, change 7.50`.
- [ ] Implement, run `flutter test test/cash_tender_test.dart`, pass.

### Task 2: Cash tender in Make Payment

**Files:** Modify `lib/features/invoices/payment_form_screen.dart`, `lib/core/router.dart` (`/invoices/:id/pay?method=Cash`).

- [ ] `PaymentFormScreen({required int invoiceId, String? initialMethod})`; initial method used when it is in the list (case-insensitive).
- [ ] When method text is `Cash` (case-insensitive): "Amount tendered" field + "Change due" line; negative change blocks submit with toast `Tendered is less than the amount`; empty reference filled with `cashReference`.
- [ ] "Show QR" outlined button under Pay pushes `/invoices/:id/qr`.
- [ ] Widget test in `test/cash_tender_test.dart` is not needed beyond Task 1 maths; `flutter analyze` clean.

### Task 3: Pay QR screen

**Files:** Create `lib/features/invoices/pay_qr_screen.dart`; modify router (`/invoices/:id/qr`), `readonly_screens.dart` Guest View card (add "Show QR"), `pubspec.yaml` (`wakelock_plus`).

**Interfaces:** Consumes invoice API row (`invoice_url_key`, `invoice_prefix`, `invoice_number`, `invoice_status`) and `paymentAddFormProvider` for balance (error = nothing owed -> show status instead).

- [ ] Full-screen white QR of `<root>/guest/guest_view_invoice.php?invoice_id=<id>&url_key=<key>`, balance large, hint `Customer scans to pay by card. No Pay button means no card provider is set up in ITFlow.`, wakelock on while mounted, Done reloads invoice + list then pops.

### Task 4: Web client quick-invoice calls

**Files:** Modify `lib/core/api/itflow_web_client.dart`; Test `test/parsers_test.dart`.

**Interfaces:** Produces
- `static Map<String,String> formDefaults(String html)` (inputs incl. hidden, checked checkboxes/radios, selected or first option of selects, textareas; skips submit buttons).
- `static int? invoiceIdFromLocation(String? loc)`.
- `Future<int> createInvoice({required int clientId, required String scope, required String date})`.
- `Future<void> addInvoiceLine({required int invoiceId, required String name, String description = '', required double price})`.
- `Future<void> linkTicketToInvoice({required int invoiceId, required int ticketId})`.
- `Future<void> markInvoiceSent(int invoiceId)`.
- `_postAgent` returns `Response`.

- [ ] Parser tests: formDefaults picks selected option, first option fallback, hidden csrf, textarea text; `invoiceIdFromLocation('invoice.php?invoice_id=42')` == 42, `'invoices.php'` null.
- [ ] Implement; live check added to `test/live/dev_server_test.dart`: quick-invoice chain on the seeded client + ticket, then API read shows status Sent, amount equals price, one line.

### Task 5: Quick payment repository + screen + entry points

**Files:** Create `lib/features/invoices/quick_pay.dart` (repository + `QuickPayScreen`); modify router (`/quick-pay?client=<id>&ticket=<id>`), `client_detail_screen.dart` (app bar action), `ticket_detail_screen.dart` (app bar action when `clientId != null`).

**Interfaces:** `QuickPayRepository.create({clientId, ticketId?, amount, lineName, note}) -> Future<int>`; throws `QuickPayException(step, invoiceId, message)`.

- [ ] Screen: amount, line name, note, buttons `Take cash` / `Card (QR)`; after create, `pushReplacement` to `/invoices/:id/pay?method=Cash` or `/invoices/:id/qr`; failure toast `Step failed: <step>. <message>` with Open invoice action when id known.

### Task 6: Verify + release

- [ ] `flutter analyze`, `flutter test`, `FERRULE_LIVE=1 flutter test test/live/dev_server_test.dart`.
- [ ] CHANGELOG + version bump, commit (message approved by user), `scripts/release-internal.ps1`.
