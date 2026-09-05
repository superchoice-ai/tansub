# Lovable.MD — กฎบังคับและ Runbook สำหรับโปรเจกต์ที่ใช้ Lovable

> [!CAUTION]
> **ทุกคนและทุก AI ต้องอ่านไฟล์นี้ให้ครบก่อนคิด วางแผน แก้ไข ทดสอบ commit merge publish deploy หรือเปลี่ยนข้อมูลใด ๆ ใน repository นี้**
>
> กฎนี้ใช้ทันทีเมื่อ repository มีการพัฒนา เชื่อมต่อ หรือร่วมใช้ Lovable แม้เพียงส่วนเล็กน้อย และใช้ร่วมกับ `AGENTS.md` และ `AI_ENGINEERING_COPILOT.md` โดยให้ใช้กฎที่เข้มงวดกว่าหากมีข้อขัดแย้ง

## วัตถุประสงค์

Lovable Remix ไม่ใช่การ clone Backend/Database แบบรับประกัน 100% โค้ดอาจถูกคัดลอก แต่ environment secrets, service-role binding, Auth trigger, integration secrets, callback URL, storage, scheduled jobs หรือ schema บางส่วนอาจยังชี้โปรเจกต์เดิมหรือไม่ถูกคัดลอกมา

เป้าหมายของ Runbook นี้คือทำให้ Remix แยกจากโปรเจกต์เดิม และชี้ FE/BE/DB ไปยังโปรเจกต์ใหม่อย่างพิสูจน์ได้ โดยห้ามใช้คำว่า “ครบ 100%” จากการที่หน้าเว็บเปิดได้เพียงอย่างเดียว ต้องผ่าน Gate 1–5 และมีหลักฐานครบทุกข้อที่เกี่ยวข้อง

## กฎสูงสุด

- ห้ามทำงานบน `main`; ใช้ non-main branch เท่านั้น จนกว่าจะ review และได้รับอนุญาตให้ merge/publish
- ห้ามแก้ไฟล์ `.env` หรือไฟล์ client ที่ Lovable สร้างให้อัตโนมัติด้วยมือ ให้ rebind ผ่านเครื่องมือ secrets/environment ของแพลตฟอร์ม
- ห้ามแสดง บันทึก หรือ commit secret/key/token
- ก่อน write ต้องตรวจ official status ของ Lovable, Supabase และ GitHub พร้อมเวลา/timezone และทดสอบเส้นทางจริงแบบ read-only
- ทดสอบด้วยข้อมูลสังเคราะห์ที่สร้างใหม่เท่านั้น ห้ามใช้หรือแก้ข้อมูลเดิม
- ห้ามลบข้อมูลทดสอบจนเจ้าของอนุญาต และเมื่อลบต้องลบ child → root ใน transaction พร้อมตรวจ orphan
- SQL ในเอกสารนี้เป็นแม่แบบ ต้องตรวจชื่อ schema/table/function/signature ของ repo ปัจจุบันก่อนใช้
- ถ้า project ref, target environment, permission, data lineage, impact หรือ rollback ไม่ชัด ให้ STOP/NO-GO และถามเจ้าของ
- ห้ามใช้ rollback แบบกว้าง เช่น `GRANT EXECUTE ON ALL FUNCTIONS ... TO anon`

---

# ขั้นตอน 1 — Readiness, Scope และ Baseline (ห้ามเขียนข้อมูล)

บันทึกก่อนเริ่ม:

- repository, branch, Lovable project, environment (Dev/Preview/Prod)
- old project ref และ new project ref
- สิ่งที่อนุญาตและยังไม่อนุญาต
- official status พร้อม timestamp/timezone
- rollback owner และหลักฐาน baseline

ตรวจ branch และสถานะ working tree:

```bash
git branch --show-current
git status --short
```

ต้องไม่ใช่ `main` สำหรับงานพัฒนา/แก้ไข ตรวจไฟล์ที่มีผลต่อการเชื่อมต่อ:

```bash
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  'VITE_SUPABASE|SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|SUPABASE_SERVICE_ROLE_KEY|project_id|supabase\.co|lovable\.app'
```

ตรวจเฉพาะ “ชื่อ” environment variables ห้ามพิมพ์ค่าคีย์:

```bash
env | cut -d= -f1 | rg '^(VITE_SUPABASE_|SUPABASE_)'
```

ตรวจ config migration:

```bash
sed -n '1,120p' supabase/config.toml
```

Read-only database baseline:

```sql
select current_database(), current_setting('server_version');
select count(*) from public.branches;
select count(*) from auth.users;
select count(*) from public.profiles;
select count(*) from public.user_roles;
```

ผลขั้นตอน 1 ต้องระบุ `GO`, `LIMITED GO` หรือ `NO-GO` ก่อนทำขั้นตอน 2

---

# ขั้นตอน 2 — Inventory และพิสูจน์ Target Project

กำหนด expected new project ref โดยไม่แสดง secret แล้วตรวจให้ตรงกันทุกชั้น:

1. Lovable project ปัจจุบัน
2. Client build-time: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID`
3. Server runtime: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
4. Migration CLI: `supabase/config.toml`
5. Source clients/middleware ต้องอ่านจาก environment และไม่มี hardcode
6. Integration secrets, Storage, Auth providers, Edge Functions, webhook/callback และ scheduled jobs

ค้นหา old ref/URL/domain ทั้ง repository:

```bash
OLD_PROJECT_REF='<OLD_PROJECT_REF>'
rg -n --hidden --glob '!.git' --glob '!node_modules' \
  "$OLD_PROJECT_REF|https://[^[:space:]"'\''/]+\.supabase\.co|sb_publishable_|https://[^[:space:]"'\'']+-preview\.lovable\.app"
```

ผลที่พบทุกจุดต้องจำแนกเป็น:

- generated environment: rebind ผ่านแพลตฟอร์ม
- `supabase/config.toml`: เปลี่ยน `project_id` ผ่าน change ที่ review แล้ว
- source hardcode: เปลี่ยนให้อ่าน environment
- documentation/history: ระบุว่าไม่ใช่ runtime reference
- unknown: STOP และตรวจต่อ ห้ามเดา

ห้ามสรุปว่าผูกโปรเจกต์ใหม่จาก URL ฝั่ง FE อย่างเดียว

---

# ขั้นตอน 3 — Rebind FE/BE และ Restart Runtime

ใช้เครื่องมือ Lovable/Cloud rebind secrets ให้ค่าต่อไปนี้มาจากโปรเจกต์ใหม่ชุดเดียวกัน:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_SUPABASE_PROJECT_ID`

จากนั้นตรวจ `supabase/config.toml` ให้ `project_id` ตรงกับ new project ref

รีสตาร์ท dev server เฉพาะ environment ของ Lovable ที่ยืนยันแล้ว:

> [!WARNING]
> คำสั่งนี้ส่ง `SIGKILL` ให้ process Vite/Bun ที่ match ใน container ปัจจุบัน ใช้เฉพาะ dev container ที่ตรวจแล้วว่าไม่มี process อื่นร่วมอยู่ ห้ามใช้บนเครื่อง/production host ที่ไม่ทราบขอบเขต

```bash
kill -9 $(ps -ef | grep -E '[v]ite|bun run dev' | grep -v grep | awk '{print $2}'); for i in $(seq 1 40); do curl -sf -o /dev/null http://localhost:8080/ && echo UP && break; sleep 1; done; grep -c . .env
```

ข้อควรทราบ:

- `grep -c . .env` ตรวจเพียงจำนวนบรรทัดที่ไม่ว่าง ไม่ได้พิสูจน์ว่าค่าถูกต้อง และห้ามแสดงเนื้อหา `.env`
- ถ้าไม่มี PID หรือ server ไม่ขึ้นภายใน 40 วินาที ให้หยุดและตรวจ log; ห้ามวนรันแบบเดาสุ่ม
- หลัง restart ต้องตรวจ project identity จาก URL/ref ที่ไม่เป็น secret และทำ read-only probe

ตัวอย่าง health/read probe โดยใช้ค่าจาก environment โดยไม่พิมพ์ key:

```bash
curl -fsS -o /dev/null -w 'AUTH %{http_code}\n' "$SUPABASE_URL/auth/v1/health"
curl -fsS -o /dev/null -w 'REST %{http_code}\n' \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  "$SUPABASE_URL/rest/v1/branches?select=id&limit=1"
curl -fsS -o /dev/null -w 'APP %{http_code}\n' http://localhost:8080/auth
```

ต้องได้ HTTP 200 ตาม endpoint ที่มีจริงใน repo นั้น หาก endpoint/table ต่างกันให้ปรับหลังตรวจ schema ห้ามสร้าง endpoint เพื่อให้ test ผ่าน

---

# ขั้นตอน 4 — ตรวจและซ่อม DB/Auth/RLS/Functions

## 4.1 ตรวจ schema และ Auth trigger

```sql
select count(*) as public_tables
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE';

select count(*) as policies from pg_policies where schemaname = 'public';

select count(*) as triggers
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal;

select t.tgname,
       n.nspname as schema_name,
       c.relname as table_name,
       p.proname as function_name
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where not t.tgisinternal
  and n.nspname = 'auth'
  and c.relname = 'users';
```

ถ้า repo นี้ออกแบบให้ signup เรียก `public.handle_new_user()` แต่ไม่มี trigger ให้สร้างผ่าน migration ที่ review แล้ว:

```sql
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();
```

ห้ามรันเพียงเพราะชื่อเหมือนกัน ต้องตรวจ function definition, side effects, constraints และ rollback ก่อน

## 4.2 Backfill เฉพาะบัญชีที่ขาด

แม่แบบจากเหตุการณ์ Tansub; ใช้ได้ต่อเมื่อ schema/enum/สำนักงานใหญ่ตรงกันและเจ้าของอนุญาตให้เปลี่ยนข้อมูล:

```sql
WITH hq AS (
  SELECT id FROM public.branches WHERE is_hq LIMIT 1
),
missing AS (
  SELECT
    u.id,
    u.email,
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
SELECT
  m.id,
  CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM public.user_roles WHERE role = 'admin'
    ) AND m.rn = 1
    THEN 'admin'::public.app_role
    ELSE 'staff'::public.app_role
  END
FROM missing m
WHERE m.id IN (SELECT id FROM ins)
ON CONFLICT (user_id, role) DO NOTHING
RETURNING user_id, role;
```

> [!CAUTION]
> การตั้ง “บัญชีแรกที่ขาด” เป็น admin เป็น business/security decision ไม่ใช่ค่า default สากล ต้องยืนยันตัวบุคคลและ role ก่อนรัน หากไม่ยืนยันให้ backfill profile โดยไม่ยกระดับสิทธิ์

## 4.3 ตรวจ RPC ที่โค้ดเรียก

```bash
rg -o "rpc\(\s*[\"'][a-z_]+" -N src | sort -u
```

เทียบกับ function signatures และ grants ในฐานข้อมูล ห้าม grant จากการเดาชื่อ

## 4.4 จำกัด SECURITY DEFINER

ตรวจสิทธิ์ก่อนแก้:

```sql
select
  n.nspname,
  p.proname,
  p.oid::regprocedure::text as signature,
  p.prosecdef,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;
```

ตัด blanket access หลัง impact review:

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

จากนั้น:

- revoke `authenticated` จาก trigger/internal helpers
- grant `authenticated` เฉพาะ RLS helpers และ RPC ที่ FE/BE เรียกจริง
- grant `service_role` เฉพาะตาม server/admin design
- ตรวจ function body ทุกตัวว่าเช็ก role/branch ภายใน และตั้ง `search_path` อย่างปลอดภัย
- `integration_secrets` อาจ intentionally ไม่มี table policy และเข้าผ่าน security-definer RPC เท่านั้น แต่ต้องพิสูจน์ว่า `anon` ไม่มี table/function access

ตัวอย่างรายชื่อจาก Tansub เท่านั้น ห้ามคัดลอกไป repo อื่นโดยไม่ตรวจ:

```sql
REVOKE ALL ON FUNCTION public.guard_collection_contract_lifecycle() FROM authenticated;
REVOKE ALL ON FUNCTION public.guard_contract_cancel_request() FROM authenticated;
REVOKE ALL ON FUNCTION public.guard_contract_first_payment_at() FROM authenticated;
REVOKE ALL ON FUNCTION public.guard_payment_void_request() FROM authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM authenticated;
REVOKE ALL ON FUNCTION public.mark_contract_payment_event() FROM authenticated;
REVOKE ALL ON FUNCTION public.prevent_payment_physical_delete() FROM authenticated;
REVOKE ALL ON FUNCTION public.set_updated_at() FROM authenticated;
REVOKE ALL ON FUNCTION public.mask_secret(text) FROM authenticated;
REVOKE ALL ON FUNCTION public.perform_contract_cancel(uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.perform_payment_void(uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.execute_approval_request_phase_a_contract_cancel(uuid, boolean, text) FROM authenticated;

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

ห้ามใช้ rollback กว้างนี้:

```sql
-- ห้ามใช้: เปิดสิทธิ์มากเกินขอบเขต
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
```

Rollback ต้อง restore เฉพาะ signature/role จาก permission snapshot ก่อนแก้

---

# ขั้นตอน 5 — Validation, Regression, Evidence และ Acceptance

## 5.1 Build/typecheck

ใช้ script ของ repo ก่อน:

```bash
bun run build
bunx tsgo --noEmit
```

ถ้า repo ใช้ npm:

```bash
npm run build
npm run lint
```

ตรวจ build log:

```bash
tail -30 /tmp/observability/build-errors.log 2>/dev/null || echo "no log"
```

คำสั่งแก้ TypeScript แบบแทนข้อความหลายไฟล์ที่เคยใช้ในเหตุการณ์ Tansub เป็น incident-specific patch เท่านั้น ห้ามรันซ้ำโดยอัตโนมัติ ต้องอ่าน error และแก้ด้วย patch ที่ตรงกับ revision ปัจจุบัน

## 5.2 Database acceptance

ต้องเก็บผลอย่างน้อย:

- DB connection และ version
- REST/Data API 200
- Auth health 200
- App 200
- ตารางหลักทั้งหมดอ่านได้
- จำนวน schema tables, RLS policies และ non-internal triggers
- `auth.users` ทุกบัญชีที่อยู่ใน scope มี `profiles/user_roles` ตาม business rule
- `anon` ไม่มี table access หรือ execute access ที่ไม่ควรมี
- `authenticated` เรียกเฉพาะ RPC/RLS helper ที่จำเป็น
- `service_role` ทำ server-side path ที่จำเป็นได้
- integration secrets อยู่ใน DB ใหม่และอ่านกลับแบบ masked
- Storage, Edge Functions, webhook/callback, scheduled jobs และ external integrations ที่ใช้งานจริงชี้ project/domain ใหม่

## 5.3 FE smoke/regression

ใช้ Incognito/new session และข้อมูลทดสอบใหม่ที่มี run ID:

1. สมัครบัญชีใหม่
2. ยืนยัน trigger สร้าง `profiles/user_roles`
3. Login และตรวจชื่อ role สาขา
4. เปิดทุกหน้าหลักที่ระบบใช้จริง
5. สร้างข้อมูลใหม่หนึ่งสายงานและตรวจ read/update/workflow ตาม scope
6. ตรวจ RLS ด้วย role และสาขาต่างกัน
7. ตรวจ approval, contract, payment, report, audit และ notification ตามที่ repo มี
8. logout/login ใหม่และตรวจ persistence
9. ตรวจ project เก่าว่าไม่มี user/record/run ID ใหม่
10. ตรวจ project ใหม่ว่ามี user/record/run ID ครบ
11. เก็บ evidence และห้ามลบจนเจ้าของอนุญาต

## 5.4 เกณฑ์ “แยกอิสระ 100%”

อนุญาตให้รายงานว่าแยกจาก project เดิมครบ 100% เฉพาะ “ขอบเขตที่ inventory ครบและทดสอบแล้ว” เมื่อ:

- FE build-time, BE runtime และ migration config ตรง new project ref
- ไม่พบ runtime hardcode ของ old project
- schema/Auth/RLS/functions/grants ถูกต้อง
- external integrations ทั้งหมดใน inventory ชี้ project/domain ใหม่
- old project ไม่ได้รับ write ระหว่าง end-to-end test
- new project รับ read/write ครบ
- build และ regression ผ่าน
- มี rollback แบบเจาะจงและ evidence ครบ

ถ้ามี Storage, Edge Function, webhook, scheduled job, callback, secret หรือเส้นทางที่ยังไม่ตรวจ ต้องรายงาน `UNKNOWN/NOT VERIFIED` และห้ามใช้คำว่า 100%

## 5.5 ก่อน merge/publish

- ตรวจ diff และดึง `main` ล่าสุดเข้า branch
- ตรวจว่าไม่มี secret, test artifact, debug code หรือ scope อื่นติดมา
- ขออนุญาต merge เข้า `main`
- หลัง merge ให้ตรวจ Lovable sync และ branch/environment อีกครั้ง
- ขออนุญาต publish production แยกต่างหาก
- หลัง publish ทำ read-only health + regression ที่จำเป็น

## Rollback แบบปลอดภัย

- rebind secrets กลับ project ref เดิมผ่านแพลตฟอร์ม
- restore `supabase/config.toml` จาก commit/snapshot ที่ยืนยันแล้ว
- restart dev server
- restore trigger/function grants เฉพาะรายการที่เปลี่ยน
- คง backfilled users/profiles ไว้ เว้นแต่ได้รับอนุญาตลบแบบระบุ ID
- ห้ามลบข้อมูลธุรกิจเดิม
- ตรวจทั้ง old/new project หลัง rollback และบันทึก evidence

## บทเรียนอ้างอิงจากเหตุการณ์ Tansub

- service-role key ของ project เดิมค้างหลัง Remix
- rebind secrets และ restart ทำให้ runtime ชี้ DB ใหม่
- `on_auth_user_created` ไม่ถูกคัดลอก ทำให้ signup มี `auth.users` แต่ไม่มี `profiles/user_roles`
- ต้องสร้าง trigger และ backfill หลังตรวจ business role
- Security linter ลดจาก 64 → 37 โดยตัด anon-executable SECURITY DEFINER 19 → 0
- คำเตือน Anonymous Access Policies ต้องพิสูจน์จาก policy roles + table grants + anonymous API test ไม่ใช่สรุปจาก linter อย่างเดียว
- `integration_secrets` ถูกล็อกโดยเจตนาและเข้าผ่าน RPC
- หน้า FE เปิดได้หรือ build ผ่านอย่างเดียวไม่พิสูจน์ว่า Backend/DB แยกครบ
