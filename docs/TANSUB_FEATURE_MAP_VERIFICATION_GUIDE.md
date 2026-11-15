# Tansub Feature Map & Verification Guide

Production: https://tansub.lovable.app · Preview (Dev/QA): https://preview--tansub.lovable.app
Format follows the Cursor pstack feature-map contract: every feature has exactly four H2 sections.
Last synced with `main`: 6adefae (2026-11-15). Update this file after every commit merged to `main` (see AGENTS.md → Feature Map Synchronization Gate).

---

# Feature 1 — Authentication, Roles & Branch Scope

## Sub-features
- `email-login` — Email/password sign in at `/auth`.
- `line-login` — LINE Login via `/api/public/auth/line/start` → `/api/public/auth/line/callback`.
- `roles` — `admin`, `manager`, `staff` stored in `public.user_roles` (never in profile metadata).
- `branch-scope` — `public.profiles.branch_id` + `can_access_branch()` / `is_hq()` decide visible data.
- `branch-switcher` — HQ/admin users switch the viewed branch in the app header.

## How to get to it (user POV)
1. Open `/auth`, sign in by Email or "เข้าสู่ระบบด้วย LINE".
2. After login you land in the dashboard; the header shows your branch.
3. Admins change a member's role/branch in user settings.

## Driving it with Playwright
1. Restore the session (Lovable auth-session) before visiting protected routes.
2. `page.goto('/auth')` → fill email/password → click the sign-in button by role.
3. Expect redirect to an `/_authenticated` route; assert the branch name in the header.

## Gotchas
- LINE `redirect_uri` must match a registered Callback URL exactly; otherwise 400 "Invalid redirect_uri". Optional fixed value: secret `LINE_LOGIN_REDIRECT_URI` (LINE settings page).
- Passwords are hashed; nobody (including admins/AI) can view them. Reset only.
- No "forgot password" link exists yet.

---

# Feature 2 — Customer Management & Cross-Branch Rare Cases

## Sub-features
- `customer-create-edit` — `/customers` create/edit with identity pre-check.
- `identity-uniqueness` — national ID and phone are unique **system-wide** (all branches), normalized to digits.
- `duplicate-check-rpc` — `check_customer_identity_duplicate()` returns existing customer code/name.

## How to get to it (user POV)
1. Menu "ทะเบียนลูกค้า" → "เพิ่มลูกค้า".
2. Enter 13-digit national ID and phone; a duplicate shows a Thai error naming the existing customer.

## Driving it with Playwright
1. Go to `/customers`, open the create dialog by role.
2. Use a unique synthetic run prefix (e.g. `PT-TEST-<runid>`) per Test Data Isolation rule.
3. Expect a toast/error on duplicate ID; expect a new row on success.

## Gotchas
- Branch staff only see customers of their branch; a customer registered at HQ is invisible to Ban Na San.
- **Rare case — Option 1 (admin temporary branch switch):** admin sets own `profile.branch_id` to the target branch, selects existing HQ customer in the Loan Application Wizard, submits (application/contract owned by target branch), then reverts own branch to HQ. Record who/when switched.
- **Rare case — Option 2 (customer branch transfer):** admin changes the customer's `branch_id` to the new branch; old contracts stay with their original branch; HQ keeps visibility via `is_hq()`.
- Name change (marriage/divorce): update `full_name`, keep old name in `note`, identity = national ID.
- Address change: single `address` field = current address; old/branch-specific address in `note`.
- Phone change: new number in `phone`, old in `phone2`/`note` (phone must stay unique).

---

# Feature 3 — Loan Application Wizard & Document Numbering

## Sub-features
- `wizard` — `LoanApplicationWizard`: customer (new/existing) → vehicle/collateral → terms → submit.
- `doc-number` — `next_loan_doc_no()` generates `APP-<BRANCH>-<SUBTYPE>-NNNN` via `doc_counters`.

## How to get to it (user POV)
1. Menu "คำขอสินเชื่อ" → "สร้างคำขอ".
2. Complete each wizard step; the application number appears after submit.

## Driving it with Playwright
1. Open the wizard, choose "ลูกค้าเดิม" or create a synthetic customer.
2. Fill steps by label, submit, assert number matches `/^APP-[A-Z]+-[A-Z]-\d{4,}$/`.

## Gotchas
- Owning branch = logged-in user's `profile.branch_id`.
- Known limit: `lpad(n,4)` truncates at 10000 → collision. Sequence safe only up to 9999 until fixed.

---

# Feature 4 — Contracts, Installment Schedules & Printing

## Sub-features
- `contract-create` — from approved application, number `CTR-<BRANCH>-<SUBTYPE>-NNNN`.
- `schedule` — installments generated per contract.
- `print` — printable contract documents.
- `cancel` — Phase B contract cancel (see docs/PHASE_B_*).

## How to get to it (user POV)
1. Menu "สัญญา" → open an approved application → "สร้างสัญญา".
2. Open the contract to view the schedule or print.

## Driving it with Playwright
1. Navigate to the contract list, open a synthetic contract by its number.
2. Assert installment rows count equals the term.

## Gotchas
- Same 9999 numbering limit as Feature 3.
- Never test on pre-existing contracts; create synthetic ones.

---

# Feature 5 — Payments, Receipts & Void

## Sub-features
- `payment-record` — record payment against installments.
- `receipt` — receipt generation/print.
- `void` — Phase B payment void with audit.

## How to get to it (user POV)
1. Open a contract → "รับชำระ" → enter amount → save.
2. Print the receipt; void requires the proper role.

## Driving it with Playwright
1. Use a synthetic contract; record a payment; assert the installment balance changes.
2. Void as an authorized role; assert status and audit record.

## Gotchas
- Void/cancel flows follow docs/PHASE_B_PAYMENT_VOID_* rules; do not void real data.
- Cleanup of test data only after explicit owner approval.
