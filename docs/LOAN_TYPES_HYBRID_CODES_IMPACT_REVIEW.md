# Loan type and hybrid document code impact review

Repository: `superchoice-ai/tansub`  
Base: `main` at `0bb8a8ed7c60f471d1de6cca17e4b5829375a019`  
Branch: `feat/loan-types-hybrid-codes`  
Scope: branch code and a migration file only; no Cloud SQL execution, publishing, or merge.

## Confirmed behavior

- New APP screens offer car, motorcycle, personal, car insurance, gold and other. Existing truck rows remain readable.
- Staff enter only 1–4 Latin letters in APP. Input is normalized to uppercase. New document numbers are `APP-<branch>-<letters>-<sequence>` and `CTR-<branch>-<same letters>-<independent sequence>`.
- Only car and motorcycle require a plate and use the existing LTV setting. Other products have no vehicle row or LTV validation.
- The legacy `next_doc_no` RPC and its other document types are unchanged. Historical APP/CTR codes are unchanged.

## Dependency and impact trace

Wizard and /applications create APP; /contracts creates CTR and installments/disbursement; both route families use the same new APP fields and scoped RPC. The existing vehicle collateral print template cannot represent a nonvehicle loan, so its print button is disabled for contracts with no vehicle; no new contract language is invented. Other views use nullable vehicle joins. Existing RLS is retained. New function checks authorized branch, document type, and letter format and is callable by authenticated users only. The branch's migration does not update existing rows.

The migration must be applied in the confirmed Tansub Lovable Cloud DB **before** using the branch UI. Its BEGIN/COMMIT transaction is all-or-nothing on SQL error. Before applying, inspect the actual DB schema and current number generator; this repository is not a proof of current Cloud schema. Deployment/merge remains outside this change.

## Focused validation

- Static: lowercase to uppercase, 1–4 valid letters, reject blank/number/non-Latin/overlong; car/motorcycle classification retained.
- After migration, use newly created test data only: create nonvehicle APP via each entry screen without plate or appraisal; verify letter/branch sequence; approve APP; create CTR and verify letter inheritance and no book-received update; verify the car-only print template is unavailable.
- Verify branch isolation and invalid RPC document type/letter rejection. Check old car rules by source review; if changed shared code can affect them, perform a narrowly scoped check of plate and LTV enforcement.
- Do not delete test data without explicit owner approval; any later cleanup must be child → root in one transaction.

## Gate and rollback

Local `npm ci` fails because the existing lockfile disagrees with package versions. A temporary, uncommitted `npm install --package-lock=false` allowed `npx tsc --noEmit` and `npm run build` to run. Full typecheck fails on repository-wide existing errors; Build stops at missing `index.html` in the GitHub tree. No full passing quality gate is claimed. Do not merge into main or publish while these are unresolved without a new explicit owner decision.

If SQL execution fails, run ROLLBACK in the same session and verify the two columns/function were not persisted. If applied successfully, disable new UI consumers first; leave populated application fields and document counters intact for audit, and plan a reviewed compensating migration rather than dropping business history.
