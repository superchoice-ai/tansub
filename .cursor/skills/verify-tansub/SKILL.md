---
name: verify-tansub
description: Verify Tansub (loan CRM) features the way real users and AI agents use them. Use before reporting any Tansub change as done, and to keep the feature map current.
---

# Verify Tansub

## When to use
- After any change merged to `main` (Lovable, GitHub, Cursor, or any tool).
- When asked to test, demo, or document a Tansub flow.

## Steps
1. Read every `.md`/`.MD` on latest `main` (governance gate) and `docs/TANSUB_FEATURE_MAP_VERIFICATION_GUIDE.md`.
2. Pick the affected feature entries; follow "Driving it with Playwright" on Preview, never Production writes.
3. Restore an authenticated session before protected routes; use stable roles/labels as handles.
4. Create only synthetic data with a unique run prefix; record a creation manifest; no cleanup without owner approval.
5. Capture evidence (screenshots, network status, DB read-only checks).
6. **Update the feature map**: add/modify/remove Sub-features, user steps, driving steps, and Gotchas for anything that changed; bump the "Last synced with main" SHA/date.

## Done means
- Affected flows verified with evidence, and the feature map + this skill reflect current `main`.
