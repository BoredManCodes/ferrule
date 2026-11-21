# On-site payments

## Intent

A tech on site needs to take money there and then: cash, or a card on the
customer's own phone. Invoice paperwork can be tidied up back in the office.
Must work against upstream ITFlow (itflow-org/itflow master), no fork changes.

## Approaches

- **Placeholder invoice + existing payment flows (picked).** App creates a
  normal invoice for the amount, marks it sent, then records cash or shows a
  QR to the guest pay page. Money lands in an account straight away.
- Client credit: cash only, never books into an account, and upstream's
  `apply_credit` is disabled ("Not ready for use 2025-08-27"). Rejected.
- Tap to Pay / in-app card charging: needs a server endpoint holding the
  provider secret key that ITFlow doesn't have. Out of scope.

## Upstream constraints

- Guest pay page only offers Pay on Sent / Viewed / Partial invoices
  (`invoiceOpenStatuses()`), so a draft must be marked sent first.
- Lines lock once an invoice is Paid (`billingCanEditItems()`). Scope, date,
  due date, category and discount stay editable (`edit_invoice`). So the line
  name is typed on site, quick and rough; the office fixes scope/notes/date.
  If a line truly needs rewriting: edit the payment to 0, fix the line, edit
  the payment back. Manual, not built.
- `edit_payment` cannot move a payment to another invoice. Deleting a Stripe
  payment refunds it.

## Design

1. **Cash tender** (Make Payment screen). When method is Cash, an "Amount
   tendered" field shows "Change due". Tendered below amount blocks save.
   Payment records the amount, not the tendered sum. Empty reference
   auto-fills "Cash, tendered $X, change $Y".
2. **Pay by phone QR.** "Show QR" on the invoice Guest View card and on Make
   Payment: full-screen QR of the guest invoice link, balance in big text,
   screen kept awake. Done reloads the invoice so paid status shows. No
   polling. Guest page picks Stripe or Square itself.
3. **Quick payment** (client screen action). Fields: amount, line name
   (prefilled "On-site service"), optional note. App then:
   `add_invoice` (scope "On-site payment, details to follow", today's date)
   -> `billing_item_save` (qty 1, price = amount, no tax) -> `mark_invoice_sent`
   ("Hand Delivered") -> opens Make Payment (cash) or the QR screen (card).
   A failure mid-way leaves the invoice in place and says which step failed.
4. **Quick payment on tickets.** Same action on the ticket screen (tickets
   with a client only). Line name prefills "<ticket prefix+number>: <subject>".
   After `add_invoice` the app posts `add_ticket_to_invoice` with the ticket id
   and no `bill_time`, which links the ticket to the invoice without adding
   time lines (upstream: "added to the invoice, without lines"), so the ticket
   shows as billed and the amount stays what the tech typed.

## Left to the builder

Form scraping details per handler, matching the existing
`itflow_web_client.dart` patterns; tax handling defaults to none.

## After

Release via `scripts/release-internal.ps1` (closed testing). Commit messages
carry no co-author or Claude mention.
