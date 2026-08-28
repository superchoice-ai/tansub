# Customer identity duplicate protection — impact review

## Confirmed scope

User-facing duplicate validation for `national_id` and `phone` is limited to:

1. Dashboard loan wizard when creating a new customer.
2. Customer screen when creating a customer or requesting an edit to an existing customer.

The database uniqueness indexes are a concurrency/data-integrity backstop, not a new UI flow.

## Identity rules

- National ID comparison: digits only, global across `public.customers`.
- Phone comparison: digits only, global across `public.customers`.
- A duplicate in either field blocks the write.
- Existing-customer edit checks exclude the current customer's own `id`.
- No automatic merge, delete, or mutation of an existing duplicate is allowed.

## Database impact

Migration `20260828123000_customer_identity_uniqueness.sql`:

- fails closed if pre-existing normalized duplicates exist;
- adds global normalized partial unique indexes for national ID and phone;
- adds authenticated-only `SECURITY DEFINER` RPC `check_customer_identity_duplicate` so the two approved UIs can perform an exact global check without weakening ordinary branch RLS;
- returns only conflict field, customer id/code/name;
- revokes PUBLIC/anon execution.

Read-only precheck on 2026-08-28 found 37 customer rows, no blank identity fields, and no duplicate normalized national IDs or phones.

## Existing consumers / non-impact

- `legacy_customers` import remains separate and unchanged.
- Application, contract, payment, collection, reporting, numbering, RLS and global-history flows are unchanged.
- Wizard application save sequence remains unchanged.
- Step 3 still auto-refreshes loan defaults when the modal opens and keeps the manual `โหลดค่าล่าสุด` button.

## Approval executor

Customer edits are still requested through the existing approval flow. The Customer UI checks duplicates before creating an edit approval request and excludes the edited customer's own id. The database unique indexes remain the final race-condition guard when an approved edit executes. A conflicting approved edit must fail rather than corrupt customer-master uniqueness.

## Regression plan

### Wizard

- Dashboard button opens modal; no route navigation.
- Existing customer can continue without duplicate check.
- New customer with unique national ID + phone can continue/save.
- Duplicate national ID blocks customer creation.
- Duplicate phone blocks customer creation.
- Step 2/3/4 behavior and back/next state remain unchanged.
- Step 3 auto refresh + manual refresh remain available.
- Final save preserves existing vehicle → APP number → application → guarantor sequence.

### Customer

- Unique customer creation succeeds.
- Duplicate national ID creation is blocked.
- Duplicate phone creation is blocked.
- Edit with unchanged national ID/phone is accepted for approval because self id is excluded.
- Edit to another customer's national ID is blocked.
- Edit to another customer's phone is blocked.
- Deactivate request is unaffected.

### Database

- Migration refuses to create indexes when pre-existing duplicates exist.
- Concurrent inserts/updates cannot create duplicate normalized national ID or phone.
- RPC is unavailable to anon/public and available to authenticated users only.

## Rollback

Code rollback: revert the UI/helper commits.

Database rollback, only with owner approval:

```sql
DROP FUNCTION IF EXISTS public.check_customer_identity_duplicate(text,text,uuid);
DROP INDEX IF EXISTS public.customers_national_id_normalized_uidx;
DROP INDEX IF EXISTS public.customers_phone_normalized_uidx;
```

Dropping the indexes removes the integrity guarantee, so it should not be done as a routine UI rollback.
