-- Phase B CS-1: immutable payment-event evidence.
-- Confirmed rule: the first recorded payment event permanently locks
-- debt-bearing edits and contract cancellation, including after payment void.

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS first_payment_at timestamptz;

COMMENT ON COLUMN public.contracts.first_payment_at IS
  'Immutable database-recorded evidence that at least one payment row has existed; never cleared by payment void.';

-- Existing rows: count every payment, including voided rows.
UPDATE public.contracts c
SET first_payment_at = evidence.first_recorded_at
FROM (
  SELECT contract_id, min(created_at) AS first_recorded_at
  FROM public.payments
  GROUP BY contract_id
) evidence
WHERE evidence.contract_id = c.id
  AND c.first_payment_at IS NULL;

CREATE OR REPLACE FUNCTION public.guard_contract_first_payment_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.first_payment_at IS NOT NULL
     AND NEW.first_payment_at IS DISTINCT FROM OLD.first_payment_at THEN
    RAISE EXCEPTION 'หลักฐานการรับชำระครั้งแรกไม่สามารถแก้ไขหรือล้างได้';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_contract_first_payment_immutable ON public.contracts;
CREATE TRIGGER trg_contract_first_payment_immutable
BEFORE UPDATE OF first_payment_at ON public.contracts
FOR EACH ROW
EXECUTE FUNCTION public.guard_contract_first_payment_at();

CREATE OR REPLACE FUNCTION public.mark_contract_payment_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  contract_state public.contract_status;
BEGIN
  -- Payment and cancellation coordinate through the same contract-row lock.
  SELECT status
  INTO contract_state
  FROM public.contracts
  WHERE id = NEW.contract_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่พบสัญญาสำหรับรายการรับชำระ';
  END IF;

  IF contract_state = 'cancelled' THEN
    RAISE EXCEPTION 'สัญญาถูกยกเลิกแล้ว ไม่สามารถรับชำระได้';
  END IF;

  UPDATE public.contracts
  SET first_payment_at = coalesce(first_payment_at, clock_timestamp())
  WHERE id = NEW.contract_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_marks_contract_history ON public.payments;
CREATE TRIGGER trg_payment_marks_contract_history
BEFORE INSERT ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.mark_contract_payment_event();

CREATE OR REPLACE FUNCTION public.prevent_payment_physical_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'ห้ามลบรายการรับชำระแบบถาวร ต้องใช้ workflow payment_void ที่ได้รับอนุมัติ';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_payment_physical_delete ON public.payments;
CREATE TRIGGER trg_prevent_payment_physical_delete
BEFORE DELETE ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.prevent_payment_physical_delete();

DROP POLICY IF EXISTS "pay manager delete" ON public.payments;
REVOKE DELETE ON public.payments FROM authenticated;

CREATE INDEX IF NOT EXISTS idx_contracts_first_payment_at
  ON public.contracts(first_payment_at)
  WHERE first_payment_at IS NOT NULL;

-- Migration must fail closed if backfill did not mark any preserved payment.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.payments p
    JOIN public.contracts c ON c.id = p.contract_id
    WHERE c.first_payment_at IS NULL
  ) THEN
    RAISE EXCEPTION 'CS-1 reconciliation failed: payment exists without first_payment_at';
  END IF;
END;
$$;
