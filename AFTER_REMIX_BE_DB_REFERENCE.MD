# AFTER_REMIX_BE_DB_REFERENCE.MD

## Reusable FE/BE/DB Project-Switch Reference

> [!CAUTION]
> อ่าน `Lovable.MD`, `DEMO_OPTION_LOVABLE.MD`, `DEMO_OPTION_ASSISTANT_REFERENCE.MD` และ `DEMO_OPTION_MCP_REFERENCE.MD` ก่อน
>
> ไฟล์นี้เป็น reusable implementation baseline สำหรับ Lovable Remix/Clone ที่ต้องแยก FE, BE และ DB ออกจาก project เดิม ไม่ใช่ raw execution log และไม่รับประกันว่าไม่มี impact จนกว่าจะตรวจและทดสอบ project ปัจจุบันครบ

## Success contract

ใช้คำว่า “แยกอิสระ 100%” ได้เฉพาะขอบเขตที่พิสูจน์แล้วว่า:

- FE build-time, BE runtime และ migration config ชี้ new project เดียวกัน
- ไม่มี runtime hardcode หรือ secret binding ของ old project
- Auth, schema, trigger, RLS, grants และ functions ถูกต้อง
- Storage, Edge Functions, webhooks, jobs, callbacks และ integrations ชี้ target ใหม่
- E2E write เข้า new project และไม่ปรากฏใน old project
- Build, typecheck, security และ regression ผ่าน
- มี evidence manifest และ rollback แบบเจาะจง

ส่วนใดไม่ตรวจให้ระบุ `UNKNOWN / NOT VERIFIED` ห้ามสรุป 100%

## Project Adaptation Record

| รายการ | Old | New/Target | Evidence |
| --- | --- | --- | --- |
| Repo/branch/SHA | TBD | TBD | Git |
| Lovable project ID/domain | TBD | TBD | Platform |
| Supabase project ref | TBD | TBD | Non-secret identity |
| FE variables | TBD | TBD | Build config |
| BE variables/service role | TBD | TBD | Runtime binding |
| Migration config | TBD | TBD | config.toml |
| Auth providers/callbacks | TBD | TBD | Provider |
| Schema/triggers/RLS/grants | TBD | TBD | Catalog |
| Storage/functions/jobs/webhooks | TBD | TBD | Inventory |
| Integration secrets | TBD | TBD | Masked inventory |
| Test run ID | n/a | TBD | Manifest |
| Rollback snapshot | TBD | TBD | Evidence |

Security/data identity มี `TBD` = `NO-GO`

# ขั้นตอน 1 — Readiness และค้นค่า Project เดิม

บันทึก scope, exclusions, authorization, environment, official status, timestamp/timezone และ branch ก่อน write

```bash
git branch --show-current
git status --short
git log --oneline --decorate -10
```

ห้ามพิมพ์ secret:

```bash
env | cut -d= -f1 | rg '^(VITE_SUPABASE_|SUPABASE_)'
sed -n '1,120p' supabase/config.toml
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  'VITE_SUPABASE|SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|SUPABASE_SERVICE_ROLE_KEY|project_id|supabase\.co|lovable\.app'
```

กำหนดเฉพาะ identity ที่ไม่เป็น secret:

```bash
OLD_PROJECT_REF='<OLD_PROJECT_REF>'
NEW_PROJECT_REF='<NEW_PROJECT_REF>'
OLD_LOVABLE_PROJECT='<OLD_PROJECT_OR_DOMAIN>'
NEW_LOVABLE_PROJECT='<NEW_PROJECT_OR_DOMAIN>'
```

```bash
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  "$OLD_PROJECT_REF|$OLD_LOVABLE_PROJECT|https://[^[:space:]\"'/]+\.supabase\.co|sb_publishable_|https://[^[:space:]\"']+\.lovable\.app"
rg -n "createClient|SUPABASE_|VITE_SUPABASE_|Authorization|SERVICE_ROLE" \
  src supabase vite.config.* package.json
```

จำแนกทุกผลเป็น generated environment, config, runtime hardcode, documentation/history หรือ unknown ถ้า unknown ให้ STOP

Read-only baseline:

```sql
select current_database(), current_setting('server_version'), now();
select count(*) from auth.users;
select table_schema, count(*)
from information_schema.tables
where table_type = 'BASE TABLE'
group by table_schema
order by table_schema;
```

Timeout/404 ครั้งแรกไม่พิสูจน์ว่า DB เสีย ต้องตรวจ official status และ direct project-path probe

# ขั้นตอน 2 — Rebind FE/BE และ Migration Target

Rebind ผ่าน supported platform tooling เท่านั้น:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_SUPABASE_PROJECT_ID`

ห้ามแก้ generated `.env` หรือ generated Supabase client ด้วยมือ

```toml
project_id = "<NEW_PROJECT_REF>"
```

ตรวจ client, server, middleware, Assistant และ MCP ว่าใช้ target เดียวกัน

### Restart command จาก incident

> [!WARNING]
> ใช้เฉพาะ isolated Lovable dev container ที่ตรวจแล้ว คำสั่งนี้ SIGKILL ทุก Vite/Bun process ที่ match ห้ามใช้บน shared host/production

```bash
kill -9 $(ps -ef | grep -E '[v]ite|bun run dev' | grep -v grep | awk '{print $2}'); for i in $(seq 1 40); do curl -sf -o /dev/null http://localhost:8080/ && echo UP && break; sleep 1; done; grep -c . .env
```

`grep -c . .env` ตรวจเพียงจำนวนบรรทัดไม่ว่าง ไม่พิสูจน์ว่าค่าถูก ก่อนใช้ควรตรวจ process:

```bash
ps -ef | rg 'vite|bun run dev'
```

Health probes:

```bash
curl -fsS -o /dev/null -w 'AUTH %{http_code}\n' "$SUPABASE_URL/auth/v1/health"
curl -fsS -o /dev/null -w 'REST %{http_code}\n' \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  "$SUPABASE_URL/rest/v1/branches?select=id&limit=1"
curl -fsS -o /dev/null -w 'APP %{http_code}\n' http://localhost:8080/auth
```

ปรับ table/route ตาม schema จริง ห้ามสร้าง endpoint เพื่อให้ test ผ่าน

# ขั้นตอน 3 — Auth, Schema, RLS และ Functions

Inventory:

```sql
select count(*) as public_tables
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE';

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

select t.tgname, n.nspname as schema_name, c.relname as table_name,
       p.oid::regprocedure::text as function_signature
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where not t.tgisinternal
order by n.nspname, c.relname, t.tgname;
```

Remix อาจไม่คัดลอก trigger ใน `auth` หาก confirmed design ใช้ `handle_new_user()` และตรวจ function body/side effects แล้ว:

```sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();
```

ตรวจ missing profile/role:

```sql
select u.id, u.email, u.created_at,
       (p.id is not null) as has_profile,
       exists (select 1 from public.user_roles ur where ur.user_id = u.id) as has_role
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at;
```

Backfill template จาก Tansub ใช้ได้ต่อเมื่อ schema/HQ/enum ตรงและ owner อนุญาต:

```sql
WITH hq AS (
  SELECT id FROM public.branches WHERE is_hq LIMIT 1
),
missing AS (
  SELECT u.id, u.email,
         coalesce(u.raw_user_meta_data->>'full_name', '') AS fn,
         row_number() over (order by u.created_at) AS rn
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE p.id IS NULL
),
ins AS (
  INSERT INTO public.profiles (id, full_name, email, branch_id)
  SELECT m.id, m.fn, m.email, (SELECT id FROM hq)
  FROM missing m
  RETURNING id
)
INSERT INTO public.user_roles (user_id, role)
SELECT m.id,
  CASE
    WHEN NOT EXISTS (SELECT 1 FROM public.user_roles WHERE role = 'admin')
         AND m.rn = 1
    THEN 'admin'::public.app_role
    ELSE 'staff'::public.app_role
  END
FROM missing m
WHERE m.id IN (SELECT id FROM ins)
ON CONFLICT (user_id, role) DO NOTHING
RETURNING user_id, role;
```

ห้ามกำหนดบัญชีแรกเป็น admin อัตโนมัติ ต้องยืนยันบุคคลและ role ก่อน

ตรวจ RPC ที่ source เรียก:

```bash
rg -o "rpc\(\s*[\"'][a-zA-Z0-9_]+" -N src | sort -u
```

ตรวจ function grants:

```sql
select n.nspname, p.proname, p.oid::regprocedure::text as signature,
       p.prosecdef,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as service_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;
```

หลัง impact review จึงตัด blanket access:

```sql
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
  END LOOP;
END $$;
```

จากนั้น grant `authenticated` เฉพาะ RLS helpers/RPC ที่ source ใช้จริง และ revoke trigger/internal helpers ราย signature

ตัวอย่าง Tansub เท่านั้น:

```sql
GRANT EXECUTE ON FUNCTION public.can_access_branch(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_hq(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_manager() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_branch(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.next_doc_no(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.global_customer_history_search(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.execute_approval_request(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_integration_secrets() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_integration_secret(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_integration_secret(text) TO authenticated;
```

ห้าม rollback แบบกว้าง:

```sql
-- DO NOT RUN
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
```

Rollback ต้อง restore ราย signature/role จาก permission snapshot เท่านั้น

# ขั้นตอน 4 — External Resources และ Data Integrity

Inventory และยืนยัน target ของ:

- Auth providers และ callback/redirect URLs
- Storage buckets/objects/policies
- Edge/server functions และ secrets
- MCP issuer, endpoint, OAuth clients และ consent
- AI gateway keys/model configuration
- LINE Login/OA/webhook/reply/push callbacks
- scheduled jobs, queues, cron และ webhooks
- integration secrets ใน DB ใหม่ โดยอ่านกลับแบบ masked
- DNS/custom domains และ preview/production domains

ห้าม copy secret ผ่าน chat/log/repository ให้กรอก/rebind ผ่าน supported platform UI/tool

สร้าง test data ใหม่ด้วย unique run ID ห้ามแก้ข้อมูลเดิม เก็บ creation manifest/lineage และห้ามลบจน owner อนุญาต

# ขั้นตอน 5 — Validation, Main ↔ Demo และ Rollback

Build:

```bash
bun run build
bunx tsgo --noEmit
tail -30 /tmp/observability/build-errors.log 2>/dev/null || echo "no log"
```

หรือ scripts ของ repo:

```bash
npm run build
npm run lint
```

Acceptance matrix:

| Layer | ต้องพิสูจน์ |
| --- | --- |
| FE | Build-time ref/URL เป็น new project |
| BE | Runtime URL/publishable/service-role bindings เป็น new project |
| Migration | config target เป็น new project |
| DB | connection/version และ tables ตรง inventory |
| Auth | signup ใหม่สร้าง profile/role ตาม design |
| RLS | anon/staff/manager/admin และ cross-branch matrix ผ่าน |
| Functions | anon ไม่มี execute เกินจำเป็น; authenticated/service role ตรง design |
| Assistant/MCP | user token + RLS; ไม่มี service-role privilege bypass |
| Storage | upload/read/delete ตาม role และ target bucket |
| External | callbacks/webhooks/jobs/LINE/AI ชี้ target |
| Old project negative check | ไม่มี run ID/user/file/event ใหม่ |
| New project positive check | มี run ID/user/file/event ตามที่คาด |
| Build/regression | ผ่านทุกเส้นทางที่เกี่ยวข้อง |

FE smoke test:

1. Incognito/new session
2. สมัครบัญชีทดสอบใหม่
3. ตรวจ `auth.users → trigger → profiles → user_roles`
4. Login และตรวจ role/branch
5. เปิดทุกหน้าหลัก
6. สร้างข้อมูลใหม่หนึ่งสายงานและตรวจ audit
7. ทดสอบ RLS ต่าง role/branch
8. ทดสอบ Assistant/MCP/Storage/integrations ที่อยู่ใน scope
9. Logout/login แล้วตรวจ persistence
10. ตรวจ old project ว่าไม่มี test run ID
11. ตรวจ new project ว่ามี test run ID ครบ
12. เก็บ evidence ห้ามลบจนอนุญาต

Main ↔ Demo ต้องใช้ PR เสมอ:

```bash
git diff --stat <TARGET_BASE_SHA>...HEAD
git diff --name-status <TARGET_BASE_SHA>...HEAD
git diff <TARGET_BASE_SHA>...HEAD -- \
  package.json vite.config.ts supabase src
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  'SERVICE_ROLE|SUPABASE_.*KEY|\.supabase\.co|\.lovable\.app|demo|mock|test'
```

เปรียบเทียบ source กับ Reference นี้และ target baseline พร้อมรายงาน `SAFE TO MERGE`, `MERGE WITH REVIEW` หรือ `DO NOT MERGE`

Rollback:

- rebind secrets กลับ snapshot/project เดิมผ่าน platform
- restore `supabase/config.toml`
- restart runtime
- restore trigger/grants ราย object/signature
- disable/revert external callbacks, MCP และ jobs ที่เพิ่ม
- ห้ามลบ backfilled user/business data เว้นแต่มี exact-ID approval
- ตรวจ old/new project หลัง rollback
- rerun Auth/App/RLS regression
- บันทึก evidence

## Raw-log prohibition

ห้ามนำ raw execution log เดิมเข้า repo หรือ copy command/code โดยไม่จัด scope เพราะ log อาจมี project-specific ref/schema, SQL ยกระดับสิทธิ์, duplicated edits, unsafe environment inspection หรือ build fix เฉพาะเหตุการณ์

ใช้ source ปัจจุบัน + Project Adaptation Record + Reference นี้เท่านั้น
