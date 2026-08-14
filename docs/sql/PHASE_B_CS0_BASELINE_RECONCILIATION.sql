-- Phase B CS-0: read-only baseline and reconciliation evidence.
-- Run against the DEMO database before applying CS-1. Do not mutate data.

-- 1. Contract lifecycle and current payment marker readiness.
SELECT status, count(*) AS contracts
FROM public.contracts
GROUP BY status
ORDER BY status;

-- 2. Every payment event counts, including voided rows.
SELECT
  c.id AS contract_id,
  c.code,
  c.status,
  count(p.id) AS payment_event_count,
  min(p.created_at) AS first_payment_recorded_at,
  count(*) FILTER (WHERE p.voided) AS voided_payment_count
FROM public.contracts c
LEFT JOIN public.payments p ON p.contract_id = c.id
GROUP BY c.id, c.code, c.status
ORDER BY c.code;

-- 3. Payment/cash-entry linkage inconsistencies.
SELECT p.id, p.contract_id, p.receipt_no, p.voided
FROM public.payments p
LEFT JOIN public.cash_entries ce ON ce.payment_id = p.id
WHERE ce.id IS NULL
ORDER BY p.created_at;

SELECT ce.id, ce.contract_id, ce.payment_id, ce.doc_no, ce.voided
FROM public.cash_entries ce
LEFT JOIN public.payments p ON p.id = ce.payment_id
WHERE ce.payment_id IS NOT NULL
  AND p.id IS NULL
ORDER BY ce.created_at;

SELECT ce.id, ce.payment_id, ce.contract_id AS cash_contract_id, p.contract_id AS payment_contract_id
FROM public.cash_entries ce
JOIN public.payments p ON p.id = ce.payment_id
WHERE ce.contract_id IS DISTINCT FROM p.contract_id;

-- 4. Closed contracts must remain completed, not cancelled.
SELECT c.id, c.code, c.status AS contract_status, la.id AS application_id, la.code AS application_code, la.status AS application_status
FROM public.contracts c
JOIN public.loan_applications la ON la.id = c.application_id
WHERE c.status = 'closed'
ORDER BY c.code;

-- 5. Duplicate pending cancellation candidates.
SELECT entity_id, count(*) AS pending_requests
FROM public.approval_requests
WHERE type = 'contract_cancel'
  AND entity_table = 'contracts'
  AND status = 'pending'
GROUP BY entity_id
HAVING count(*) > 1;

-- 6. Current active-debt and overdue baselines.
SELECT
  count(*) AS collectible_contracts,
  coalesce(sum(outstanding), 0) AS outstanding
FROM public.contracts
WHERE status IN ('active', 'overdue');

SELECT
  count(*) AS overdue_installments,
  coalesce(sum(i.total_amount - i.paid_amount), 0) AS overdue_amount
FROM public.installments i
JOIN public.contracts c ON c.id = i.contract_id
WHERE c.status IN ('active', 'overdue')
  AND i.due_date < current_date
  AND i.status IN ('unpaid', 'partial', 'overdue');
