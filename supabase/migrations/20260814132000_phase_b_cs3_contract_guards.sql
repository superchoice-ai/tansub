-- Phase B CS-3: lifecycle, duplicate-request, and direct-write guards.

CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_contract_cancel_per_contract
ON public.approval_requests(entity_id)
WHERE type = 'contract_cancel'
  AND entity_table = 'contracts'
  AND status = 'pending';

CREATE OR REPLACE FUNCTION public.guard_collection_contract_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  contract_state public.contract_status;
BEGIN
  SELECT status
  INTO contract_state
  FROM public.contracts
  WHERE id = NEW.contract_id
  FOR KEY SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่พบสัญญาสำหรับการติดตามหนี้';
  END IF;

  IF contract_state NOT IN ('active', 'overdue') THEN
    RAISE EXCEPTION 'สถานะสัญญานี้ไม่อนุญาตให้สร้างงานติดตามหนี้ใหม่';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_collection_contract_lifecycle ON public.collection_activities;
CREATE TRIGGER trg_collection_contract_lifecycle
BEFORE INSERT ON public.collection_activities
FOR EACH ROW
EXECUTE FUNCTION public.guard_collection_contract_lifecycle();

-- Prevent a cancellation request from targeting an invalid lifecycle or a
-- contract that already has permanent payment evidence. Approval-time checks
-- remain mandatory because state can change while the request is pending.
CREATE OR REPLACE FUNCTION public.guard_contract_cancel_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target public.contracts%ROWTYPE;
BEGIN
  IF NEW.type <> 'contract_cancel' THEN
    RETURN NEW;
  END IF;

  IF NEW.entity_table <> 'contracts' OR NEW.entity_id IS NULL THEN
    RAISE EXCEPTION 'คำขอยกเลิกสัญญาต้องระบุสัญญาให้ถูกต้อง';
  END IF;

  IF coalesce(nullif(trim(NEW.reason), ''), '') = '' THEN
    RAISE EXCEPTION 'กรุณาระบุเหตุผลการยกเลิกสัญญา';
  END IF;

  SELECT *
  INTO target
  FROM public.contracts
  WHERE id = NEW.entity_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่พบสัญญาที่ต้องการยกเลิก';
  END IF;

  IF target.branch_id <> NEW.branch_id THEN
    RAISE EXCEPTION 'สาขาของคำขอไม่ตรงกับสัญญา';
  END IF;

  IF target.status NOT IN ('active', 'overdue') THEN
    RAISE EXCEPTION 'ยกเลิกได้เฉพาะสัญญา active หรือ overdue';
  END IF;

  IF target.first_payment_at IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM public.payments p WHERE p.contract_id = target.id
     ) THEN
    RAISE EXCEPTION 'สัญญานี้เคยรับชำระแล้ว จึงไม่สามารถยกเลิกได้';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_contract_cancel_request ON public.approval_requests;
CREATE TRIGGER trg_guard_contract_cancel_request
BEFORE INSERT ON public.approval_requests
FOR EACH ROW
EXECUTE FUNCTION public.guard_contract_cancel_request();
