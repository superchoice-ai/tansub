-- Run in the confirmed Tansub Lovable Cloud database before using the branch UI.
-- One transaction: any failing statement aborts the entire migration; execute ROLLBACK if the SQL editor remains in an aborted transaction.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.loan_applications') IS NULL
     OR to_regclass('public.contracts') IS NULL
     OR to_regclass('public.vehicles') IS NULL
     OR to_regclass('public.doc_counters') IS NULL
     OR to_regclass('public.branches') IS NULL THEN
    RAISE EXCEPTION 'Tansub schema incomplete: no changes applied';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'loan_applications'
      AND column_name = 'vehicle_id' AND is_nullable = 'YES'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'contracts'
      AND column_name = 'vehicle_id' AND is_nullable = 'YES'
  ) THEN
    RAISE EXCEPTION 'Vehicle references must be nullable for non-vehicle loans';
  END IF;
  IF to_regprocedure('public.can_access_branch(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Branch authorization helper is missing';
  END IF;
END
$preflight$;

ALTER TABLE public.loan_applications
  ADD COLUMN IF NOT EXISTS loan_type text,
  ADD COLUMN IF NOT EXISTS subtype_code text;

DO $constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.loan_applications'::regclass
      AND conname = 'loan_applications_loan_type_check'
  ) THEN
    ALTER TABLE public.loan_applications
      ADD CONSTRAINT loan_applications_loan_type_check
      CHECK (loan_type IS NULL OR loan_type IN
        ('car', 'motorcycle', 'personal', 'car_insurance', 'gold', 'other'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.loan_applications'::regclass
      AND conname = 'loan_applications_subtype_code_check'
  ) THEN
    ALTER TABLE public.loan_applications
      ADD CONSTRAINT loan_applications_subtype_code_check
      CHECK (subtype_code IS NULL OR subtype_code ~ '^[A-Z]{1,4}$');
  END IF;
END
$constraints$;

-- Do not alter next_doc_no: customer, cash, receipt and other numbers keep their existing format.
-- APP/CTR share their respective branch-wide sequence across all staff-entered letter codes.
-- 'ALL' avoids reusing document numbers when the month changes and the new format has no month.
CREATE OR REPLACE FUNCTION public.next_loan_doc_no(
  _branch uuid, _doc_type text, _user_code text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  bcode text;
  letters text;
  baseline integer;
  n integer;
BEGIN
  IF _branch IS NULL OR NOT public.can_access_branch(_branch) THEN
    RAISE EXCEPTION 'ไม่มีสิทธิ์ในสาขานี้';
  END IF;
  IF _doc_type IS NULL OR _doc_type NOT IN ('APP', 'CTR') THEN
    RAISE EXCEPTION 'เลขเอกสารชนิดนี้ไม่รองรับ';
  END IF;
  letters := upper(btrim(_user_code));
  IF letters IS NULL OR letters !~ '^[A-Z]{1,4}$' THEN
    RAISE EXCEPTION 'อักษรหมวดย่อยต้องเป็น A-Z จำนวน 1-4 ตัว';
  END IF;
  SELECT code INTO bcode FROM public.branches WHERE id = _branch;
  IF bcode IS NULL THEN
    RAISE EXCEPTION 'ไม่พบสาขา';
  END IF;

  -- Start after the greatest historical suffix in this branch, including legacy codes.
  IF _doc_type = 'APP' THEN
    SELECT COALESCE(max((regexp_match(code, '-([0-9]+)$'))[1]::integer), 0)
      INTO baseline FROM public.loan_applications WHERE branch_id = _branch;
  ELSE
    SELECT COALESCE(max((regexp_match(code, '-([0-9]+)$'))[1]::integer), 0)
      INTO baseline FROM public.contracts WHERE branch_id = _branch;
  END IF;
  INSERT INTO public.doc_counters (branch_id, doc_type, period, last_no)
  VALUES (_branch, _doc_type, 'ALL', baseline + 1)
  ON CONFLICT (branch_id, doc_type, period) DO UPDATE
    SET last_no = greatest(public.doc_counters.last_no, excluded.last_no - 1) + 1
  RETURNING last_no INTO n;

  RETURN _doc_type || '-' || bcode || '-' || letters || '-' || lpad(n::text, 4, '0');
END
$function$;

REVOKE ALL ON FUNCTION public.next_loan_doc_no(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.next_loan_doc_no(uuid, text, text) TO authenticated;

DO $verify$
BEGIN
  IF to_regprocedure('public.next_loan_doc_no(uuid,text,text)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'loan_applications'
         AND column_name = 'loan_type'
     )
     OR NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'loan_applications'
         AND column_name = 'subtype_code'
     )
     OR NOT has_function_privilege('authenticated',
          'public.next_loan_doc_no(uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Loan migration verification failed; transaction will roll back';
  END IF;
END
$verify$;

COMMIT;

-- Read-only checks after COMMIT:
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'loan_applications'
--   AND column_name IN ('loan_type', 'subtype_code');
-- SELECT to_regprocedure('public.next_loan_doc_no(uuid,text,text)') AS generator;
-- SELECT branch_id, doc_type, period, last_no FROM public.doc_counters WHERE period = 'ALL';
-- No existing application or contract rows are updated by this migration.
