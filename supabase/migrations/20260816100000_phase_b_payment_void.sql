-- Phase B: payment_void.
-- Confirmed business rule:
--   1. The target must be the latest payment row for its contract by
--      (created_at DESC, id DESC).
--   2. Approval must complete on the same Asia/Bangkok calendar date as
--      payments.created_at. A later-day void is prohibited.
-- Pending/rejected requests never mutate financial data.

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS allocation_snapshot jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS voided_at timestamptz,
  ADD COLUMN IF NOT EXISTS voided_by uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS void_reason text,
  ADD COLUMN IF NOT EXISTS void_approval_id uuid REFERENCES public.approval_requests(id);

CREATE UNIQUE INDEX IF NOT EXISTS approval_requests_one_pending_payment_void
  ON public.approval_requests (entity_id)
  WHERE type = 'payment_void'
    AND entity_table = 'payments'
    AND status = 'pending';

CREATE OR REPLACE FUNCTION public.guard_payment_void_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target public.payments%ROWTYPE;
  latest_payment_id uuid;
BEGIN
  IF NEW.type <> 'payment_void' THEN
    RETURN NEW;
  END IF;

  IF NEW.entity_table <> 'payments'
     OR coalesce(NEW.payload ->> 'operation', '') <> 'void'
     OR NEW.entity_id IS NULL THEN
    RAISE EXCEPTION 'รูปแบบคำขอ Void Payment ไม่ถูกต้อง';
  END IF;

  SELECT * INTO target
  FROM public.payments
  WHERE id = NEW.entity_id
  FOR UPDATE;

  IF NOT FOUND OR target.branch_id <> NEW.branch_id THEN
    RAISE EXCEPTION 'ไม่พบ Payment ในสาขาของคำขอ';
  END IF;

  IF target.voided THEN
    RAISE EXCEPTION 'Payment นี้ถูก Void แล้ว';
  END IF;

  SELECT p.id INTO latest_payment_id
  FROM public.payments p
  WHERE p.contract_id = target.contract_id
  ORDER BY p.created_at DESC, p.id DESC
  LIMIT 1;

  IF latest_payment_id IS DISTINCT FROM target.id THEN
    RAISE EXCEPTION 'Void ได้เฉพาะ Payment ล่าสุดของสัญญาเท่านั้น';
  END IF;

  IF (target.created_at AT TIME ZONE 'Asia/Bangkok')::date
     <> (clock_timestamp() AT TIME ZONE 'Asia/Bangkok')::date THEN
    RAISE EXCEPTION 'Payment ข้ามวันแล้ว ไม่สามารถ Void ได้';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS approval_requests_guard_payment_void
  ON public.approval_requests;
CREATE TRIGGER approval_requests_guard_payment_void
BEFORE INSERT ON public.approval_requests
FOR EACH ROW
EXECUTE FUNCTION public.guard_payment_void_request();

CREATE OR REPLACE FUNCTION public.perform_payment_void(_approval_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req public.approval_requests%ROWTYPE;
  target public.payments%ROWTYPE;
  target_contract public.contracts%ROWTYPE;
  latest_payment_id uuid;
  installment_row public.installments%ROWTYPE;
  allocation_item jsonb;
  remaining bigint;
  reversed bigint;
  new_paid bigint;
  cash_rows int;
  next_status public.contract_status;
BEGIN
  SELECT * INTO req
  FROM public.approval_requests
  WHERE id = _approval_id
  FOR UPDATE;

  IF NOT FOUND OR req.status <> 'pending' THEN
    RAISE EXCEPTION 'ไม่พบคำขอ Void ที่รออนุมัติ';
  END IF;

  IF req.type <> 'payment_void'
     OR req.entity_table <> 'payments'
     OR coalesce(req.payload ->> 'operation', '') <> 'void'
     OR req.entity_id IS NULL THEN
    RAISE EXCEPTION 'รูปแบบคำขอ Void Payment ไม่ถูกต้อง';
  END IF;

  SELECT * INTO target
  FROM public.payments
  WHERE id = req.entity_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่พบ Payment ที่ต้องการ Void';
  END IF;

  IF target.branch_id <> req.branch_id THEN
    RAISE EXCEPTION 'สาขาของคำขอไม่ตรงกับ Payment';
  END IF;

  IF target.voided THEN
    RAISE EXCEPTION 'Payment นี้ถูก Void แล้ว';
  END IF;

  SELECT p.id INTO latest_payment_id
  FROM public.payments p
  WHERE p.contract_id = target.contract_id
  ORDER BY p.created_at DESC, p.id DESC
  LIMIT 1;

  IF latest_payment_id IS DISTINCT FROM target.id THEN
    RAISE EXCEPTION 'Void ได้เฉพาะ Payment ล่าสุดของสัญญาเท่านั้น';
  END IF;

  IF (target.created_at AT TIME ZONE 'Asia/Bangkok')::date
     <> (clock_timestamp() AT TIME ZONE 'Asia/Bangkok')::date THEN
    RAISE EXCEPTION 'Payment ข้ามวันแล้ว ไม่สามารถ Void ได้';
  END IF;

  SELECT * INTO target_contract
  FROM public.contracts
  WHERE id = target.contract_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่พบสัญญาของ Payment';
  END IF;

  -- New receipts preserve their exact per-installment before/after allocation.
  -- The fallback supports same-day receipts created immediately before this
  -- migration and follows the existing FIFO allocation in reverse.
  remaining := target.amount;

  IF jsonb_array_length(coalesce(target.allocation_snapshot, '[]'::jsonb)) > 0 THEN
    FOR allocation_item IN
      SELECT value
      FROM jsonb_array_elements(target.allocation_snapshot)
      ORDER BY (value ->> 'seq')::int DESC
    LOOP
      SELECT * INTO installment_row
      FROM public.installments
      WHERE id = (allocation_item ->> 'installment_id')::uuid
        AND contract_id = target.contract_id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'ไม่พบงวดที่ Payment เคยตัดยอด';
      END IF;

      IF installment_row.paid_amount <> (allocation_item ->> 'after_paid')::bigint THEN
        RAISE EXCEPTION 'ยอดงวดเปลี่ยนจากหลักฐานเดิม จึงไม่สามารถ Void อัตโนมัติ';
      END IF;

      reversed := (allocation_item ->> 'applied_amount')::bigint;
      new_paid := (allocation_item ->> 'before_paid')::bigint;

      UPDATE public.installments
      SET paid_amount = new_paid,
          status = (allocation_item ->> 'before_status')::public.installment_status,
          paid_date = nullif(allocation_item ->> 'before_paid_date', '')::date,
          updated_at = now()
      WHERE id = installment_row.id;

      remaining := remaining - reversed;
    END LOOP;
  ELSE
    FOR installment_row IN
      SELECT *
      FROM public.installments
      WHERE contract_id = target.contract_id
        AND paid_amount > 0
      ORDER BY seq DESC
      FOR UPDATE
    LOOP
      EXIT WHEN remaining <= 0;
      reversed := least(remaining, installment_row.paid_amount);
      new_paid := installment_row.paid_amount - reversed;

      UPDATE public.installments
      SET paid_amount = new_paid,
          status = CASE WHEN new_paid = 0 THEN 'unpaid' ELSE 'partial' END,
          paid_date = NULL,
          updated_at = now()
      WHERE id = installment_row.id;

      remaining := remaining - reversed;
    END LOOP;
  END IF;

  IF remaining <> 0 THEN
    RAISE EXCEPTION 'ยอดงวดที่ย้อนกลับไม่ตรงกับยอด Payment';
  END IF;

  next_status := CASE
    WHEN EXISTS (
      SELECT 1
      FROM public.installments i
      WHERE i.contract_id = target.contract_id
        AND i.paid_amount < i.total_amount
        AND i.due_date < (clock_timestamp() AT TIME ZONE 'Asia/Bangkok')::date
    ) THEN 'overdue'::public.contract_status
    ELSE 'active'::public.contract_status
  END;

  UPDATE public.contracts
  SET outstanding = outstanding + target.amount,
      status = next_status,
      updated_at = now()
  WHERE id = target.contract_id;

  UPDATE public.cash_entries
  SET voided = true,
      updated_at = now(),
      note = concat_ws(' | ', nullif(note, ''), 'Void Payment: ' || coalesce(req.reason, '-'))
  WHERE payment_id = target.id
    AND voided = false;
  GET DIAGNOSTICS cash_rows = ROW_COUNT;

  UPDATE public.payments
  SET voided = true,
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = req.reason,
      void_approval_id = req.id
  WHERE id = target.id
    AND voided = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่สามารถ Void Payment ได้';
  END IF;

  INSERT INTO public.audit_logs (
    branch_id, user_id, action, entity_table, entity_id, detail
  ) VALUES (
    target.branch_id,
    auth.uid(),
    'payment_void_executed',
    'payments',
    target.id,
    jsonb_build_object(
      'approval_id', req.id,
      'reason', req.reason,
      'payment_before', to_jsonb(target),
      'contract_id', target.contract_id,
      'contract_status_before', target_contract.status,
      'contract_outstanding_before', target_contract.outstanding,
      'contract_status_after', next_status,
      'contract_outstanding_after', target_contract.outstanding + target.amount,
      'cash_entries_voided', cash_rows,
      'rule', 'latest_created_at_same_bangkok_day'
    )
  );

  RETURN jsonb_build_object(
    'payment_id', target.id,
    'contract_id', target.contract_id,
    'status', 'voided',
    'cash_entries_voided', cash_rows
  );
END;
$$;

REVOKE ALL ON FUNCTION public.perform_payment_void(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.perform_payment_void(uuid) FROM authenticated;

-- Preserve the already-reviewed Phase A + contract_cancel Approval Engine as
-- an internal core, then add an exact payment_void dispatcher in front of it.
DO $$
BEGIN
  IF to_regprocedure('public.execute_approval_request_phase_a_contract_cancel(uuid,boolean,text)') IS NULL THEN
    ALTER FUNCTION public.execute_approval_request(uuid, boolean, text)
      RENAME TO execute_approval_request_phase_a_contract_cancel;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.execute_approval_request_phase_a_contract_cancel(uuid, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.execute_approval_request_phase_a_contract_cancel(uuid, boolean, text) FROM authenticated;

CREATE OR REPLACE FUNCTION public.execute_approval_request(
  _approval_id uuid,
  _approve boolean,
  _decision_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req public.approval_requests%ROWTYPE;
  actor uuid := auth.uid();
  affected_rows int;
  result jsonb;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated';
  END IF;

  IF NOT (public.is_manager() OR public.has_role(actor, 'approver')) THEN
    RAISE EXCEPTION 'ไม่มีสิทธิ์อนุมัติรายการ';
  END IF;

  SELECT * INTO req
  FROM public.approval_requests
  WHERE id = _approval_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่พบคำขออนุมัติ';
  END IF;

  IF req.status <> 'pending' THEN
    RAISE EXCEPTION 'รายการนี้ถูกพิจารณาแล้ว';
  END IF;

  IF NOT public.can_access_branch(req.branch_id) THEN
    RAISE EXCEPTION 'ไม่มีสิทธิ์ในสาขานี้';
  END IF;

  IF req.type = 'payment_void'
     AND req.entity_table = 'payments'
     AND coalesce(req.payload ->> 'operation', '') = 'void' THEN
    IF NOT _approve THEN
      UPDATE public.approval_requests
      SET status = 'rejected',
          decided_by = actor,
          decided_at = now(),
          decision_note = nullif(trim(_decision_note), '')
      WHERE id = req.id AND status = 'pending';

      GET DIAGNOSTICS affected_rows = ROW_COUNT;
      IF affected_rows <> 1 THEN
        RAISE EXCEPTION 'ไม่สามารถบันทึกผลไม่อนุมัติได้';
      END IF;

      INSERT INTO public.audit_logs (
        branch_id, user_id, action, entity_table, entity_id, detail
      ) VALUES (
        req.branch_id, actor, 'approval_rejected', 'payments', req.entity_id,
        jsonb_build_object('approval_id', req.id, 'type', req.type, 'note', _decision_note)
      );

      RETURN jsonb_build_object('ok', true, 'executed', false, 'status', 'rejected');
    END IF;

    result := public.perform_payment_void(req.id);

    UPDATE public.approval_requests
    SET status = 'approved',
        decided_by = actor,
        decided_at = now(),
        decision_note = nullif(trim(_decision_note), '')
    WHERE id = req.id AND status = 'pending';

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
      RAISE EXCEPTION 'ไม่สามารถบันทึกผลอนุมัติได้';
    END IF;

    INSERT INTO public.audit_logs (
      branch_id, user_id, action, entity_table, entity_id, detail
    ) VALUES (
      req.branch_id, actor, 'approval_executed', 'payments', req.entity_id,
      jsonb_build_object(
        'approval_id', req.id,
        'type', req.type,
        'operation', 'void',
        'result', result,
        'note', _decision_note
      )
    );

    RETURN jsonb_build_object(
      'ok', true,
      'executed', true,
      'status', 'approved',
      'operation', 'void',
      'type', 'payment_void',
      'result', result
    );
  END IF;

  -- Every existing exact combination remains handled by the reviewed core.
  RETURN public.execute_approval_request_phase_a_contract_cancel(
    _approval_id, _approve, _decision_note
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.execute_approval_request(uuid, boolean, text) TO authenticated;
