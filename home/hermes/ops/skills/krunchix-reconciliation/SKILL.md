---
name: krunchix-reconciliation
description: How Krunchix reconciles its money pots (Equity, Stanbic, MTN MoMo, Airtel, VISA, till, petty cash) and closes a month. Read this before touching a bank statement, a wallet balance or a month-end question.
version: 1.0.0
metadata:
  hermes:
    tags: [krunchix, odoo, reconciliation, bank, momo, month-end]
    category: operations
---

# Krunchix reconciliation playbook

Distilled from the July and August 2026 closes done by hand with the captain.
Everything here is precedent the captain has already approved. When a case is
not covered, ask; never guess a booking.

## 1. The money map

| Pot | Journal | Account | Statement source | What the captain calls it |
|---|---|---|---|---|
| Stanbic Bank | Stanbic Bank (was "Bank") | 352801 | API, auto-fetched, lines to today | "the bank" |
| Equity Bank | EQTY | 352815 | portal PDF the captain posts, monthly | "equity" |
| MTN MoMo merchant wallet | MOMO | 101510 | portal CSV, monthly; live balance in the receipt SMS | "momo", "mtn" |
| Airtel Pay wallet | AIRT | 101520 | portal export, 15 days max; closing balance from the SMS | "airtel" |
| Card Settlement (VISA machine, Equity) | VISA | 101530 | no statement; clears via EQSET credits on Equity | "visa", "card" |
| Cash Restaurant (the POS till) | CSH1 | 352813 | POS sessions; banked by Fahil into Stanbic | "till", "cash" |
| Petty Cash (the box) | | 352814 | n/a, topped up from till or bank | "petty cash" |

Odoo 19 on the cluster since 1 July 2026. Everything before is the Odoo 17
till (database `odoo17` in `pg-apps`), which recorded sales only; its debts
were cleared through `519000 Opening Balance Clearing`, never through P&L.

How money moves:

- **In.** Every POS tender posts to its own journal at session close. Card
  sales land later as lump `EQSET` credits on Equity (about 2.9% commission).
  MoMo and Airtel receipts carry the transaction id in
  `pos_payment.krunchix_transaction_ref`, so they match one to one.
- **Salaries** run as Dr Salaries / Cr Salaries Payable, then settle as
  individual MoMo transfers on payday (around the 28th) against Salaries
  Payable. Pay is PAYE-exclusive: PAYE is a company cost (`620200 PAYE`), not
  a deduction.
- **Supplier bills** sit in Accounts Payable and are paid from Stanbic (EFT,
  `PAY-2026-xxxx`, auto-reconciled) or occasionally Equity (APP/MTN lines,
  matched to bills by phone number and amount). The captain deliberately
  spreads payments out; an unpaid bill is still that month's cost.
- **Till cash** is banked by Fahil almost daily. A Stanbic credit naming
  Fahil (or matching a recorded session deposit within 7 days) is cash from
  POS sales: Dr Stanbic / Cr Cash Restaurant. Automated in the module.
- **Petty cash** is topped up from the till at session close, occasionally
  from Equity (statement narration `PETTY CASH TOP UP`). Staff advances and
  loans come out of petty cash or MoMo. Petty cash can never be negative;
  the module now blocks entries that would take it below zero.
- **Rent and utilities** are paid a month late, both on the last day of the
  month or the first days of the next. Rent goes through NAMANYA BARBRAH
  (a forex bureau: they buy ~USD 1,600 and pay the landlord's dollar
  account) -> `281400 Rent`. Utilities go to GATEWAY METROPLEX (the mall's
  shilling account) -> `223000 Utility & Property`. A 31 Aug pair is July's
  rent; do not accrue on top of it (July 2026 was double-counted that way
  and had to be reversed).
- **Director drawings** are frequent and large (Aug 2026: 17.7M). They
  reduce equity, never profit. Accounts: `301000 Director Drawings - Ntale`,
  `513002 Director Drawings - Sophie`, `519100 Director Drawings` (generic,
  used when the statement does not say whose). Show them plainly; the
  captain wants to see them.

## 2. Equity statement (the monthly PDF)

Tooling: `kx equity import`, `open`, `book`, `status`, `set-closing`. Always
`--dry-run` first and show the captain the dry run.

Facts about the PDF:

- The portal period starts a day early (e.g. 31/07 to 31/08). Lines dated
  in the previous month were already reconciled in that month's close: skip
  them. `kx` dedupes, but check the opening balance matches the previous
  statement's closing (July closed 17,346,186; August closed 24,919,559).
- Signs come from the running-balance chain, not the debit/credit columns.
- A charge line repeats its parent payment's narration; charges are
  matched first so a "MOBILE MONEY CHARGES" on a drawings payment still goes
  to bank charges.

What the rules book automatically (`tools/kx/remote_equity.py`):

| Narration contains | Account |
|---|---|
| MOBILE MONEY CHARGES, RTGS CHARGES, TRANSACTION CHARGE, COMMISSION ON INWARD RTGS, EXCISE DUTY, LEDGER FEE, SERVICE CHARGE, WITHDRAWAL CHARGE | 291001 Bank Charges |
| EQSET | 101530 Card Settlement |
| RTGS AIRTEL MOBILE COMMERCE (credit, 19.7M in Jul, 20M in Aug) | 101520 Airtel Pay: liquidating the Airtel wallet into the bank, a transfer, never income |
| NAMANYA BARBRAH | 281400 Rent |
| GATEWAY METROPLEX | 223000 Utility & Property |
| CLOUD FEES, CLAUDE SUBSCRIPTION, INTERNET SUBSCRIPTION, MIFI | 222000 Communications |
| PETTY CASH TOP UP | reverses the parked suspense entry, lands in 352814 Petty Cash; a bank amount above the parked one (e.g. 405,000 vs 400,000) is a withdrawal fee -> bank charges |
| APP/MTN or APP/AIRTEL payment whose phone number and amount match an open bill | settles that bill (`bill:BILL/...`) |

Precedent for the lines that need a decision (how the same thing was booked
before; reuse unless the captain says otherwise):

| Line | Booking |
|---|---|
| GRAD DINNER, GRADUATION, GRAD PARTY/LUNCH/CLOTHES/DRESSES, HOME CARPETS, SHOPPING (HOME PRODUCTS), SHOPPING CYNIBEL, CUSHIONS, SUPERMARKET, 72 FOOD, DAVINO DINNER, Safina grad fees, anything personal | 519100 Director Drawings (or the named director's account if the captain says whose) |
| SHABAN IRISH 220,000 (x10 in Aug), IRISH POTATOES to 0759255787 (Joel, 260,000) | `bill:` the matching Irish potato bill of the same amount, oldest first; Shaban and Joel deliver Irish to the store |
| HONEY 200,000 | Matua Stephen bill if one is open, else 224000 Supplies and Services |
| STAFF RICE 200,000 | Kiwatule Wholesale bill of the same date |
| KITCHEN DOOR FIX, AC SERVICE, DRAINAGE DEPOSIT, fryer repair, furniture repair, REMAT / Reagan "kitchen works" | 600300 Repairs & Maintenance |
| Barcode scanner 825,000, company phone 430,000, laptop | 310220 ICT equipment (capitalise equipment above roughly 400,000; under that, expense it) |
| Food delivery bag or bike gear | 600330 Motorcycle Running Costs (over 400,000: 310210 Transport equipment) |
| ADS, marketing payments | 600500 Marketing & Advertising |
| Petty cash box (the physical box) | small equipment expense, not petty cash |
| Payments to suppliers that predate Odoo (pre-July 2026) | 519000 Opening Balance Clearing, attributed to the vendor; never P&L |
| URA VAT (PRN 22700041425xx) | 411722 Taxes payable |
| URA PAYE | 620200 PAYE |
| Director payouts by EFT (DPAY/...) | the director's drawings account |

Vendor aliases the captain uses: POA / Pearl = PEARL OF AFRICA 2012 STEP CO.
(cheese); Suli / Suula = Suulah Food Suppliers; Dre = beef supplier;
Knowledge / Fanta = Knowledge For Rural Development (soda); Ice cream =
Afrifresh; Irish = Goliath Enterprises before August, then Shaban, then
Joel; Gas = Imperial Gas Agencies; Dairy man = mozzarella; Biyinzika =
chicken; Heron = Heron Official Traders (spices, dry goods); SY = SY
Authentic Packaging; Rentokil = pest control; Rapid = Rapid Ventures.

After booking: `kx equity status` must show bank closing = book balance for
the statement date (August: 24,919,559 to the shilling). If the Odoo
statement record still shows a computed figure, `kx equity set-closing`
with the PDF's closing once the captain confirms it.

## 3. MTN MoMo (monthly CSV, or daily from now on)

- Odoo already holds every MoMo sale (POS) and the payroll transfers. The
  statement is a comparison, never an import: importing lines would double
  count revenue.
- Match by transaction id against `pos_payment.krunchix_transaction_ref`.
  August: 567 of 613 matched to the shilling.
- Every inbound payment is docked a merchant fee (about 1%); transfers out
  cost 500 to 1,500 each. Odoo never records these itself. Book the month's
  total at month end: Dr `600400 Payment Processing Fees` / Cr MoMo
  (August: 335,895).
- Customer paid more than the till rang: on delivery orders that is the
  rider's fee sent with the food. The field `krunchix_rider_reimbursement`
  on the payment captures it when the cashier remembers; when they did not,
  book the surplus Dr MoMo / Cr `600320 3rd-Party Delivery Cost` (August:
  297,000 on 36 orders). On dine-in orders a surplus is a tip.
- Mis-keyed refs (two customers' refs swapped, a 1-shilling test ref from
  the captain's own number) cancel out; the captain's 1-shilling test
  payments sit in the wallet as unmatched credits and are ignored.
- Refunds with no MTN counterpart, or refs MTN never issued, go to suspense
  and are listed for the captain, never guessed.
- The portal export named `..._2026-07-31_2026-08-31.csv` did not contain
  31 July at all. Check the first and last dates before trusting a file.
- The wallet's live balance is in the latest receipt SMS (`kx wallets`).
  Book vs wallet gap = unbooked fees + unmatched receipts + anything
  pre-August (1,004,500 carried from before August, unresolved).
- Money on the *company* line (customers who send to the personal number
  instead of the merchant code) is still rung through POS with the ref, so
  it is not missing revenue.

## 4. Airtel Pay

- The portal only exports the last 15 days, so there is never a full-month
  statement. Use the SMS closing balance on the last day of the month as
  the anchor (31 Aug 2026: 12,969,111).
- Same shape as MoMo: commission on every receipt, rider money and tips in
  the surplus, so expect the same kind of gap (31 Aug: wallet 1,300,815
  above book). Do not post a plug; list it, and reconcile daily from the
  receipt SMS going forward.
- Liquidations to Equity (RTGS AIRTEL MOBILE COMMERCE) draw the wallet
  down by the full amount; the inward RTGS commission is a bank charge.

## 5. Stanbic

Fully automatic: statement pulled by API, Fahil deposits matched to POS
session deposits (module rule, also catches typos like "FAHIK"), EFT
supplier payments matched to bills, small charges (excise, electronic
account pmts, monthly management fee, under 50,000) booked to 291001. What
is left after the cron is genuinely for a human: a payment to a supplier
with no bill, or a deposit that disagrees with what the session recorded
(6 Aug bank 1,260,000 vs recorded 1,206,000; 15 Aug 755,000 vs 775,000:
transposed digits, tell Fahil). Stanbic bank-codes and balance APIs are not
subscribed; the running balance comes from the statement.

## 6. Month end: what "closed" means

Order: Stanbic (automatic) -> Equity -> MoMo -> Airtel -> cash suspense ->
stock adjustment -> tax true-up -> read the picture.

- **Stock.** Valuation is standard cost, periodic. Purchases go straight to
  `224000 Supplies and Services`; nothing posts COGS automatically. The
  closing stock is the physical count at 08:00 on the 1st, valued at cost.
  COGS = opening + purchases - closing. The stock adjustment moves the
  difference between `320111 Inventory` and `224000`. `320114` (goods for
  resale) is archived; all categories and company accounts point at 320111.
  Before trusting a count, check `stock.move` adjustments in the last days
  for fat fingers (August had three multi-million typos: caramel syrup
  +100,040 ml, corn starch +398,980 g, Oreo +261,576 g). A wrong count
  swung August's profit from 29.1M to 17.6M.
- **Cut-off.** Goods received on the last day need their bill dated in that
  month, otherwise stock is counted and the cost is not (Heron 4.4M bill
  P00148, September 2026).
- **Comps.** Director, Marketing and Staff Special Day meals are company
  accounts: rung at zero, cost of ingredients charged to `601910`/`601930`
  and credited out of stock. They are not sales.
- **VAT.** POS sales are 18% inclusive; output VAT accrues in `411722`.
  Input VAT has never been captured on bills (`352804` is empty), so the
  ledger overstates the liability; the captain files with pre-Odoo credits
  and pays a small net (August: 670,700; July: nil). Keep the estimate,
  book the filed figure against Opening Balance Clearing when the captain
  gives it, do not try to fix VAT in a reconciliation. A cash sale outside
  POS (custom cake) is invoiced Tax Exempt and declared as miscellaneous.
- **Profit vs cash.** The captain thinks in money retained. Always give
  both: profit (net sales less all costs) and where the cash went
  (drawings, stock build, supplier debt paid down, equipment, loans, VAT
  collected but not paid). Show gross rung, VAT inside it, net revenue.
  Bought-vs-paid: bills dated in the month vs cash to suppliers in the
  month, and how much of the cash cleared the previous month's bills.
- **Anchors so far.** July 2026: revenue 68.7M, profit about 8.8M before the
  rent catch-up (three months of landlord payments landed in July). August
  2026: rung 101,041,500 over 2,279 orders, revenue 85.35M, profit
  17,605,388 (food cost 52%), drawings 17,714,400, Stanbic 31 Jul closing
  117,929,905, Equity 31 Aug closing 24,919,559, MoMo 31 Aug wallet
  62,588,278.80 (book 61,583,779), Airtel 31 Aug 12,969,111.

## 7. Traps that cost time before

- Do not import statement lines for MoMo, Airtel or VISA: POS already holds
  the sales. Only Equity and Stanbic are line-reconciled.
- The suspense account (`352803`, not reconcilable) is a parking bay:
  petty-cash top-ups waiting for their bank line, POS cash moves whose
  reason has no counterpart account (cake sale, tips, refunds). List what
  is in it and why; it should be near zero after a close.
- Tips paid out go to `211100 Wages and Salaries - Cash` (no tips account);
  client refunds go back against sales; a delivery fee cash-in goes against
  `600320`.
- Stanbic deposits keyed into Odoo late carry the typing date, not the
  banking date; the 7-day window exists for that.
- Odoo 19 stores `account.code`, `standard_price` and product names as
  company-dependent jsonb; read them through the ORM or `->>'en_US'`.
- Mattermost alerts fire from a background thread: a dry run that raises an
  alert has already sent it. Prefer `kx --dry-run`, which prints instead.
- Never book a plug to make a wallet tie. The captain would rather see the
  gap named than a number that lies.
