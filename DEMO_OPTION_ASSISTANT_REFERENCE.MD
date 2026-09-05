# DEMO_OPTION_ASSISTANT_REFERENCE.MD — Reusable AI Assistant Implementation

> [!CAUTION]
> **Mandatory reference:** อ่าน `Lovable.MD` และ `DEMO_OPTION_LOVABLE.MD` ก่อนอ่านไฟล์นี้
>
> เอกสารนี้คือ reusable implementation baseline ที่กลั่นจาก implementation log เดิม ไม่ใช่สำเนา log และไม่ใช่คำสั่งให้ paste โค้ดลงทุก project โดยตรง ต้องทำ Project Adaptation Record และผ่าน Auth/RLS/regression gates ก่อนใช้เสมอ

## 1. Contract ที่ต้องรักษา

Assistant ต้อง:

- ตอบคำถามทั่วไปและวิธีใช้ project จาก help/capability document ที่ยืนยันแล้ว
- วิเคราะห์ข้อมูล project แบบ read-only เฉพาะที่ signed-in user มีสิทธิ์เห็น
- แสดง role, branch/data scope และเวลา `as_of`
- แยก general knowledge ออกจาก project/tool-derived facts
- ไม่สร้าง แก้ไข ลบ อนุมัติ ชำระเงิน หรือเปลี่ยนสถานะ
- ไม่ใช้ service-role เพื่อขยายสิทธิ์
- ไม่ส่ง secret, token, full national ID หรือข้อมูลนอก scope ไป AI provider
- ปฏิเสธคำถามข้ามสิทธิ์และชี้ไปยังหน้าจอ/ผู้อนุมัติที่ถูกต้อง

## 2. Project Adaptation Record — ต้องกรอกก่อนพัฒนา

| รายการ | ค่าของ project ปัจจุบัน | หลักฐาน |
| --- | --- | --- |
| Source/target environment | TBD | project/branch/SHA |
| Auth server helper | TBD | file + function |
| User/profile/role tables | TBD | schema |
| Branch enforcement | TBD | RLS policies/functions |
| Assistant route | TBD | route file |
| AI provider/model | TBD | approved configuration |
| Help source | TBD | confirmed document |
| Allowed data fields/aggregates | TBD | owner approval |
| PII exclusions | TBD | data classification |
| Error/credit behavior | TBD | provider docs/tests |
| Rollback | TBD | commit/revert plan |

มี `TBD` แม้หนึ่งรายการที่กระทบสิทธิ์หรือข้อมูล = `DO NOT IMPLEMENT`

## 3. Recommended architecture

```text
Assistant UI
  → authenticated server action
  → resolve signed-in identity + role + branch scope
  → shared read-only domain/tool layer
  → RLS-enforced user-scoped DB access
  → minimized context + confirmed help document
  → AI gateway
  → scoped answer + as_of + no-write notice
```

หลัง MCP พร้อม Assistant ควรเรียก shared domain/tool layer เดียวกับ MCP ห้ามสร้าง permission logic สองชุดที่ให้ผลต่างกัน

## 4. File layout แม่แบบ

```text
src/
  lib/
    assistant/
      contracts.ts
      scope.ts
      help.ts
      data-provider.ts
      gateway.ts
      ask-assistant.ts
  routes/
    _authenticated/
      assistant/
        index.tsx
tests/
  assistant/
    scope.test.ts
    gateway.test.ts
    assistant.e2e.ts
```

ปรับตาม stack ของ repo ห้ามสร้าง duplicate route/server/client

## 5. Contracts ที่ใช้ซ้ำได้

```ts
export type AssistantRole = "staff" | "manager" | "approver" | "admin";

export type AssistantMessage = {
  role: "user" | "assistant";
  content: string;
};

export type AssistantScope = {
  userId: string;
  roles: AssistantRole[];
  homeBranchId: string | null;
  requestedBranchId: string | null;
  effectiveBranchId: string | null;
  scopeLabel: string;
  canViewAllBranches: boolean;
};

export type AssistantSnapshot = {
  asOf: string;
  scope: Pick<AssistantScope, "roles" | "effectiveBranchId" | "scopeLabel">;
  facts: Record<string, string | number | boolean | null>;
};

export interface AssistantDataProvider {
  resolveScope(userId: string, requestedBranchId: string | null): Promise<AssistantScope>;
  getSnapshot(scope: AssistantScope): Promise<AssistantSnapshot>;
}

export interface AssistantGateway {
  answer(input: {
    messages: AssistantMessage[];
    helpDocument: string;
    snapshot: AssistantSnapshot;
  }): Promise<string>;
}
```

Contract นี้จงใจไม่ผูกชื่อตาราง เพื่อให้ adapter ของแต่ละ project เป็นผู้ map schema จริง

## 6. Scope resolver pattern

```ts
export async function resolveAssistantScope(
  userId: string,
  requestedBranchId: string | null,
  deps: {
    getIdentity: (userId: string) => Promise<{
      roles: AssistantRole[];
      homeBranchId: string | null;
      homeBranchName: string | null;
      isHq: boolean;
    }>;
    canAccessBranch: (userId: string, branchId: string) => Promise<boolean>;
    getBranchName: (branchId: string) => Promise<string | null>;
  },
): Promise<AssistantScope> {
  const identity = await deps.getIdentity(userId);
  const canViewAllBranches = identity.roles.includes("admin") || identity.isHq;

  if (!canViewAllBranches) {
    if (!identity.homeBranchId) throw new Error("User has no authorized branch");
    return {
      userId,
      roles: identity.roles,
      homeBranchId: identity.homeBranchId,
      requestedBranchId,
      effectiveBranchId: identity.homeBranchId,
      scopeLabel: identity.homeBranchName ?? "Home branch",
      canViewAllBranches: false,
    };
  }

  if (requestedBranchId) {
    if (!(await deps.canAccessBranch(userId, requestedBranchId))) {
      throw new Error("Requested branch is outside the authorized scope");
    }
    return {
      userId,
      roles: identity.roles,
      homeBranchId: identity.homeBranchId,
      requestedBranchId,
      effectiveBranchId: requestedBranchId,
      scopeLabel: (await deps.getBranchName(requestedBranchId)) ?? "Selected branch",
      canViewAllBranches: true,
    };
  }

  return {
    userId,
    roles: identity.roles,
    homeBranchId: identity.homeBranchId,
    requestedBranchId: null,
    effectiveBranchId: null,
    scopeLabel: "All authorized branches",
    canViewAllBranches: true,
  };
}
```

ข้อบังคับ: `canAccessBranch` ต้องอิง RLS/business rule จริง ไม่ใช่รับ `branch_id` จาก client แล้วเชื่อทันที

## 7. Shared data-provider pattern

```ts
export async function buildAssistantSnapshot(
  scope: AssistantScope,
  tools: {
    portfolioSummary: (input: { branchId: string | null }) => Promise<Record<string, unknown>>;
    pendingApprovals?: (input: { branchId: string | null; limit: number }) => Promise<unknown[]>;
  },
): Promise<AssistantSnapshot> {
  const portfolio = await tools.portfolioSummary({ branchId: scope.effectiveBranchId });
  const approvals = tools.pendingApprovals
    ? await tools.pendingApprovals({ branchId: scope.effectiveBranchId, limit: 20 })
    : [];

  return {
    asOf: new Date().toISOString(),
    scope: {
      roles: scope.roles,
      effectiveBranchId: scope.effectiveBranchId,
      scopeLabel: scope.scopeLabel,
    },
    facts: {
      ...portfolio,
      pendingApprovalCount: approvals.length,
    },
  };
}
```

Tool/shared function ต้องใช้ user-scoped DB client และ RLS เหมือน MCP ห้ามรับ service-role client

## 8. Prompt construction

```ts
export function buildAssistantSystemPrompt(
  helpDocument: string,
  snapshot: AssistantSnapshot,
): string {
  return [
    "You are the internal project assistant.",
    "Answer in the user's language, clearly and concisely.",
    "Separate general guidance from live project data.",
    "Project data may be stated only from the supplied snapshot/tool result.",
    "Never invent records, figures, permissions, workflows, or statuses.",
    "You are read-only. Never claim to create, edit, delete, approve, pay, or change data.",
    "Never expose another branch, secrets, access tokens, or full sensitive identifiers.",
    "For an unauthorized action, refer the user to the proper screen and authorized role.",
    `DATA_SCOPE: ${snapshot.scope.scopeLabel}`,
    `AS_OF: ${snapshot.asOf}`,
    "CONFIRMED_HELP:",
    helpDocument,
    "AUTHORIZED_SNAPSHOT:",
    JSON.stringify(snapshot),
  ].join("\n");
}
```

Help document ต้องมาจาก requirement ที่ยืนยันแล้ว ห้ามสร้าง business rule จากชื่อ enum/TODO/โค้ด dormant

## 9. Gateway pattern

```ts
export async function callAssistantGateway(input: {
  apiKey: string;
  endpoint: string;
  model: string;
  systemPrompt: string;
  messages: AssistantMessage[];
}): Promise<string> {
  const response = await fetch(input.endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${input.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: input.model,
      messages: [{ role: "system", content: input.systemPrompt }, ...input.messages],
    }),
  });

  if (response.status === 401 || response.status === 403) throw new Error("AI access is not authorized");
  if (response.status === 402) throw new Error("AI credit is unavailable");
  if (response.status === 429) throw new Error("AI rate limit reached");
  if (!response.ok) throw new Error("AI assistant is temporarily unavailable");

  const json = (await response.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const answer = json.choices?.[0]?.message?.content?.trim();
  if (!answer) throw new Error("AI assistant returned no answer");
  return answer;
}
```

- API key อยู่ server environment เท่านั้น
- ห้าม log prompt/snapshot/token เต็ม
- Model/endpoint ต้องเป็น configuration ที่อนุมัติ ไม่ hardcode ข้าม environment
- Error ห้าม fallback ไป provider หรือ credential อื่นเอง

## 10. Server-action orchestration

```ts
export async function askAssistant(
  input: { userId: string; requestedBranchId: string | null; messages: AssistantMessage[] },
  deps: {
    data: AssistantDataProvider;
    gateway: AssistantGateway;
    helpDocument: string;
  },
) {
  if (!input.userId) throw new Error("Not authenticated");
  if (!input.messages.length || input.messages.length > 30) throw new Error("Invalid message history");

  const scope = await deps.data.resolveScope(input.userId, input.requestedBranchId);
  const snapshot = await deps.data.getSnapshot(scope);
  const answer = await deps.gateway.answer({
    messages: input.messages,
    helpDocument: deps.helpDocument,
    snapshot,
  });

  return {
    answer,
    scopeLabel: scope.scopeLabel,
    roles: scope.roles,
    asOf: snapshot.asOf,
    readOnly: true,
  };
}
```

ต้อง bind `userId` จาก verified server session ห้ามรับจาก request body

## 11. UI contract

UI ต้องมี:

- scope label และ roles
- read-only badge
- suggestion prompts ที่ไม่สัญญา write capability
- Enter ส่ง, Shift+Enter ขึ้นบรรทัด
- loading/error states
- no-write notice
- timestamp/as-of เมื่อใช้ข้อมูล project
- ไม่มีการ render raw HTML จากโมเดลโดยไม่ sanitize

## 12. Commands

```bash
git branch --show-current
git status --short
rg -n "assistant|askAssistant|requireSupabaseAuth|useAuth|useBranchFilter|ROLE_LABEL|LOVABLE_API_KEY" src
rg -n "from\(|rpc\(" src/lib/assistant* src/lib/mcp 2>/dev/null
sed -n '1,320p' src/lib/assistant.functions.ts 2>/dev/null
sed -n '1,360p' src/routes/_authenticated/assistant/index.tsx 2>/dev/null
env | cut -d= -f1 | rg '^(LOVABLE_|SUPABASE_|VITE_SUPABASE_)'
bun run build
bunx tsgo --noEmit
```

ใช้ npm scripts ของ repo หากไม่ใช้ Bun ห้ามอ่านหรือพิมพ์ค่า `.env`

## 13. Required tests

| Test | Expected |
| --- | --- |
| Anonymous | Assistant project data denied |
| Staff A → Branch A | Allowed fields only |
| Staff A → Branch B | Denied/no leakage |
| Manager/HQ | Only confirmed scope |
| General question | Answered, labeled/non-live when appropriate |
| Live project question | Based only on snapshot/tool result |
| Write/approve/delete request | Refused; points to normal workflow |
| Missing fact | No invention |
| PII prompt injection | Sensitive fields remain excluded |
| 401/403/402/429/5xx | Controlled error; no privilege fallback |
| Assistant vs MCP same user | Same scope and material facts |
| Logout/session expiry | Access stops |

## 14. Main ↔ Demo comparison gate

ก่อน PR ต้องบันทึก:

- Production base SHA และ Demo feature SHA
- full diff ของ route, server actions, shared tools, auth, deps และ environment references
- schema/RLS/function changes
- help/business-rule changes
- AI provider/model/credit behavior
- test matrix และ rollback

พบ duplicate route, duplicate component/export/import, duplicated query path, stale project ref, service-role use หรือ unresolved `TBD` = `DO NOT MERGE`

## 15. Raw-log prohibition

ห้าม commit execution log ต้นฉบับหรือคัดลอกโค้ดจาก log โดยตรง เพราะ log อาจมี:

- โค้ดก่อนและหลังแก้ซ้ำกัน
- duplicate imports/components/meta
- destructuring/query ที่ไม่ตรงกัน
- project-specific schema/routes/labels
- command ที่เปิดเผย environment
- สถานะ “แก้แล้ว” ที่ยังไม่ผ่าน build/regression

ใช้ไฟล์นี้เป็น baseline แล้วปรับจาก source code ปัจจุบันเท่านั้น
