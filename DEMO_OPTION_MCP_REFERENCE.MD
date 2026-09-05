# DEMO_OPTION_MCP_REFERENCE.MD — Reusable OAuth/RLS MCP Implementation

> [!CAUTION]
> **Mandatory reference:** อ่าน `Lovable.MD`, `DEMO_OPTION_LOVABLE.MD` และ `DEMO_OPTION_ASSISTANT_REFERENCE.MD` ก่อน
>
> เอกสารนี้คือ reusable implementation baseline ที่กลั่นจาก MCP execution log เดิม ไม่ใช่สำเนา log และไม่ใช่ authorization ให้เปิด endpoint หรือเข้าถึงข้อมูล ต้องปรับตาม stack/schema/provider ปัจจุบันและผ่าน OAuth, RLS, security และ regression gates

## 1. Security contract

MCP สำหรับ project ที่มีบัญชีผู้ใช้และข้อมูลแยก role/branch ต้อง:

- ใช้ OAuth authorization และ explicit Allow/Deny consent
- รับ verified access token ของ signed-in user
- ส่งต่อ user token ไปยัง DB clientเพื่อให้ RLS บังคับสิทธิ์
- ห้ามใช้ service-role ใน user-facing MCP tools
- เริ่มด้วย read-only tools เท่านั้น
- จำกัดข้อมูลตาม role และ branch แม้ client ส่ง branch ID อื่น
- ไม่คืน secret, token, full national ID หรือข้อมูลที่ไม่จำเป็น
- ไม่ทำ Approve/Reject/Edit/Delete/Payment; write ยังคงผ่าน app + approval workflow
- แยก issuer, callback, endpoint และ environment ระหว่าง Demo/Production
- รองรับ revoke, expiry, denial และ audit โดยไม่ log token

## 2. Project Adaptation Record

| รายการ | ค่าของ project | หลักฐาน |
| --- | --- | --- |
| Source/target/branch/SHA | TBD | GitHub/Lovable |
| Runtime stack | TBD | package/vite config |
| MCP SDK/version | TBD | package lock |
| MCP endpoint | TBD | route/plugin |
| OAuth issuer/audience | TBD | target auth config |
| Consent route | TBD | route |
| Auth return path | TBD | login methods |
| User-scoped DB client | TBD | implementation |
| Role/branch RLS | TBD | policies/tests |
| Tool inventory | TBD | approved tools |
| PII/output exclusions | TBD | classification |
| External clients | TBD | registered callbacks |
| Disable/rollback | TBD | tested procedure |

Security-related `TBD` = `DO NOT IMPLEMENT/CONNECT`

## 3. Architecture

```text
ChatGPT / Claude / other MCP client
  → OAuth authorize
  → Project login
  → Project consent Allow/Deny
  → short-lived user token
  → /mcp
  → Tool handler
  → user-scoped Supabase client with Authorization: Bearer <user token>
  → RLS role/branch policies
  → minimized read-only result
```

Authentication, authorization และ filtering เป็นคนละชั้น ต้องผ่านครบทั้งหมด

## 4. File layout

```text
src/
  lib/
    mcp/
      env.ts
      supabase.ts
      shared.ts
      index.ts
      tools/
        list-branches.ts
        portfolio-summary.ts
        search-customers.ts
        list-contracts.ts
        get-contract.ts
        list-overdue-installments.ts
        list-pending-approvals.ts
  routes/
    [.]lovable.oauth.consent.tsx
    auth.tsx
vite.config.ts
package.json
tests/mcp/
```

ปรับตาม framework/router ปัจจุบัน ห้ามสร้าง route/plugin ซ้ำ

## 5. Runtime environment helper

```ts
type RuntimeGlobals = typeof globalThis & {
  Deno?: { env?: { get?: (name: string) => string | undefined } };
  process?: { env?: Record<string, string | undefined> };
};

export function runtimeEnv(name: string): string | undefined {
  const runtime = globalThis as RuntimeGlobals;
  return runtime.Deno?.env?.get?.(name) ?? runtime.process?.env?.[name];
}

export function requireRuntimeEnv(names: readonly string[]): string {
  for (const name of names) {
    const value = runtimeEnv(name)?.trim();
    if (value) return value;
  }
  throw new Error(`Missing required environment: ${names.join(" or ")}`);
}

export function supabaseProjectUrl(): string {
  return requireRuntimeEnv(["SUPABASE_URL", "VITE_SUPABASE_URL"]);
}

export function supabasePublishableKey(): string {
  return requireRuntimeEnv([
    "SUPABASE_PUBLISHABLE_KEY",
    "VITE_SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_ANON_KEY",
    "VITE_SUPABASE_ANON_KEY",
  ]);
}
```

ห้าม fallback ไป project ref/key แบบ hardcode และห้ามเลือก key จาก keyset โดยไม่พิสูจน์ว่าเป็น target project

## 6. User-scoped Supabase client

```ts
import { createClient } from "@supabase/supabase-js";
import type { ToolContext } from "@lovable.dev/mcp-js";
import { supabaseProjectUrl, supabasePublishableKey } from "./env";

export function supabaseForUser(ctx: ToolContext) {
  if (!ctx.isAuthenticated()) throw new Error("Not authenticated");
  const token = ctx.getToken();
  if (!token) throw new Error("Verified OAuth token is required");

  return createClient(supabaseProjectUrl(), supabasePublishableKey(), {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export const NOT_AUTHENTICATED = {
  content: [{ type: "text" as const, text: "Not authenticated" }],
  isError: true as const,
};
```

ต้องตรวจ issuer, audience, expiry และ signature ผ่าน SDK/provider ก่อน handler ห้าม decode JWT แล้วเชื่อ claims เองโดยไม่ verify

## 7. Shared tool helpers

```ts
export function normalizeLimit(value: number | undefined, fallback = 20, max = 50) {
  const n = Number.isInteger(value) ? Number(value) : fallback;
  return Math.max(1, Math.min(n, max));
}

export function sanitizeSearch(value: string): string {
  return value.replace(/[%,()]/g, " ").trim().slice(0, 100);
}

export function baht(satang: number | null | undefined): number {
  return Math.round((satang ?? 0)) / 100;
}
```

- ตรวจ query construction ตาม client library
- จำกัด pagination/limit
- ใช้ explicit select fields
- minimize nested relations
- ไม่ reveal ว่า record นอก scope มีอยู่
- structured content และ text content ต้องมีสาระตรงกัน
- ใส่ read-only/idempotent annotations เมื่อเป็นจริง

## 8. Reusable tool pattern

```ts
import { defineTool } from "@lovable.dev/mcp-js";
import { z } from "zod";
import { NOT_AUTHENTICATED, supabaseForUser } from "../supabase";
import { normalizeLimit, sanitizeSearch } from "../shared";

export default defineTool({
  name: "search_customers",
  title: "Search customers",
  description: "Search customer profiles visible to the signed-in user. Sensitive identifiers are excluded.",
  inputSchema: {
    query: z.string().trim().min(1).max(100),
    branch_id: z.string().uuid().optional(),
    limit: z.number().int().min(1).max(50).default(20),
  },
  annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
  handler: async ({ query, branch_id, limit }, ctx) => {
    if (!ctx.isAuthenticated()) return NOT_AUTHENTICATED;

    const sb = supabaseForUser(ctx);
    const q = sanitizeSearch(query);
    let request = sb
      .from("customers")
      .select("id, code, full_name, phone, branch_id, status, created_at")
      .or(`full_name.ilike.%${q}%,code.ilike.%${q}%,phone.ilike.%${q}%`)
      .order("created_at", { ascending: false })
      .limit(normalizeLimit(limit));

    if (branch_id) request = request.eq("branch_id", branch_id);
    const { data, error } = await request;
    if (error) return {
      content: [{ type: "text", text: "Unable to search authorized records" }],
      isError: true,
    };

    return {
      content: [{ type: "text", text: JSON.stringify(data ?? [], null, 2) }],
      structuredContent: { customers: data ?? [] },
    };
  },
});
```

แม่แบบยังต้องทดสอบว่า RLS ปฏิเสธ `branch_id` นอก scope จริง ห้ามถือว่า `.eq()` คือ authorization

## 9. Baseline tools

| Tool | Input หลัก | Output ที่อนุญาต | ข้อห้าม |
| --- | --- | --- | --- |
| `list_branches` | none | สาขาที่ผู้ใช้เห็น | ห้ามคืนสาขานอก RLS |
| `portfolio_summary` | optional branch | aggregate + as_of | ห้ามรวมข้อมูลนอก scope |
| `search_customers` | query/branch/limit | basic profile | ไม่คืน national ID เต็ม |
| `list_contracts` | status/branch/customer/limit | contract summary | ตรวจหน่วยเงิน |
| `get_contract` | id หรือ code | contract/installments/non-void payments | not-visible = not found |
| `list_overdue_installments` | branch/days/limit | overdue rows | limit + PII minimization |
| `list_pending_approvals` | branch/limit | pending summary | ไม่มี approve/reject |

ชื่อ table/column/status ต้อง map จาก schema จริงและ generated types ของ project

## 10. MCP server definition

```ts
import { auth, defineMcp } from "@lovable.dev/mcp-js";
import listBranches from "./tools/list-branches";
import portfolioSummary from "./tools/portfolio-summary";
import searchCustomers from "./tools/search-customers";
import listContracts from "./tools/list-contracts";
import getContract from "./tools/get-contract";
import listOverdueInstallments from "./tools/list-overdue-installments";
import listPendingApprovals from "./tools/list-pending-approvals";

const projectRef = import.meta.env["VITE_SUPABASE_PROJECT_ID"];
if (!projectRef) throw new Error("VITE_SUPABASE_PROJECT_ID is required");

export default defineMcp({
  name: "PROJECT_SLUG",
  title: "PROJECT_TITLE",
  version: "0.1.0",
  instructions:
    "Read-only project tools. Callers act as the signed-in user and RLS limits data by role and branch. Data changes must be made in the app.",
  auth: auth.oauth.issuer({
    issuer: `https://${projectRef}.supabase.co/auth/v1`,
    acceptedAudiences: "authenticated",
  }),
  tools: [
    listBranches,
    portfolioSummary,
    searchCustomers,
    listContracts,
    getContract,
    listOverdueInstallments,
    listPendingApprovals,
  ],
});
```

เปลี่ยน `PROJECT_SLUG/TITLE` หลังยืนยัน ห้ามใช้ชื่อ project จาก log กับทุก repo

## 11. Vite/plugin integration

```ts
import { defineConfig } from "@lovable.dev/vite-tanstack-config";
import { mcpPlugin } from "@lovable.dev/mcp-js/stacks/tanstack/vite";

export default defineConfig({
  tanstackStart: { server: { entry: "server" } },
  vite: { plugins: [mcpPlugin()] },
});
```

ต้อง merge กับ config เดิม ไม่เขียนทับ plugins/server/aliases/proxy/build settings และตรวจว่า `mcpPlugin()` ไม่มีอยู่แล้ว

## 12. Consent route contract

Consent route ต้อง:

- ใช้ browser-only mode หาก session อยู่ browser storage
- validate `authorization_id`
- ถ้าไม่ login ให้ redirect ไป Auth พร้อม safe relative `next`
- เรียก official authorization-details API
- แสดงชื่อ client และ read-only scope
- มี Allow → approve และ Deny → deny
- redirect เฉพาะ URL ที่ authorization server คืน
- ไม่ log authorization ID/token
- มี error state ที่ไม่ expose internal details

```ts
async function decide(
  authorizationId: string,
  approve: boolean,
  oauth: {
    approveAuthorization: (id: string) => Promise<{ data: unknown; error: Error | null }>;
    denyAuthorization: (id: string) => Promise<{ data: unknown; error: Error | null }>;
  },
) {
  if (!authorizationId) throw new Error("Missing authorization_id");
  const { data, error } = approve
    ? await oauth.approveAuthorization(authorizationId)
    : await oauth.denyAuthorization(authorizationId);
  if (error) throw new Error("Unable to process authorization");

  const result = data as { redirect_url?: string; redirect_to?: string } | null;
  const target = result?.redirect_url ?? result?.redirect_to;
  if (!target) throw new Error("Authorization server returned no redirect");
  window.location.assign(target);
}
```

ใช้ API/signature ที่ SDK version ปัจจุบันรองรับจริง

## 13. Safe auth return path

```ts
export function safeNext(value: string | null | undefined): string | null {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return null;
  return value;
}
```

- เก็บ `next` ข้าม Google/LINE/email round-trip ได้ใน session storage หรือ signed state
- clear หลังใช้
- ห้าม duplicate navigate/redirect handlers
- LINE callback ต้อง preserve/validate state ตาม provider design
- Auth สำเร็จต้องกลับ consent ไม่ใช่ dashboard เมื่อมี pending authorization

## 14. Commands

```bash
git branch --show-current
git status --short
sed -n '1,240p' vite.config.ts
sed -n '1,220p' package.json
find src/lib/mcp -maxdepth 3 -type f -print 2>/dev/null
find src/routes -maxdepth 5 -type f -print | sort
rg -n "mcpPlugin|defineMcp|defineTool|oauth/consent|authorization_id|approveAuthorization|denyAuthorization" src vite.config.ts
rg -n "SERVICE_ROLE|ctx.getToken|isAuthenticated|Authorization|createClient" src/lib/mcp src 2>/dev/null
env | cut -d= -f1 | rg '^(SUPABASE_|VITE_SUPABASE_|LOVABLE_)'
```

ห้าม `cat .env`

เมื่อตรวจ package manager/version และได้รับอนุญาต:

```bash
bun add @lovable.dev/mcp-js zod
```

หรือ:

```bash
npm install @lovable.dev/mcp-js zod
```

ห้ามสร้าง lockfile สองระบบโดยไม่ตั้งใจ

หลังแก้:

```bash
rg -n '"@lovable.dev/mcp-js"|"zod"' package.json
git diff -- package.json bun.lock package-lock.json vite.config.ts src/lib/mcp src/routes
bun run build
bunx tsgo --noEmit
```

ใช้ scripts ของ repo หากต่างจากตัวอย่าง

## 15. OAuth/RLS test matrix

| Identity | Consent | Requested scope | Expected |
| --- | --- | --- | --- |
| Anonymous | none | any | 401/denied |
| Signed-in + Deny | denied | own branch | no token/tool access |
| Staff A | allowed | Branch A | allowed minimal fields |
| Staff A | allowed | Branch B | empty/denied, no leakage |
| Manager | allowed | confirmed branches | business-rule result |
| HQ/Admin | allowed | global/selected | only confirmed access |
| Expired token | previously allowed | any | denied |
| Wrong issuer/audience | allowed elsewhere | any | denied |
| Revoked consent | revoked | any | denied |
| service-role attempt | n/a | any | absent/fail test |

ต้องทดสอบ Data API/RLS จริง ไม่ใช้ mocked filter เป็นหลักฐาน authorization

## 16. External clients

ก่อนประกาศรองรับ ChatGPT, Claude หรือ client อื่น:

- ใช้ official client integration flow
- callback/redirect URI exact match
- แยก registration Demo/Production
- ทดสอบ login, Allow, Deny, tool discovery, role/branch, expiry, revoke, reconnect
- บันทึก client/version/date/environment โดยไม่เก็บ token
- client ที่ยังไม่ทดสอบต้องระบุ `NOT VERIFIED`

## 17. Assistant integration

Option 2.1 ต้องแชร์ tool contracts, scope resolver, user-scoped DB adapter, output minimization, error mapping และ RLS matrix tests

Assistant ห้ามเรียก service-role หรือ query ชุดที่กว้างกว่า MCP หากไม่มี business rule ที่อนุมัติ

## 18. Main ↔ Demo gate

```bash
git log --oneline --decorate -20
git diff --stat <TARGET_BASE_SHA>...HEAD
git diff --name-status <TARGET_BASE_SHA>...HEAD
git diff <TARGET_BASE_SHA>...HEAD -- package.json vite.config.ts src/lib/mcp src/routes
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  'SERVICE_ROLE|SUPABASE_.*KEY|\.supabase\.co|\.lovable\.app|demo|mock|test'
```

รายงาน SDK/lockfile, config/plugin, OAuth issuer/audience/callback, route conflicts, schema/RLS, tools/data, environment bindings, client registrations, build/E2E/RLS และ rollback

Stale project ref, service-role use, duplicate auth route/plugin, unverified RLS หรือ callback ผิด environment = `DO NOT MERGE`

## 19. Rollback/disable

ต้องมีวิธี disable MCP endpoint/plugin โดย revert, revoke clients, remove environment callback, preserve audit, ไม่ลบ user/business data, rerun Auth/App regression และตรวจ token lifecycle

## 20. Raw-log prohibition

ห้าม commit execution log ต้นฉบับหรือ copy โค้ดตรง ๆ เพราะอาจมี duplicated consent/auth blocks, incomplete edits, project-specific schema, unsafe env inspection, stale package version หรือ code ที่ยังไม่ผ่าน build/E2E

ใช้ source ปัจจุบัน + adaptation record + reference นี้เท่านั้น
