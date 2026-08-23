# Phase B Implementation Plan — F0 Guardrails and contract_cancel

- **Repository:** `superchoice-ai/tansub`
- **Environment:** Lovable/Supabase demo; not production
- **Plan status:** PAUSED FAIL-CLOSED AFTER CS-2 — FUNCTION VERIFICATION BLOCKED / NOT MERGED / NOT DEPLOYED
- **Active workflow:** `contract_cancel`
- **Later workflow:** `payment_void` requires a separate F1 plan
- **Excluded:** `restructure` remains unsupported and fail-closed
- **Confirmed by decision owner:** Five F0 business decisions confirmed on 2026-08-14

## 1. Confirmed decisions

1. Use immutable `contracts.first_payment_at` as permanent evidence that a contract has ever received a payment. It must never be cleared by payment void.
2. Prohibit physical deletion of payments. Corrections must use the separately approved `payment_void` workflow.
3. A `closed` contract is completed and must never cause its loan application to be changed to `cancelled`.
4. Payment recording and contract cancellation must coordinate through the same database contract-row lock.
5. A `cancelled` contract cannot receive a new payment or new collection activity; existing history remains.

These decisions authorize this plan only. They do not authorize code, migration, UI, RLS, data, fixture, deployment, or production changes.

## 2. Required outcome

After a separately authorized implementation:

- staff may submit a cancellation request only for an eligible contract with no permanent payment evidence;
- pending/rejected requests change no business data;
- approval revalidates all conditions and applies the complete cancellation atomically;
- contract and application become `cancelled`;
- installments are captured in durable audit evidence, then deleted;
- disbursement, vehicle-book status, payment/cash evidence, and collection history remain unchanged;
- future payment and collection creation are blocked;
- `closed` remains completion, not cancellation;
- `payment_void` and `restructure` remain unsupported until separately approved.

## 3. Planned change sets

Each change set is a separate review, migration/commit, regression gate, and rollback boundary. A passed step does not automatically authorize the next.

### Change Set CS-0 — Baseline and reconciliation evidence

**Purpose:** Prove the demo database is understood before schema or behavior changes.

Planned read-only evidence:

- contract counts by lifecycle;
- every payment row grouped by contract, including `voided=true`;
- earliest payment record per contract;
- payment-linked `cash_entries` grouped by contract;
- mismatches: payment without cash entry, cash entry without payment, cross-contract links;
- contracts with payment/cash evidence but no matching current payment history;
- closed contracts and their application statuses;
- pending duplicate approval candidates;
- current overdue/installment/report totals for later comparison.

**Acceptance:** Save exact queries and results. Any unexplained mismatch fails closed and stops the implementation.

**Runtime effect:** None.

### Change Set CS-1 — Immutable payment evidence

**Planned database objects:**

- add nullable `contracts.first_payment_at timestamptz`;
- backfill from all preserved payment rows, including voided rows;
- cross-check payment-linked cash evidence and fail migration/enablement where evidence conflicts;
- add database logic that sets `first_payment_at` on the first payment insertion;
- prevent any later update from clearing or moving the marker;
- remove authenticated/manager physical DELETE permission/policy for `payments`;
- preserve SELECT access needed by existing screens and reports.

**Important boundary:** `first_payment_at` is an eligibility marker, not a repayment amount and not permission to calculate debt.

**Expected consumers:**

- application debt-bearing edit lock;
- `contract_cancel` eligibility;
- future `payment_void`;
- contract detail/history;
- reconciliation and audit.

**Rollback:** Disable new consumers first. A compensating migration may remove trigger/guards, but must not erase payment evidence. Do not blindly drop a populated marker.

### Change Set CS-2 — Correct existing Phase A rule conflicts

**Planned correction:**

- application edit UI and Approval Executor stop using only `voided=false` as the lock;
- debt-bearing changes use permanent “ever paid” evidence;
- non-debt-bearing application fields remain editable through approval;
- existing application-cancel path rejects every linked `closed` contract as cancellation;
- payoff history and `closed` lifecycle remain unchanged;
- existing Phase A approval combinations remain exact/fail-closed.

**Affected files/objects:**

- `src/routes/_authenticated/applications/index.tsx`;
- `execute_approval_request()` migration/function;
- generated Supabase types if schema generation changes;
- application UI messages and approval detail.

**Rollback:** Restore the prior executor version only if doing so does not reopen debt-bearing edits. Prefer forward correction over reverting financial safety.

### Change Set CS-3 — Shared concurrency and direct-write guards

**Planned database behavior:**

- payment insertion locks the target contract row before accepting the event;
- cancellation approval locks the same contract row before revalidation;
- payment is rejected when contract status is `cancelled`;
- collection creation is rejected when contract status is `cancelled`;
- direct writes cannot bypass the lifecycle guard;
- one pending `contract_cancel` request per contract is enforced at database level;
- execution is idempotent: repeat approval cannot apply effects twice.

**Race result:**

- payment commits first → `first_payment_at` is set and cancellation fails;
- cancellation commits first → contract is `cancelled` and payment fails;
- both can never commit successfully.

**Rollback:** Dedicated guards can be disabled individually, but contract cancellation must also be disabled before removing a safety guard.

### Change Set CS-4 — Dedicated contract_cancel executor

**Architecture boundary:**

- keep `execute_approval_request()` as authentication, authorization, decision, and exact dispatcher;
- add a dedicated database executor for `contract_cancel`;
- do not perform related-table reflection in browser code;
- keep `payment_void`, `restructure`, and unknown combinations fail-closed.

**Planned approved transaction order:**

1. lock the pending approval request;
2. verify exact type/entity/operation and branch authorization;
3. lock the target contract;
4. revalidate lifecycle, application link, permanent payment evidence, cash evidence, and duplicate/replay state;
5. capture contract/application state and the complete installment schedule;
6. write durable audit evidence linked to approval;
7. set `contracts.status = cancelled`;
8. set linked `loan_applications.status = cancelled`;
9. delete the contract's installment rows;
10. preserve disbursement, payment/cash history, collection history, and vehicle-book state;
11. mark approval approved and write notification/audit outcome;
12. commit only if every step succeeds.

Any failure rolls back all steps and leaves the request unapproved.

**Rollback:** Remove/disable only the `contract_cancel` dispatch path. Preserve all completed cancellation and audit evidence; do not attempt destructive automatic reversal.

### Change Set CS-5 — Request and approval UI

**Lowest-blast-radius UI plan:**

- add “ขอยกเลิกสัญญา” on contract detail, not as a bulk list action;
- show plain-language eligibility and mandatory reason;
- producer inserts only `approval_requests`;
- display pending state from the approval request without changing contract status;
- approval screen shows target contract, customer, reason, current eligibility, and warning that approval is final;
- after decision, refresh approvals, contract, application, dashboard, reports, payment options, and collection queries;
- cancelled contract detail remains visible and shows audit-based schedule history or an explicit cancellation-history section.

**Not included:** payment-void UI, vehicle return confirmation, automatic blacklist, restructure, or disbursement recovery.

**Rollback:** Hide/remove request entry point while database executor remains fail-closed or explicitly disabled.

### Change Set CS-6 — Defensive consumers

**Planned consumers:**

- `src/routes/_authenticated/payments/index.tsx`: only collectible/payable contract states; database remains final guard;
- `src/routes/_authenticated/collections/index.tsx`: overdue query joins/filters collectible contract states; create action revalidated by database;
- `src/routes/_authenticated/dashboard.tsx`: overdue totals exclude non-collectible lifecycle states;
- `src/lib/reports.ts`: debtor/overdue reports select only confirmed collectible states;
- contract/application pages: clear `cancelled` presentation;
- prints/history: preserve original contract and show lifecycle without rewriting legal text;
- notifications/audit: requester, approver, reason, time, before/after, and affected objects.

**Rollback:** Consumer filters are independently reversible only while database guards remain active and reconciliation proves totals.

### Change Set CS-7 — Demo fixtures and regression execution

Create isolated demo/test fixtures only after explicit authorization:

1. eligible contract with installments/disbursement and no payment event;
2. contract with one active payment;
3. contract with one voided payment but permanent marker retained;
4. closed/payoff contract;
5. cancellation/payment concurrency pair;
6. forced-failure transaction fixture;
7. duplicate pending/replayed approval fixture.

Existing demo contracts must not be altered to manufacture eligibility.

## 4. Regression gates

### Gate REG-A — Phase A remains functional

- loan approval;
- customer edit/deactivate;
- application non-debt edit;
- application debt-bearing edit before payment;
- debt-bearing lock after any payment event, including voided;
- application cancellation without a contract where currently valid;
- cash-entry logical void;
- rejected approval mutates nothing;
- staff request versus approver/manager/admin decision rules remain unchanged.

### Gate REG-B — contract_cancel eligibility

- zero-payment contract may request and approve;
- active payment blocks request and approval;
- voided payment blocks request and approval;
- cash evidence conflict fails closed;
- closed and already-cancelled contracts fail;
- duplicate pending request fails;
- cross-branch/unauthorized decision fails.

### Gate REG-C — Atomicity and concurrency

- pending/rejected mutate nothing;
- payment-first blocks cancellation;
- cancellation-first blocks payment;
- simultaneous actions cannot both commit;
- forced failure at each executor step rolls back business and approval state;
- repeated approval has no duplicate effect.

### Gate REG-D — Related data

- contract/application become `cancelled`;
- audit snapshot is complete before installments disappear;
- disbursement, cash/payment evidence, vehicle book, and collection history remain;
- future payment/collection creation fails;
- active debt, overdue, and collection totals exclude cancelled contract;
- historical pages remain understandable.

### Gate REG-E — Supabase/infrastructure

- browser `.from()`;
- `.rpc()` method binding;
- auth/session;
- server client;
- RLS/branch access;
- generated types;
- Lovable build;
- existing Supabase Proxy behavior.

No step passes from UI-only evidence. Database reconciliation is mandatory.

## 5. Rollout sequence

1. CS-0 baseline evidence.
2. Review CS-0 anomalies and stop if unresolved.
3. CS-1 immutable evidence.
4. Reconcile marker/payment/cash evidence.
5. CS-2 Phase A rule corrections and full Phase A regression.
6. CS-3 concurrency/direct-write guards.
7. CS-4 dedicated executor, initially disabled/fail-closed.
8. CS-5 UI producer and approval presentation.
9. CS-6 defensive consumers.
10. CS-7 isolated demo fixtures and complete regression.
11. Demo-only enablement after evidence review.
12. Production topology/data Impact Review and separate explicit cutover approval.

## 6. Required evidence per change set

- exact migration/commit;
- changed files and database objects;
- before/after reconciliation results;
- regression cases executed and results;
- screenshots only where UI evidence is material;
- RPC/database error evidence for blocked paths;
- rollback command or compensating migration;
- remaining unverified areas;
- explicit approval for the next change set.

## 7. Resolved implementation interpretation gates

The decision owner confirmed all four gates on 2026-08-14:

- **U1 — Cancellable lifecycle:** both `active` and `overdue` are eligible when no payment event has ever existed.
- **U2 — Payment marker:** eligibility changes when payment count reaches at least one. The implementation records the database time of the first inserted payment event in `first_payment_at`; staff-entered/backdated `paid_at` does not control the permanent lock.
- **U3 — Schedule snapshot:** store the complete pre-cancellation installment snapshot in `audit_logs.detail`.
- **U4 — Application cancellation:** an application may be cancelled only until a contract row/contract number has been created. Once a contract exists—including a closed contract—the application is no longer cancellable through the application-cancel path.

## 7.1 Feature-branch implementation progress

Branch: `phase-b-contract-cancel`

Implemented in repository code, but not yet migrated, merged, deployed, or database-tested:

- CS-0 baseline reconciliation SQL;
- CS-1 immutable `first_payment_at`, payment insert lock, and hard-delete prevention;
- CS-2 Phase A payment-lock and application-cancel alignment;
- CS-3 duplicate cancellation, lifecycle, payment, and collection guards;
- CS-4 dedicated atomic contract-cancel executor and exact Approval Engine dispatch;
- contract-detail cancellation request UI;
- application UI alignment;
- cancelled lifecycle filters in collections, dashboard, and reports;
- generated Supabase type for `first_payment_at`.

Remaining gates:

- CS-0 executed; two payment-without-cash anomalies recorded and classified;
- CS-1 verified successfully across column, backfill, privilege, trigger, and function gates;
- CS-2 applied successfully and row-count baseline remained unchanged;
- CS-2 system-catalog/function verification is blocked by recurring Lovable Database Query HTTP 504;
- restore query access and prove CS-2 function behavior before applying CS-3;
- run Phase A and contract-cancel regression suites;
- verify Lovable build and Supabase `.from()`/`.rpc()`/RLS/Proxy behavior;
- review diff and evidence before any merge to `main` or deployment.

## 8. Explicitly not authorized

This plan does not authorize:

- implementation of any change set;
- creation or execution of migrations;
- mutation or repair of demo/production data;
- Lovable deployment;
- production cutover;
- `payment_void` implementation;
- `restructure` design or implementation;
- permission redesign outside the exact financial-evidence guards;
- vehicle return, payout recovery, or automatic blacklist behavior.

## 9. Approval boundary

The next permissible action is to resolve Gates U1–U4 and approve the exact first implementation slice.

Implementation has started only on the isolated feature branch. The next operational action is CS-0 execution against the demo database. No merge to `main`, migration execution, Lovable deployment, or production cutover is authorized by this document.


## 10. Contract Detail Hook-ordering Impact Review — 2026-08-23

### Scope and evidence

- **Repository/branch:** `superchoice-ai/tansub` / `phase-b-contract-cancel`.
- **Target environment:** Lovable Demo Preview only; `main`, deployment, and PROD are excluded.
- **Observed regression:** authenticated navigation to `/_authenticated/contracts/$contractId` failed with `Rendered more hooks than during the previous render`.
- **Confirmed cause:** `useMutation()` was declared after the loading and missing-contract early returns. The first render skipped that Hook; a later data render called it, changing Hook order.

### Dependency and consumer trace

- Direct file: `src/routes/_authenticated/contracts/$contractId.tsx`.
- Direct consumers: contract-list detail links, contract detail loading/not-found states, cancellation request dialog, React Query caches `contract` and `approvals`.
- Data/API path retained unchanged: read-only selects from `contracts`, `installments`, `payments`, `approval_requests`, and `audit_logs`; cancellation producer inserts only `approval_requests`.
- Explicitly unaffected: Approval Engine/executor, Supabase migrations/RLS/proxy/client, payment-void page, application workflow, reports, printing content, and all business eligibility rules.

### Risks and invariants

- The fix must not allow a mutation while contract data is absent.
- Loading and not-found renders must remain valid.
- Paid contracts must continue hiding the cancellation action.
- Eligible `active`/`overdue` contracts with no payment evidence and no pending request may show the action.
- Pending/rejected requests must not mutate contract, application, installment, payment, cash, or audit business data.

### Approved minimal implementation

Declare the contract value before early returns, declare `useMutation()` unconditionally, and add a mutation-function guard that rejects when the contract is unavailable. Remove the later duplicate contract declaration. No other behavior or file is changed.

### Validation and rollback

- Build/lint validation where available.
- Lovable authenticated regression: loading/detail page renders without Hook error; paid contract detail opens and has no cancel action; Payment and Approval pages still load.
- Eligible/pending behavioral cases require an isolated authorized fixture; existing Demo contracts must not be changed to manufacture eligibility.
- Rollback: revert only the atomic Hook-ordering code commit on `phase-b-contract-cancel`.
- Acceptance remains fail-closed: no merge/deploy until the full Phase B regression gate passes.
