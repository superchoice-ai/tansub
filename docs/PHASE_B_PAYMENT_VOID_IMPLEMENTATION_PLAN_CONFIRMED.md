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
