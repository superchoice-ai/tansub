# Design 2 — Dashboard Loan Wizard Impact Review

Date: 2026-08-28 (Asia/Bangkok)
Repository: `superchoice-ai/tansub`
Branch: `dev-design-2-wizard`
Target: branch-only development; no merge, publish, deploy, schema change, RLS change, RPC change, or production-data write authorized.

## Requested change and confirmed interpretation

- Add Design 2 as a 4-step Wizard UI matching the supplied mockups.
- Entry point is only the Dashboard button **สร้างคำขอสินเชื่อ**.
- The button opens a modal/dialog over Dashboard; it does not navigate to `/applications` first.
- Step 1 supports selecting an existing customer or entering a new customer.
- Step 2 contains vehicle and guarantor data.
- Step 3 contains the existing loan-condition fields and existing latest-setting/LTV rules.
- Step 4 reviews the accumulated form state and shows the existing mandatory confirmation before the first database save.
- Back/Next only changes local form state; it must not insert vehicle/application rows.
- Closing and reopening the Wizard resets the Wizard state.

## Existing behavior verified and protected

Creation actions on the primary operational pages use dialogs rather than separate creation routes:

- Customer: `src/routes/_authenticated/customers/index.tsx` uses `setOpen(true)` + `Dialog` for **เพิ่มลูกค้าใหม่**.
- Loan application: `src/routes/_authenticated/applications/index.tsx` uses `openCreate()` + `Dialog` for **สร้างคำขอใหม่**.
- Contract: `src/routes/_authenticated/contracts/index.tsx` uses `setOpen(true)` + `Dialog` for **ทำสัญญาใหม่**.

The sidebar itself still navigates among first-level list routes (`/customers`, `/applications`, `/contracts`, etc.); this change does not alter sidebar routing.

The existing application persistence sequence is preserved after customer resolution:

1. insert `vehicles`
2. call `next_doc_no(..., 'APP')`
3. insert `loan_applications`
4. insert `loan_guarantors` when a guarantor exists

The existing execution-time loan-default refresh and latest LTV validation are retained before persistence.

## Affected code

Direct changes:

- `src/components/LoanApplicationWizard.tsx` — new isolated Wizard wrapper.
- `src/routes/_authenticated/dashboard.tsx` — Dashboard button now opens the Wizard and renders it.

Read/reused behavior only; not modified:

- `src/routes/_authenticated/applications/index.tsx`
- `src/routes/_authenticated/customers/index.tsx`
- `src/routes/_authenticated/contracts/index.tsx`
- `src/components/SearchableCombobox.tsx`
- `src/lib/loan.ts`
- `src/lib/format.ts`
- `src/lib/labels.ts`

## Database / API / security impact

No schema, migration, RLS, RPC, permission, environment, secret, or integration changes.

Existing database objects touched at runtime by the Wizard:

- `customers`
- `vehicles`
- `loan_applications`
- `loan_guarantors`
- `system_settings`
- RPC `next_doc_no`
- RPC `global_customer_history_search`

The Wizard relies on the current authenticated Supabase client and current RLS. It does not weaken cross-branch visibility. Existing customer selection is scoped by the current branch filter in the same manner as current operational selectors; the global history mini-report continues to use the existing narrow RPC.

## Data-integrity rules

- No vehicle/application write occurs on Step 1 → 2, Step 2 → 3, or Step 3 → 4.
- For a new customer, customer creation is also deferred until final confirmation so the Step 4 confirmation remains before the first database save.
- New-customer validation reuses the current customer validation rules.
- Existing application defaults are refreshed from DB again at final execution time.
- Application vehicle/application/guarantor mutation sequence is unchanged.
- Closing the modal clears accumulated Wizard data.

## Readiness evidence

Official provider status checked on 2026-08-28:

- GitHub: operational for Git/API path used.
- Lovable: fully operational.
- Supabase: provider status showed degraded/partial conditions for some components/incidents; therefore no production mutation or runtime UAT was performed as part of this branch development.

Read-only project-path probes:

- GitHub branch reads/writes succeeded on `dev-design-2-wizard`.
- Lovable could read the newly committed Wizard and Dashboard files from ref `dev-design-2-wizard`, confirming branch sync visibility.
- Lovable/Supabase read-only `SELECT now()` succeeded at `2026-08-28 04:35:54.993364+00`.
- `information_schema` read confirmed the expected customer, vehicle, application, and guarantor columns used by the Wizard exist.

Decision: **LIMITED GO** for isolated branch code development and read-only validation. No deploy/merge/production write.

## Regression risks and test plan

1. Dashboard regression
   - Dashboard still loads all existing metrics/charts.
   - **ดูรายงาน** behavior remains unchanged.
   - **สร้างคำขอสินเชื่อ** opens the Wizard without changing route.

2. Wizard state
   - opens on Step 1;
   - Back/Next do not save rows;
   - validation blocks invalid step transitions;
   - close/reopen resets state;
   - existing/new customer switching does not leak stale values.

3. Existing customer flow
   - type-ahead selection works;
   - current branch scoping remains intact;
   - global-history RPC still returns the mini-report without changing RLS.

4. New customer flow
   - current customer validation is applied;
   - no customer row is inserted before final confirmation.

5. Vehicle/loan flow
   - vehicle fields and guarantor map to the same existing tables/fields;
   - latest DB defaults are re-read on final save;
   - term and LTV checks use latest values;
   - persistence order stays vehicle → APP number → application → guarantor.

6. Existing primary pages
   - customer create dialog unchanged;
   - application list/create dialog unchanged;
   - contract create dialog unchanged;
   - sidebar routing unchanged.

## Rollback

Branch-only rollback is limited to reverting the commits that add `LoanApplicationWizard.tsx` and alter `dashboard.tsx`. No database rollback is required because this change introduces no schema/data migration and no production data was written during implementation.

## Acceptance / post-change evidence required before merge

- successful TypeScript/build check;
- browser smoke test of all four Wizard steps;
- read-only verification that Dashboard does not route to `/applications` when opening the Wizard;
- regression smoke test for customer/application/contract creation dialogs;
- controlled final-save test in an authorized non-production/demo environment, confirming row creation order and no intermediate writes;
- clean diff review showing no unrelated files, schema, RLS, RPC, environment, or production changes.
