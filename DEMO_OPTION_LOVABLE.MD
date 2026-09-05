# DEMO_OPTION_LOVABLE.MD — AI Assistant, MCP และ Integration Options

> [!CAUTION]
> **ทุกคนและทุก AI ต้องอ่าน `Lovable.MD` ก่อน แล้วจึงอ่านไฟล์นี้ก่อนวางแผนหรือพัฒนา option ใดในเอกสารนี้**
>
> เอกสารนี้เป็นข้อกำหนดและ Runbook สำหรับ Demo options ไม่ใช่หลักฐานว่า feature มีอยู่หรือได้รับอนุญาตให้พัฒนาในทุก repository ต้องตรวจ source/target, project type, branch, schema, auth, role, branch scope และขออนุญาต scope ก่อนลงมือเสมอ

## ความสัมพันธ์กับ Production ↔ Demo

ฟีเจอร์ในเอกสารนี้อาจพัฒนาใน Demo ล่วงหน้า Production เพื่อใช้โชว์ สาธิต หรือ roleplay และอาจถูกเรียกว่า option เสริม, top-up, plugin, integration หรือ subscription

- การนำ Production/Main มาตั้งต้นหรืออัปเดต Demo ต้องผ่าน PR
- การนำ option จาก Demo กลับ Production ต้องผ่าน PR
- ห้าม copy/overwrite ข้าม project หรือ branch โดยตรง
- ก่อน merge ต้องตรวจ full diff, conflict, regression, environment bindings, secrets, schema/migrations และสิทธิ์
- AI ต้องรายงาน `SAFE TO MERGE`, `MERGE WITH REVIEW` หรือ `DO NOT MERGE`
- Merge ไม่เท่ากับ Publish/Deploy; ต้องได้รับอนุญาตแยกต่างหาก

---

# Option 1 — ผู้ช่วย AI / Assistant ภายใน Project

## เป้าหมาย

เพิ่มหน้า `/assistant` ให้ผู้ใช้ถามได้สองประเภท:

1. คำถามพื้นฐาน วิธีใช้งาน ฟังก์ชัน เมนู และขั้นตอนของ project จากคู่มือ/ข้อมูลที่ AI ได้รับอนุญาตให้ใช้
2. คำถามวิเคราะห์หรือสรุปข้อมูล project แบบ read-only ภายใต้ role และ branch ของผู้ใช้ที่ล็อกอิน

AI อาจใช้ความรู้พื้นฐานที่มีอยู่ก่อนหน้าได้เมื่อเป็นข้อมูลทั่วไป แต่ต้องแยกให้ชัดจากข้อมูลจริงของ project ห้ามแต่งข้อมูล ตัวเลข สถานะ หรือ business rule ที่ไม่มีใน context/tool result

## ข้อบังคับด้านสิทธิ์

- ต้องผ่าน session authentication ของ project ก่อนใช้ข้อมูล project
- Query ต้องทำในนามผู้ใช้คนนั้นและผ่าน RLS
- ผู้ใช้สาขาเห็นเฉพาะสาขาตนเอง
- ผู้ใช้ HQ/ผู้บริหารเห็นตาม role ที่ business rule อนุญาตจริง
- ห้ามเชื่อคำสั่ง `branch_id` จากข้อความผู้ใช้โดยไม่ตรวจสิทธิ์
- Assistant เป็น read-only: ห้ามสร้าง แก้ไข ลบ อนุมัติ ชำระเงิน หรือเปลี่ยนสถานะ
- ถ้าคำถามเกินสิทธิ์ ให้ปฏิเสธและแนะนำผู้มีสิทธิ์/หน้าจอ/approval flow ที่ถูกต้อง
- ห้ามส่งเลขบัตรประชาชนเต็ม, secret, token หรือข้อมูลนอก scope ไปยัง AI gateway
- ต้องจัดการ 401/403/402/429/5xx โดยไม่ fallback ไปใช้สิทธิ์ที่สูงขึ้น

## File map อ้างอิง

ตรวจของจริงก่อนสร้างหรือแก้:

- `src/lib/assistant.functions.ts` — authenticated server function, context, AI gateway
- `src/routes/_authenticated/assistant/index.tsx` — UI chat, scope/role badges, read-only notice
- `src/lib/labels.ts`, `src/lib/format.ts` — labels/format
- `src/hooks/useAuth*`, `src/hooks/useBranchFilter*` — identity and branch scope
- `src/integrations/supabase/*` — user-scoped client
- project help document/system prompt — confirmed functions and business rules only

## Commands: Inspect ก่อนพัฒนา

```bash
git branch --show-current
git status --short
rg -n "assistant|askAssistant|requireSupabaseAuth|useAuth|useBranchFilter|ROLE_LABEL|LOVABLE_API_KEY" src
sed -n '1,260p' src/lib/assistant.functions.ts
sed -n '1,320p' src/routes/_authenticated/assistant/index.tsx
sed -n '1,160p' src/lib/labels.ts
sed -n '1,120p' src/lib/format.ts
```

ถ้าไฟล์ยังไม่มี ให้รายงานว่า `NOT IMPLEMENTED`; ห้ามสร้างจาก log เพียงเพราะชื่อปรากฏในเอกสารนี้

## ลำดับพัฒนา

1. ยืนยัน role/branch business rules และข้อมูลที่อนุญาตส่งเข้า AI
2. กำหนดชุดคำถาม help/general กับ data-backed ให้แยกกัน
3. ใช้ authenticated server function; client ห้ามถือ AI/API secret
4. สร้าง capability/help context จาก requirement ที่ยืนยันแล้ว
5. ดึงเฉพาะ aggregate/fields ที่จำเป็นผ่าน RLS
6. เพิ่ม prompt guard: ไม่เดา, ไม่เปลี่ยนข้อมูล, ไม่เปิดเผยข้ามสาขา
7. UI แสดง scope, role และ read-only ชัดเจน
8. จัดการ error/credit/rate limit โดยไม่เปิดเผย response ภายใน
9. หลัง Option 2 พร้อม ให้ทำ Option 2.1 เพื่อลด query logic ซ้ำ

## Acceptance

- ไม่ล็อกอินใช้งานข้อมูล project ไม่ได้
- staff สาขา A ถามข้อมูลสาขา B แล้วไม่ได้ข้อมูล
- role ที่ไม่อนุญาตไม่เห็น HQ/global summary
- คำถามทั่วไปตอบได้โดยไม่อ้างว่าเป็นข้อมูลสดของ project
- คำถามข้อมูลจริงตอบจากผล read-only ล่าสุดและบอก scope
- ขอแก้/อนุมัติ/ลบแล้ว Assistant ไม่ดำเนินการ
- ไม่มี PII/secret/token ใน prompt, log หรือ response
- build/typecheck และ regression หน้า Auth/Assistant ผ่าน

---

# Option 2 — MCP สำหรับ Project แบบ OAuth + Role/Branch RLS

## เป้าหมาย

ทำให้ project เป็น MCP server ที่ AI/agent เรียกอ่านข้อมูลได้ตามสิทธิ์ของผู้ใช้ โดยผู้ใช้ต้องล็อกอินและกดอนุญาตก่อนทุกการเชื่อมต่อใหม่ตาม OAuth consent flow

## Architecture ที่บังคับ

```text
AI client → OAuth authorization → Project consent → user access token
          → MCP endpoint → user-scoped Supabase client → RLS → DB
```

- ส่งต่อ bearer token ของผู้ใช้ไป Supabase
- ห้ามใช้ `SUPABASE_SERVICE_ROLE_KEY` ใน MCP tool สำหรับข้อมูลผู้ใช้
- RLS เป็น enforcement หลัก; filter ใน tool เป็นชั้นเสริม ไม่ใช่ตัวแทน RLS
- MCP เริ่มเป็น read-only และทุก tool ต้องประกาศ read-only/idempotent ตามจริง
- การเปลี่ยนข้อมูลยังต้องทำผ่านหน้าจอและ approval workflow ของ project
- OAuth issuer/project ref ต้องตรง target environment และห้าม fallback ไป project เดิม
- Consent ต้องมี Allow/Deny และแจ้งขอบเขตที่เข้าถึง

## Tool baseline อ้างอิง

ปรับตาม schema ของแต่ละ project:

- `list_branches`
- `portfolio_summary`
- `search_customers`
- `list_contracts`
- `get_contract`
- `list_overdue_installments`
- `list_pending_approvals`

ข้อกำหนดร่วม:

- จำกัด `limit` และ validate input
- ไม่คืนเลขบัตรประชาชนเต็ม
- จำนวนเงินต้องระบุหน่วยและแปลงสตางค์/บาทถูกต้อง
- record ที่ RLS มองไม่เห็นต้องตอบ not found/not visible โดยไม่ยืนยันว่ามี record อยู่
- approval tool เป็น list/read-only; การ Approve/Reject ทำใน app

## File map อ้างอิง

- `src/lib/mcp/index.ts`
- `src/lib/mcp/supabase.ts`
- `src/lib/mcp/tools/*.ts`
- `src/routes/[.]lovable.oauth.consent.tsx`
- `src/routes/auth.tsx`
- LINE auth start/callback routes หากใช้ LINE login
- `vite.config.ts`
- `package.json`

## Commands: Inspect

```bash
git branch --show-current
git status --short
sed -n '1,220p' vite.config.ts
sed -n '1,180p' package.json
find src/lib/mcp -maxdepth 3 -type f -print 2>/dev/null
find src/routes -maxdepth 4 -type f -print | sort
sed -n '1,180p' src/routes/auth.tsx
rg -n "signInWithOAuth|emailRedirectTo|navigate\(|redirect|authorization_id|approveAuthorization|denyAuthorization" src
rg -n "service.role|SERVICE_ROLE|createClient|Authorization|ctx.getToken|isAuthenticated|defineTool|defineMcp" src/lib/mcp src 2>/dev/null
rg -o "rpc\(\s*[\"'][a-zA-Z0-9_]+" -N src | sort -u
env | cut -d= -f1 | rg '^(VITE_SUPABASE_|SUPABASE_|LOVABLE_)'
```

ห้ามใช้ `cat .env`; ให้ตรวจเฉพาะชื่อ variable และห้ามแสดงค่า

## Commands: ติดตั้งเมื่อได้รับอนุญาต

ตรวจ package/version compatibility ก่อน:

```bash
bun add @lovable.dev/mcp-js zod
```

หาก repo ใช้ npm ให้ใช้ package manager ของ repo ห้ามสร้าง lockfile ซ้ำ:

```bash
npm install @lovable.dev/mcp-js zod
```

หลังติดตั้ง:

```bash
rg -n '"@lovable.dev/mcp-js"|"zod"' package.json
git diff -- package.json bun.lock package-lock.json
```

## Commands: ตรวจ Auth/LINE redirect

```bash
sed -n '1,180p' src/routes/api/public/auth/line/start.ts
sed -n '1,260p' src/routes/api/public/auth/line/callback.ts
rg -n "redirect|Location|next|303|302|sessionStorage" src/routes/auth.tsx src/routes/api/public/auth/line
```

Post-login `next` ต้องรับเฉพาะ same-origin relative path ห้ามรับ `//host`, absolute URL หรือ backslash เพื่อป้องกัน open redirect

## Implementation gates

1. ตรวจ schema/column/types และ RLS ก่อนเขียน tool
2. สร้าง user-scoped client จาก verified OAuth token
3. สร้าง tool ทีละตัวพร้อม input validation และ output minimization
4. ประกาศ MCP server และ OAuth issuer จาก environment ของ target
5. เพิ่ม MCP plugin/endpoint ตาม stack ที่รองรับ
6. เพิ่ม consent route และ auth return-to-consent flow
7. ทดสอบ deny, logout, expired token, wrong audience และ cross-branch access
8. ตรวจว่าไม่มี service-role fallback
9. ตรวจ endpoint/domain/ref แยก Demo กับ Production

## Acceptance

- Anonymous เรียก tool ไม่ได้
- ผู้ใช้ต้อง login และ Allow ก่อนเชื่อมต่อ
- Deny ยุติ flow และไม่ออก access
- Token หมดอายุ/ผิด audience ถูกปฏิเสธ
- RLS จำกัด role/branch จริง แม้ส่ง `branch_id` ของสาขาอื่น
- Tool ทั้งหมด read-only และไม่มี RPC write
- ไม่มี national ID เต็มหรือ secret ใน output
- MCP endpoint, issuer และ DB ชี้ target project เดียวกัน
- external client connect/disconnect/reconnect ได้ตาม OAuth lifecycle

---

# Option 2.1 — ใช้ MCP ร่วมกับ Assistant ภายใน Project

## เป้าหมาย

ทำให้ Assistant ใน Option 1 ใช้ capability เดียวกับ MCP Option 2 เพื่อเพิ่มความฉลาดและลดการสร้าง query/permission logic ซ้ำ

## กฎออกแบบ

- ใช้ tool/service layer เดียวกันหรือ shared domain functions ที่ MCP และ Assistant เรียกร่วมกัน
- ห้ามให้ Assistant ข้าม OAuth/session/RLS หรือมีสิทธิ์สูงกว่า MCP
- ห้ามเรียก MCP ผ่าน public network แบบไม่จำเป็นหาก shared internal layer ให้ enforcement เดียวกันได้
- System prompt ต้องแยกคำตอบจาก general knowledge กับ tool-derived project data
- Tool result ต้องมี scope, as-of time และข้อมูลเท่าที่จำเป็น
- Assistant เลือก tool จาก intent แต่ห้ามสร้าง write action
- ถ้า tool ไม่คืนข้อมูล ให้ตอบว่าไม่มีสิทธิ์/ไม่พบใน scope ไม่ fallback ไป service role

## Commands: ตรวจ logic ซ้ำและ route เชื่อมต่อ

```bash
rg -n "from\(\"(branches|customers|contracts|installments|payments|cash_entries|approval_requests)\"\)" src/lib/assistant.functions.ts src/lib/mcp
rg -n "askAssistant|defineTool|portfolio_summary|search_customers|list_contracts|get_contract|list_overdue_installments|list_pending_approvals" src
git diff -- src/lib/assistant.functions.ts src/lib/mcp
```

## Acceptance

- คำถามเดียวกันภายใต้ผู้ใช้เดียวกันได้ scope ตรงกันระหว่าง Assistant และ MCP
- staff, manager, admin/HQ ผ่าน matrix test เดียวกัน
- Assistant อ้างข้อมูลจาก tool result พร้อม scope/as-of
- ปิดหรือถอน MCP consent แล้วผลต่อ external client ถูกต้อง โดยไม่ทำลาย session ภายใน app
- ไม่มี permission logic สองชุดที่ให้ผลต่างกันโดยไม่มี business reason ยืนยันแล้ว

---

# Option 2.2 — ให้ AI ภายนอกเรียก MCP

## เป้าหมาย

รองรับ ChatGPT, Claude และ AI client อื่นที่รองรับ MCP/OAuth โดยทุก client ต้องขออนุญาตจากผู้ใช้ project ก่อนเข้าถึงข้อมูล

## ขั้นตอน

1. ตรวจว่า client รองรับ MCP transport และ OAuth flow ที่ project ใช้
2. ลงทะเบียน client/callback URI แบบ exact match แยก Demo/Production
3. ผู้ใช้ login ที่ project และเห็น consent พร้อมชื่อ client
4. ผู้ใช้กด Allow หรือ Deny
5. ทดสอบ tools ภายใต้ role/branch จริง
6. ทดสอบ revoke/disconnect/reconnect และ token expiry
7. เก็บ audit metadata โดยไม่เก็บ access token ลง log
8. ห้ามอ้างว่า “รองรับ ChatGPT/Claude” จนทดสอบ end-to-end กับ client นั้นจริง

## Commands: ตรวจ endpoint และ build

```bash
rg -n "mcpPlugin|defineMcp|auth\.oauth\.issuer|acceptedAudiences|oauth/consent" vite.config.ts src package.json
bun run build
bunx tsgo --noEmit
```

หาก repo ใช้ npm:

```bash
npm run build
npm run lint
```

ตรวจ endpoint ด้วยวิธีของ stack/provider ที่เป็น official และห้ามพิมพ์ token ลง terminal history/log

## Acceptance matrix

| Client | Demo OAuth | Consent Allow/Deny | Role/Branch RLS | Tools read-only | Revoke/Reconnect | สถานะ |
| --- | --- | --- | --- | --- | --- | --- |
| ChatGPT | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | NOT VERIFIED จนมีหลักฐาน |
| Claude | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | NOT VERIFIED จนมีหลักฐาน |
| Client อื่น | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | ต้องทดสอบ | NOT VERIFIED จนมีหลักฐาน |

---

# Option 2.3 — Project ↔ LINE แบบ 2-way ผ่าน MCP

## สถานะ

**PLANNED / UNDER STUDY — ยังไม่ใช่ authorization ให้พัฒนา เปิด webhook ส่งข้อความจริง หรือเปลี่ยนข้อมูล**

เป้าหมายที่กำลังศึกษา:

- Project → LINE: Project/AI/MCP เลือกผู้รับและส่งข้อความผ่านฝั่ง LINE ที่ได้รับอนุญาต
- LINE → Project: รับ webhook, ตรวจผู้ส่ง, map LINE user กับบัญชี project, เรียก MCP ตาม role/branch แล้วส่งคำตอบกลับ
- ใช้ MCP ของแต่ละฝั่งโดยมี trust boundary ชัดเจน

ก่อนออกแบบหรือพัฒนา ต้องยืนยัน:

- use cases, ผู้ส่ง/ผู้รับ, consent และการยกเลิกการเชื่อมบัญชี
- LINE signature verification, timestamp/replay protection และ idempotency
- mapping ระหว่าง LINE user ID กับ project user
- role/branch enforcement ทุก tool call
- read-only กับ write/approval boundary
- message retention, PII masking, audit, rate limit และ incident handling
- webhook/reply/push API, callback/domain และ secrets แยก Demo/Production
- human approval สำหรับข้อความหรือ action สำคัญ
- loop prevention ระหว่าง Project ↔ LINE
- fallback เมื่อ AI/MCP/LINE/Lovable/Supabase ไม่พร้อม

ห้ามนำ Option 2.3 ไป Production จนมีเอกสาร architecture, threat model, impact review, test plan, rollback และ owner approval

---

# คำสั่งตรวจรวมก่อน PR จาก Demo → Production

```bash
git branch --show-current
git status --short
git log --oneline --decorate -20
git diff --stat <PRODUCTION_BASE_SHA>...HEAD
git diff --name-status <PRODUCTION_BASE_SHA>...HEAD
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  'SERVICE_ROLE|LOVABLE_API_KEY|SUPABASE_.*KEY|\.supabase\.co|\.lovable\.app|demo|mock|test'
```

ต้องตรวจ diff จริง ไม่ commit secret และไม่ตีความผลจากชื่อไฟล์อย่างเดียว

## Conflict report บังคับ

| ส่วน | Production | Demo option | Conflict/Impact | Test/Rollback | ผลตัดสิน |
| --- | --- | --- | --- | --- | --- |
| Assistant | baseline SHA/behavior | feature SHA/behavior | auth/RLS/AI gateway/UI | matrix + revert | SAFE / REVIEW / DO NOT MERGE |
| MCP | baseline SHA/behavior | feature SHA/behavior | OAuth/RLS/routes/deps | OAuth + RLS + revert | SAFE / REVIEW / DO NOT MERGE |
| External AI | registered clients | demo clients | callback/domain/consent | E2E + revoke | SAFE / REVIEW / DO NOT MERGE |
| LINE 2-way | production integrations | study/demo implementation | webhook/signature/mapping/loop | threat test + disable | SAFE / REVIEW / DO NOT MERGE |

ถ้า evidence ไม่ครบ ให้ใช้ `DO NOT MERGE`
