# Phase B Demo Execution Evidence — CS-0 and CS-1

- **Project:** Lovable `tansub` / AutoLoan Central
- **Project ID:** `ba86c689-294b-4f44-b209-7ee1c7d99319`
- **Environment:** Demo Supabase database; not production
- **Execution date:** 2026-08-14
- **Branch:** `phase-b-contract-cancel`
- **Status:** STOPPED FAIL-CLOSED AFTER CS-1 — POST-MIGRATION VERIFICATION UNAVAILABLE

## 1. CS-0 baseline result

### Contract lifecycle

| Status | Contracts |
|---|---:|
| active | 14 |
| overdue | 16 |
| closed | 4 |
| total | 34 |

All 34 contracts have at least one preserved payment row. No current contract is eligible for `contract_cancel` testing.

### Payment/cash evidence

- 314 payment rows across 34 contracts.
- No voided payment rows.
- Two payments have no linked `cash_entries`:
  - `RCP-HQ2608-0001`
  - `RCP-HQ2608-0002`
- Both belong to closed contract `CTR-HQ2608-0001`.
- No cash entry points to a missing payment.
- No payment/cash entry is linked across different contracts.
- No duplicate pending `contract_cancel` request exists.

### Closed-contract lifecycle

All four closed contracts retain `loan_applications.status = contracted`, which matches the confirmed rule that payoff/closure is completion rather than cancellation.

### Financial baseline

- Collectible contracts (`active` + `overdue`): 30
- Outstanding: 326,755,386 satang
- Overdue installments: 48
- Overdue amount: 35,666,648 satang

### Anomaly classification

The two payments without cash entries are a blocker for future historical `payment_void` automation, but not for `contract_cancel`:

- the payment rows still exist;
- permanent payment evidence can be backfilled;
- the contract is closed and ineligible for cancellation;
- no data repair was performed.

## 2. CS-1 execution

Applied migration:

`supabase/migrations/20260814130000_phase_b_cs1_payment_evidence.sql`

The database execution endpoint returned success with no error rows.

Expected effects:

- add/backfill `contracts.first_payment_at`;
- create immutable marker trigger;
- set marker on first future payment insertion while locking the contract row;
- reject payment insertion for cancelled contracts;
- prevent physical payment deletion;
- revoke authenticated DELETE permission;
- create reconciliation index/check.

## 3. Verification failure and stop decision

Immediately after CS-1, post-migration verification queries stopped receiving a normal response:

- combined marker/privilege query timed out;
- separated marker count query returned Lovable transport HTTP 504;
- even `SELECT now()` did not complete.

Because post-migration state could not be proven, execution stopped before CS-2.

Not applied:

- CS-2 Phase A rule alignment;
- CS-3 lifecycle/duplicate guards;
- CS-4 contract-cancel executor;
- demo fixtures;
- regression tests;
- merge to `main`;
- Lovable deployment.

## 4. Required recovery gate

Before continuing:

1. confirm Lovable database query service responds to `SELECT now()`;
2. verify `first_payment_at` exists;
3. verify 34 contracts are marked and no payment belongs to an unmarked contract;
4. verify authenticated DELETE permission on `payments` is false;
5. verify CS-1 triggers/functions exist;
6. compare contract/payment/overdue totals with the CS-0 baseline;
7. continue to CS-2 only if every check passes.

No retry of CS-1 and no later migration is permitted until these checks complete. CS-1 is written idempotently, but must not be blindly reapplied while its actual state is unknown.


## 5. Recovery verification on 2026-08-15

Lovable Database Query recovered temporarily.

CS-1 passed all required checks:

- `contracts.first_payment_at` exists as `timestamptz`;
- 34 contracts with payments are marked;
- zero payment rows belong to an unmarked contract;
- authenticated DELETE privilege on `payments` is false;
- all three CS-1 triggers exist with the expected event/table;
- all three trigger functions exist.

## 6. CS-2 execution on 2026-08-15

Applied:

`supabase/migrations/20260814131000_phase_b_cs2_phase_a_rule_alignment.sql`

The database endpoint returned success.

Post-apply data baseline remained unchanged:

- contracts: 34;
- payments: 314;
- installments: 768;
- closed contracts: 4;
- all four linked closed applications remain `contracted`.

The first function-definition verification query used an over-specific signature filter and returned no row. A corrected system-catalog query then received HTTP 504. A concurrent approval-status evidence query also received HTTP 504.

Therefore CS-2 behavioral/function-definition verification is incomplete. Execution stopped before CS-3. No CS-3/CS-4 migration, fixture, merge, or deployment was performed.
