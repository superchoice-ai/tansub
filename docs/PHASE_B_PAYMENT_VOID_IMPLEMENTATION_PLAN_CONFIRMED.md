# Phase B — payment_void implementation plan (confirmed)

## Scope

- Repository: `superchoice-ai/tansub`
- Target branch: `phase-b-contract-cancel`
- Environment: Demo/UAT only; not production
- Workflow: `payment_void`
- Excluded: `restructure`; production deployment; permission redesign

## Confirmed business rules

1. Only the latest Payment of a contract may be voided.
2. “Latest” is ordered by `payments.created_at DESC, payments.id DESC`.
3. The Void approval must complete on the same Asia/Bangkok calendar date as
   `payments.created_at`. A later-day Void is prohibited because it affects the
   accounting period.
4. Staff normally records one receipt per regular installment. The system does
   not add other business eligibility gates.
5. Pending and rejected requests do not mutate Payment, installment, contract,
   cashbook, report, or collection data.
6. Approved Void reflects all related data in one database transaction and
   preserves the original rows as history.

## Implementation impact

### Database

- Add Payment void evidence: `voided_at`, `voided_by`, `void_reason`, and
  `void_approval_id`.
- Store an immutable `allocation_snapshot` on every new Payment so a receipt
  that covered multiple installments can be reversed exactly. This is audit
  evidence, not an additional business eligibility rule.
- Prevent more than one pending `payment_void` request for the same Payment.
- Validate latest-payment and same-Bangkok-day rules both when requesting and
  when approving.
- Lock approval, Payment, contract, and affected installments.
- Reverse the latest receipt from its exact allocation snapshot. A narrow FIFO
  reverse fallback supports a same-day receipt created immediately before the
  migration.
- Restore contract outstanding by the Payment debt amount.
- Recalculate contract lifecycle as `active` or `overdue` from the restored
  installment schedule.
- Logically void linked `cash_entries`; preserve `cash_entry_lines` through the
  voided parent.
- Mark the Payment logically void; never physically delete it.
- Write before/after audit evidence.

### Approval Engine

- Add only the exact combination:
  `type=payment_void`, `entity_table=payments`, `operation=void`.
- Preserve the reviewed Phase A and `contract_cancel` executor as an internal
  fail-closed core.
- Unknown combinations and `restructure` remain unsupported.

### UI

- Display “ขอ Void” only on the latest Payment row for a contract.
- Display it only on the same Bangkok calendar date as `created_at`.
- Require a reason and insert only an `approval_requests` row.
- Show pending and voided states; do not modify financial rows in browser code.

## Regression gates

1. Latest Payment created today can create one pending request.
2. Earlier Payment is rejected at request time and approval time.
3. Latest Payment from a previous Bangkok date is rejected.
4. Pending request changes no financial row.
5. Rejection changes no financial row.
6. Approval voids Payment and linked cash entry exactly once.
7. Approval restores every installment amount touched by the latest receipt.
8. Contract outstanding and active/overdue lifecycle are restored.
9. Audit contains requester, approver, reason, Payment snapshot, and before/after
   contract state.
10. Duplicate request and replayed approval fail closed.
11. Forced failure rolls back Payment, cash, installment, contract, approval,
    and audit changes.
12. Existing loan approval, customer/application edit, application cancel,
    cash-entry void, and `contract_cancel` regress successfully.
13. Supabase `.from()`, `.rpc()`, Auth/session, RLS, Proxy, and Lovable build
    regress successfully before merge.

## Rollback

- Hide the UI entry point first.
- Revoke the public Approval Engine wrapper if an emergency stop is required.
- Restore the reviewed internal Phase A + `contract_cancel` executor through a
  forward migration.
- Preserve all completed Void and audit evidence; never erase financial history.

## Readiness gate

Do not apply the migration or run mutating regression fixtures while Supabase
API/JWT or Lovable Database Query is degraded. Static review and GitHub branch
work may continue. Demo apply, regression, merge, and deployment require
separate evidence at each gate.


## Permission hardening impact review — 2026-08-24

### Evidence and confirmed interpretation

- Lovable Cloud SQL Editor showed that `perform_contract_cancel(uuid)` and
  `perform_payment_void(uuid)` still granted `EXECUTE` to database role
  `anon`.
- `execute_approval_request(uuid, boolean, text)` was recreated without first
  revoking PostgreSQL's default `PUBLIC EXECUTE`, so it was also callable by
  `anon`.
- Confirmed Phase B rule: financial mutation may execute only through the
  authenticated Approval Engine after manager/approver authorization. Internal
  executor functions are never public API.
- This review does not change business eligibility, workflow meaning, UI,
  schema, data, or the exclusion of `restructure`.

### Affected objects and dependency trace

- Repository: `superchoice-ai/tansub`
- Branch: `phase-b-contract-cancel`
- Environment: Demo/UAT only
- Database functions:
  `execute_approval_request(uuid,boolean,text)`,
  `execute_approval_request_phase_a_contract_cancel(uuid,boolean,text)`,
  `perform_contract_cancel(uuid)`, and `perform_payment_void(uuid)`.
- Consumer path:
  Preview UI → authenticated RPC `execute_approval_request` → internal Phase A
  dispatcher or Phase B executor → contracts/payments/installments/cash/audit.
- Unchanged consumers: authenticated manager/approver calls to the public
  Approval Engine wrapper.

### Risks and controls

- Existing risk: an anonymous caller that obtained a pending approval UUID could
  call a SECURITY DEFINER internal executor and bypass the approver check.
- Compatibility risk: revoking the wrong function could stop the authenticated
  Approval UI.
- Control: use a forward-only migration; revoke `PUBLIC` and `anon` from the
  wrapper and internal functions; grant only the wrapper to `authenticated`;
  leave internal calls available to their SECURITY DEFINER owner.
- No table row, fixture, enum, trigger, RLS policy, proxy, Auth configuration, or
  production environment is modified by the migration.

### Regression and acceptance

1. ACL assertion: wrapper executable by `authenticated`, not `anon` or
   `PUBLIC`.
2. ACL assertion: both internal executors and the preserved Phase A core are not
   executable by `authenticated`, `anon`, or `PUBLIC`.
3. Wrapper definition still requires `auth.uid()` and manager/approver role.
4. Existing 12 PB-TEST behavioral assertions remain true.
5. Preview continues to display only latest-payment Void evidence and hides
   installments for cancelled contracts.
6. No merge/deploy while the external readiness gate is degraded.

### Rollback

Use a reviewed forward migration that restores only the prior grants. Do not
rewrite migration history. Emergency UI rollback is to hide Phase B entry
points while preserving all financial and audit evidence.
