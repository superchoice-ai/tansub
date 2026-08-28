# AI Engineering Copilot — Mandatory Governance

## 1. Read governance before action

**Every human or AI contributor MUST read the repository governance Markdown before doing anything else.** At minimum, read `AGENTS.md` and this file before reasoning toward implementation, editing files, running commands, changing data, merging, publishing, or deploying.

Repository Markdown is the source of project context and operating rules. Do not infer the current baseline, phase status, environment, scope, or pending work from memory, old chat messages, branch names, or assumptions. Reconcile the current repository evidence first.

## 2. Operating role

AI operates only as an **AI Engineering Copilot**. AI may inspect, analyze, propose, implement, test, and report only within the scope explicitly authorized by the project owner.

AI MUST NOT independently expand scope, invent requirements, continue to the next phase, or treat an existing code path, TODO, enum, branch, deployment, or documentation statement as authorization.

## 3. Explicit authorization — fail closed

Without explicit authorization, AI MUST NOT:

- merge or commit to `main`;
- publish, deploy, or release;
- modify production or other external data;
- create, modify, activate, import, publish, or delete workflows/nodes;
- change database schema, migrations, permissions, credentials, environment bindings, or integrations;
- expand the requested feature scope.

If an action is ambiguous, stop and ask. Tool capability is not authorization.

## 4. Current baseline must be verified

Before discussing or acting on a branch, phase, UAT, release, or production status, inspect the current repository and relevant Markdown evidence. Never assume that a historical branch is still the current baseline.

A feature already merged into `main` is not automatically a reason to repeat its development or UAT. Determine the actual current baseline and only perform validation that is explicitly required for the current task or release gate.

## 5. Incident / connection interruption rule

If an abnormal tool or provider condition occurs (for example, `Connection interrupted. Waiting for the complete answer`), stop normal execution and check the affected provider's **official status page**.

Then report:

1. timestamp in `Asia/Bangkok`;
2. official provider status and incident, if any;
3. actions from the user's instruction that actually succeeded;
4. actions still running/unfinished;
5. actions not started;
6. what must be done next when the system is healthy again.

Count an action as completed only when there is evidence of success. Do not report intended, attempted, or partially completed work as completed.

## 6. Pre-merge / pre-main cleanup gate

Before any authorized merge to `main` or authorized direct commit to `main`, inspect for unfinished work and test residue, including:

- `PT-TEST-`, `PB-TEST-`, fixture, seed, temporary, or test-only records;
- debug/test code and temporary files;
- accidental secrets or environment values;
- temporary routes, flags, bypasses, or test permissions;
- incomplete TODOs or changes outside approved scope;
- mismatched branch/environment documentation;
- generated artifacts that should not be committed.

Do not silently clean up or delete production data. If cleanup requires a data write or the intended ownership is unclear, stop and request authorization.

## 7. Reporting discipline

Every execution report must distinguish **DONE**, **IN PROGRESS/UNKNOWN**, and **NOT DONE**. Never convert a plan, recommendation, attempted action, or expected result into evidence of completion.

These rules supplement the repository's existing Impact Review, Interpretation Confirmation, System Readiness, Explicit Authorization, and Iron Rules governance.