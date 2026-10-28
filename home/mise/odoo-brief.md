# Krunchix Odoo: brief for the reconciliation and Q&A agent

Snapshot taken 2026-10-23 from prod (read-only). Figures marked "today" will drift.

## 1. The business and the system

- KRUNCHIX BAKERY COMPANY LIMITED (URSB 80034606434587), one cafe in Kampala
  (Metroplex). Directors: Ntale Shadik (the user, also the developer) and
  Namaganda Sophia ("Sophie"). Currency UGX. Timezone: always Africa/Kampala
  (UTC+3), never the user's tz.
- Odoo 19 Enterprise on Doodba, repo `~/workspace/odoo`; custom code only in
  `odoo/custom/src/private/krunchix_*`. Live since the early-July 2026 cutover.
- Two databases:
  - Current: `odoo` on CNPG cluster `odoo-prod`, namespace `pg-odoo`. Read from the
    replica pod `odoo-prod-2` (container `postgres`).
  - History before July 2026 (POS only, no bills/accounting): `odoo17` on cluster
    `apps`, namespace `pg-apps` (pods `apps-1`, `apps-2`).
- Inventory valuation is Manual/Periodic on all categories: stock moves post no
  journal entries. COGS comes from vendor bills plus a month-end stock value.
- Supplier prices are tax-inclusive; no purchase VAT is added.

## 2. How to get at the data

Read-only SQL (safe, use freely):

```
kubectl --context admin@kx-hcloud -n pg-odoo exec -i odoo-prod-2 -c postgres -- psql -d odoo
```

SQL gotchas: `account_account.code` lives in `code_store->>'1'`; names are jsonb
(`name->>'en_US'`); a bank statement line's date and state come from its
`move_id` (`account_bank_statement_line` inherits `account_move`).

Writes go through an Odoo shell script on the web pod, always dry-run first
(roll back, print every account's balance next to the bank's real balance),
then commit only after the user approves:

```
kubectl -n odoo exec -i deploy/odoo-web -- env KX_DRY=1 odoo shell --no-http < script.py
```

Make scripts idempotent (refuse to import a statement twice), print `LOG ...`
lines, and end with `LOG COMMITTED` or `LOG ROLLED BACK`. Write the full output to
a log file so a failed run can be diagnosed.

## 3. Money accounts (journals)

| Journal | Code | GL account | Balance today | How lines arrive |
|---|---|---|---|---|
| Stanbic Bank | BNK1 | 352801 | 124,149,581 | Automatic: hourly API import of the last 7 days |
| Equity Bank | EQTY | 352815 | 26,638,784 (= real 30 Sep) | Monthly statement the user uploads. Imported to 30 Sep 2026; October not done |
| Cash Restaurant (till) | CSH1 | 352813 | 162,990 | POS sessions (cash in/out) |
| Petty Cash | PTY | 352814 | 200,853 | Expenses + "Top up Petty Cash from Bank" form |
| MTN MoMo (merchant) | MOMO | 101510 | 37,730,615 | No statement lines. POS books straight into the wallet |
| Airtel Pay | AIRT | 101520 | 24,356,921 | Same as MTN |
| VISA (card clearing) | VISA | 101530 | 5,692,000 | POS card takings; cleared by Equity EQSET settlements |
| MTN MoMo API wallet | MOAPI | 101540 | 24,129,619 | Payroll, advances, MoMo supplier payments, MoMo prompt at till |

Other accounts you will touch:

- 352810 Liquidity Transfer (reconcilable): internal moves between our accounts.
  It should net to 0 (it does today).
- 352812 Outstanding Payments: payments registered but not yet matched to a bank
  line. Since 2 Oct, Equity's outbound payment method uses it, so a supplier
  payment registered from Equity waits here until the statement line matches.
- 352803 Bank Suspense: NOT reconcilable. Should sit at 53,000 (MISC/26-27/08/0062
  "MoMo items pending investigation, August 2026"). It does today.
- 411700 Accounts Payable: today 21 open vendor bills, 18,106,511 owed.
- 291001 Bank charges (incl. card commission, excise, RTGS fees); 600400 Payment
  Processing Fees.
- 211510 Rider Payouts Clearing (rider money that passes through us).
- 519100 Director Drawings (equity, off the P&L). Per-director accounts:
  301000 (Ntale), 513002 (Sophie).
- 121200 Employee Advances, 121300 Staff Loans, 121400 GoGo Bike Wallet.
- 411722 Taxes payable (VAT), 620200 PAYE, 620100 Salaries and Wages.
- 222000 Communications (AI tools, hosting, internet, SMS sender IDs, airtime),
  223000 Utilities, 281400 Rent, 224000 Supplies and Services (= food cost; only
  real ingredients), 600300 Repairs & Maintenance, 600310 Kitchen Supplies &
  Sundry, 600330 Motorcycle Running Costs, 600500 Marketing, 310220 ICT equipment.
- 519000 Opening Balance Clearing: only for pre-go-live items.

## 4. How money moves

- **Till takings:**
  - Cash goes to the till. At closing, the manager (Fahil) banks the cash at
    Stanbic. A Stanbic credit named "Fahil" is auto-matched to the closed
    session's `amount_to_deposit`. The bank figure wins over a typed one.
  - Card goes to 101530 and settles into Equity as "EQSETddmmyy".
  - MTN and Airtel MoMo go straight into their wallet accounts.
  - The MoMo Prompt method books to the MOAPI wallet.
- **Card settlement:**
  - EQSETddmmyy is that day's card takings, net of a flat 3%. Weekends are batched
    on Monday.
  - Book it as Cr 101530 for the gross and Dr 291001 for the 3% fee.
  - Card takings on the last days of the month settle next month, so 101530 keeps
    a small balance.
- **Wallet sweeps:**
  - MTN and Airtel are swept into Equity, then on to Stanbic, all via 352810.
  - Stanbic sends to MoMo account 500201905103957 to fund the MoMo API wallet.
- **Wallet fees:** MTN merchant 1%, Airtel 1.5%. Wallets reconcile by closing
  balance plus fee and rider entries, not line by line.
- **Rider money:**
  - On a delivery, the customer may pay extra by MoMo for the rider. That extra is
    not our income or cost.
  - It goes through 211510 (Dr wallet / Cr 211510, then the cash payout is Dr
    211510 / Cr till).
  - Before 2 Oct it was wrongly booked to 600320 and corrected at month end.
- **Supplier payments:**
  1. A manager raises a payment request (`krunchix.payment.request`).
  2. States: draft, pending (Awaiting Director), approved, processing, paid,
     failed, rejected, cancelled.
  3. A director approves it.
  4. It is paid by Stanbic EFT (API) or MTN MoMo (API). Each sends a proof PDF to
     the supplier on WhatsApp.
  5. A Stanbic EFT is an `account.payment` with no outstanding account, so it
     stays "in_process" with no journal entry until the bank line arrives. The
     2-hourly `_cron_reconcile_eft` then matches it by message id and the bill
     flips to Paid.
  6. A MoMo supplier payment marks the bill paid on MTN SUCCESSFUL. No statement
     is needed.
  7. Older supplier payments went out from Equity (APP/MTN/..., APP/AIRTELMONEY/...)
     and are matched to open bills during the Equity reconciliation.
- **Rent and utilities:**
  - Paid from Stanbic since 30 Sep (Equity before that).
  - Paid in arrears, for the previous month, and expensed in the month paid. No
    accruals.
  - Rent is USD 1,600, paid in UGX to a forex bureau, which deposits it for the
    landlord, Gateway Metroplex Ltd. Book it to 281400, in UGX at the bureau's
    rate.
  - Utilities go to the landlord's Stanbic account, booked to 223000.
  - On old Equity statements, rent was RTGS to "Namanya Barbrah" (the bureau
    contact) and utilities were RTGS to Gateway Metroplex.
- **Payroll:**
  - Staff are daily-wage, paid monthly over the MoMo API.
  - Each payslip posts Dr 620100 / Cr Salaries Payable. The MoMo payout clears the
    payable.
  - Three employees are registered for PAYE; the PAYE paid to URA is an expense
    (620200).
  - Advances are requested on WhatsApp and paid over MoMo (Dr 121200 / Cr MOAPI).
- **Director payouts:** drawings via `krunchix.director.payout`, never salary and no
  PAYE. Director personal spending from company money goes to 519100.
- **Petty cash:**
  - Expenses need a category and a receipt. Categories map to accounts (food buys
    go to 224000, staff meals to 601920, not food cost).
  - The "Top up from bank" form posts Dr 352814 / Cr a suspense or outstanding
    line. When the bank statement shows "PETTY CASH TOP UP", match it to that open
    item, never to 352814 again (that double-counts).
- **GoGo bike wallet (121400):**
  - Prepaid battery-swap balance, topped up from Equity.
  - Top-ups now post as an outbound payment through 352812 so the bank line
    matches.

## 5. Equity monthly reconciliation (the main job)

**Inputs from the user:**

- The Equity statement, usually the Equity Online PDF
  (`receipts_<from>_<to>.pdf`).
  - Rows wrap across several text lines. Rebuild each row so it keeps its
    "APP/<MTN|AIRTELMONEY>/<phone>/<txn>/<name>" header.
  - Older months came as CSV: `Date,Label,Reference,Amount,Running Balance`.
  - Account number 1042202970288.
- Often also, for the same month:
  - the MTN merchant CSV (`151063075_<from>_<to>.csv`);
  - the MoMo API wallet CSV (`219117689_...csv`);
  - Airtel, which only exports the last 15 days, so ask for the month-end balance.
- Stanbic is already in Odoo via its API.

**Procedure:**

1. Parse every row: date, label, reference, amount, running balance.
   - Check that the running balance chains with no gaps.
   - Check that the opening balance equals Odoo's 352815 balance at the cutoff.
   - Drop rows from before the cutoff. They belong to the previous month and are
     already in Odoo.
2. Check that Odoo has not already got this period. EQTY lines exist up to
   2026-09-30. Statements are named "EQTY Statement YYYY-MM-DD", one per month.
   Never import twice.
3. Classify each row using the table below.
   - Look for an existing open item before inventing a counterpart: an open bill
     for that supplier, an open suspense or outstanding entry (petty top-ups, bike
     top-ups, payments registered from Equity), or a 352810 transfer leg.
4. List anything you can't classify, with date, amount, label and your best
   guess, and ask the user once. Only genuinely new payees need asking.
5. Dry run: create the statement and lines, reconcile them, and print the balances
   of 352815, 352801, 101510, 101520, 101530, 101540 and 352810 against the real
   closing balances. Equity must match the statement's closing running balance to
   the shilling.
6. After the user approves, commit (or hand the user the command if your
   permissions block prod writes).
7. Re-read prod to confirm it landed.
8. Report the month in plain language: what was booked, what is still open, and
   "how much we retained" (profit). Profit includes:
   - the fees;
   - the stock change: on-hand at the 1st of the next month, 09:00 Kampala, times
     standard cost, minus the same at the start of the month. Watch for count
     typos near the snapshot; Sept had Oreo 261,576 g and vanilla syrup.

**Classification table (from the Aug and Sep reconciliations, 345 lines):**

| Statement label looks like | Book to |
|---|---|
| EQSETddmmyy | Cr 101530 gross card takings, Dr 291001 3% fee |
| Charges, excise duty, "MOBILE MONEY CHARGES", RTGS charges, ledger fees | 291001 |
| "TPG/KRUNCHIX BAKERY..." from MTN, RTGS from AIRTEL MOBILE COMMERCE | 101510 / 101520 (wallet sweep in) |
| RTGS "KRUNCHIX BAKERY COMPANY" out to Stanbic | 352810 (match the Stanbic leg) |
| APP/MTN or APP/AIRTELMONEY to a supplier | Match the supplier's open bill (411700). Kasim is paid on Willy Ssegginggo's number |
| AI tools, hosting (Hetzner, Claude), internet, airtime, SMS sender IDs | 222000 |
| Repairs, bulbs (Lighting City), equipment fixes | 600300 |
| Laptops, phones, ICT kit | 310220 |
| URA ... VAT | 411722 |
| URA ... PAYE | 620200 |
| Director personal items, Supermarket, "Sophie", graduation and family items | 519100 |
| Rent RTGS (bureau / Namanya Barbrah) | 281400 |
| Utilities RTGS to Gateway Metroplex | 223000 |
| PETTY CASH TOP UP | Match the open top-up entry (never 352814 directly) |
| GoGo wallet top-up | Match the bike-wallet payment in 352812 (121400) |
| Marketing spend | 600500 |
| Ingredient buys with no bill (rare) | 224000 |

Past one-offs the user decided:

- 2 Sep 400k "Hosting fees" was split: 200k GoGo top-up and 200k hosting.
- A 35k Airtel receipt with no sale was booked as a sale.
- Gaps from before September went into one entry dated 31 Aug.

### Equity statement records vs the ledger (read before the October import)

The Equity ledger (GL 352815) is right: 26,638,784, the bank's real 30 Sep
balance. Odoo's statement records (`account_bank_statement`, journal EQTY) say
7,517,410. They are short by exactly 19,121,374. This is a statement-record gap
only; no money is missing.

Why the gap exists:

- **Opening balance:** at go-live, Equity's opening balance of 19,144,824 was
  posted as a plain journal entry, MISC/25-26/06/0004 "Opening balance Equity Bank
  (migration)", dated 2026-06-30. It is not a statement line, so the ledger counts
  it but the statement chain started from 0.
- **Missed charges:** MISC/26-27/07/0055 "Equity charges missed on import"
  (-23,450, 31 Jul) is also a plain entry, outside the statements.
- **The arithmetic:** 19,144,824 - 23,450 = 19,121,374, and
  7,517,410 + 19,121,374 = 26,638,784.
- **July's lines:** the 85 July statement lines (-1,775,188) are booked and
  reconciled but have no `statement_id`. That is why the August statement opens
  at -1,775,188.
- **GoGo top-ups:** the two Sep entries (EQTY/26-27/0171 and 0315), each reversed
  by 0433 and 0434, net to zero.

The fix, approved by the user:

- Correct only the statement records' opening and closing figures (e.g.
  `kx equity set-closing`).

  | Statement | Opening | Closing |
  |---|---|---|
  | EQTY Statement 2026-08-31 | 17,346,186 | 24,919,559 |
  | EQTY Statement 2026-09-30 | 24,919,559 | 26,638,784 |

- Then October opens at 26,638,784.
- Do NOT post any journal entry to "fix" the 19.1M. That would double-count the
  opening balance.
- Optional and cosmetic: group the 85 July lines into a July statement. It won't
  chain to the shilling, because the 23,450 of charges sits outside the
  statements.

The rule for the future: the Equity ledger balance is the truth to check against
the bank. The statement records' opening and closing figures are only checks.

## 6. Open items going into October

- **Equity October:** not imported yet. The opening balance must be 26,638,784
  (the real 30 Sep balance). Fix the statement-record chain first (see "Equity
  statement records vs the ledger" above).
- **Order Metroplex - 000221 (2 Oct, 37k):** rung up as merchant MTN (101510), but
  the money landed on the company MTN line. Expect merchant -37k and company line
  +37k.
- **Duplicate Airtel 157892458219 (37k, 2 Oct):** refunded in cash as a
  Metroplex/00094 cash-out (Dr 101520 / Cr till). Receipt 2369 is set to ignored.
- **BILL/26-27/08/0059, Rentokil fumigation, 386,435:**
  - No payment exists in Odoo.
  - Payment request PAY/2026/0211 has been Awaiting Director since 1 Oct.
  - If an October Equity or Stanbic line shows it, match it to this bill.
- **Africa's Talking sender ID bill:** book to 222000, not 224000.

## 7. Traps that have bitten before

- Odoo 19 `account.payment` with no outstanding account has no journal entry
  until a bank line reconciles it. Its bill shows "in_payment" with the full
  residual. Don't read that as unpaid.
- 352803 is not reconcilable. Clear an item there with an offsetting entry or a
  reversal, never `reconcile()`.
- Petty top-up double count:
  - The till suggests the top-up as target minus the petty balance.
  - In Sept a stray 50k debit on 352814 made it suggest 42k instead of about 92k.
- Stanbic auto-matching can pick the wrong line for same-amount payments. Check
  the partner and reference, not just the amount. Nearby amounts (e.g. 390,000 vs
  386,435) are different payments.
- A deposit line often posts before the manager records the deposit. The matcher
  links them later; the unmatched alert waits 24h.
- A POS refund leaves the original order "done". A full refund frees the MoMo
  transaction ref.
- Never reopen a paid POS order to draft. Swap the payment in place.
- A PO's `amount_total` is the ordered value. The bill and the receipt are what
  count.
- Chicken is ordered in kg but stocked in pieces (`krunchix_weigh_count`), so PO
  quantity discrepancies on those lines are misleading.
- `res.groups.user_ids` in v19 is direct members only. Use `has_group`.
- A manager can't see Accounting, payments, bank lines, POS session totals or
  sales reports. This is deliberate (blind deposits). Don't expose deposit totals
  to managers.

## 8. Answering Odoo questions

- **People:**
  - Logins are only Managers (e.g. Fahil, user 7) and Directors.
  - Cashiers and staff are POS employees with PINs, not users.
  - Directors approve POs and payments; managers submit them.
- **Key custom modules** (`krunchix_*`):
  - `pos_cash_control`: deposits, petty cash, cash reasons.
  - `momo_reconcile`: SMS receipts, tips, rider payouts.
  - `momo_pos`: MoMo prompt and bill QR.
  - `momo_disbursement`, `momo_payroll` and `momo_purchase`: MTN API payouts.
  - `stanbic_bank`: API statement import.
  - `stanbic_purchase`: EFT, payment requests, proofs, supplier statements.
  - `purchase_approval`: director approval, Supplier Orders.
  - `purchase_intelligence`: waste sheet, drift, alerts.
  - `expense`: petty cash categories.
  - `director_payout`, `rent`, `bike_wallet`, `hr_payroll`, `hr_advance`,
    `ops_advance`.
  - `pos_marketing`: Company Accounts comp tenders (Marketing, Staff Meals,
    Director).
  - `pos_restrict`: manager PIN, voids and refunds.
  - `recipe_cost` and `food_cost`.
  - `sales_declaration`: the landlord turnover letter.
- **Accounting menus** live under the Accounting app (`accountant.menu_accounting`).
- Mattermost carries internal alerts; WhatsApp carries supplier and staff messages.

## 9. House rules

- Never use the em dash; use a plain "-".
- Plain language for the user, who is not an accountant. Show the money trail,
  then the entry.
- Read-only first. Never write to prod without a dry run and the user's go-ahead.
  Never print secrets or credentials.
- No accruals for rent or utilities. Director items are drawings, never P&L.
  Only real ingredients count as food cost.
- When unsure about a payee, ask once with your best guess. Reuse the mappings
  above and don't re-ask settled ones.
