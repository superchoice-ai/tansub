-- Phase B permission hardening.
-- Impact review: docs/PHASE_B_PAYMENT_VOID_IMPLEMENTATION_PLAN_CONFIRMED.md
--
-- The Approval Engine wrapper is the only client-callable mutation entry point.
-- Internal SECURITY DEFINER executors must never be callable by PUBLIC, anon,
-- or authenticated. PostgreSQL function owners retain the ability to call the
-- internal functions from the reviewed wrapper.

REVOKE ALL ON FUNCTION public.execute_approval_request(uuid, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.execute_approval_request(uuid, boolean, text)
  TO authenticated;

REVOKE ALL ON FUNCTION public.execute_approval_request_phase_a_contract_cancel(uuid, boolean, text)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.perform_contract_cancel(uuid)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.perform_payment_void(uuid)
  FROM PUBLIC, anon, authenticated;
