# Tansub — PC App vs Web App Architecture Map

> Purpose: คู่มือสำหรับคนที่มีพื้นฐาน PC Application / Web Form / Database แต่ยังไม่คุ้นกับโครงสร้าง Web App สมัยใหม่
>
> Scope: อธิบายจากโครงสร้างจริงของ repository `superchoice-ai/tansub` บน branch `main` ณ 2026-08-29 โดยเน้นว่า "ถ้าจะไปแก้เอง ต้องไปแก้ตรงไหน"

---

## 1. ภาพใหญ่: PC App ที่คุ้นเคย vs Tansub Web App

| สิ่งที่คุ้นจาก PC App / Web Form แบบเดิม | Tansub Web App | หน้าที่แบบเข้าใจง่าย | ตัวอย่างใน Tansub |
|---|---|---|---|
| Form / Screen | React component + route | หน้าจอที่ผู้ใช้เห็น | `src/routes/_authenticated/customers/index.tsx` |
| Button / Event | React event / mutation | เมื่อกดปุ่มแล้วให้ทำอะไร | ปุ่ม "บันทึกข้อมูล" เรียก `createCustomer.mutate()` |
| Code Behind | Server function / server route | Logic ฝั่ง server | `src/routes/**`, `src/*.functions.ts`, middleware ที่เกี่ยวข้อง |
| Database connection | Supabase client | ช่องทางติดต่อฐานข้อมูล | `src/integrations/supabase/client.ts` |
| SQL SELECT | `supabase.from(...).select(...)` หรือ RPC | อ่านข้อมูล | Customers page อ่านจาก `customers` |
| SQL INSERT | `supabase.from(...).insert(...)` หรือ RPC | เพิ่มข้อมูล | เพิ่ม customer ใน `customers` |
| SQL UPDATE | `supabase.from(...).update(...)` หรือ RPC | แก้ข้อมูล | Payment มี update path; Customer edit ถูกออกแบบเป็น approval request |
| Stored Procedure | Supabase RPC | เรียก function ใน DB | `next_doc_no`, `global_customer_history_search` |
| Session / Login | Supabase Auth | รู้ว่าใคร login | `useAuth`, Supabase auth |
| Permission check | RLS + Auth middleware + application rules | ใครทำอะไรได้ | `requireSupabaseAuth` และ DB/RLS |
| Web server | TanStack Start / Nitro / deployment platform | ประมวลผล request ฝั่ง server | `@tanstack/react-start`, `nitro` |
| Web server config | Environment Variables | ค่าตั้งระบบที่ไม่ควร hard-code | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` |
| IP ของ DB Server | Managed Supabase endpoint | โดยทั่วไปไม่ต้องรู้ IP จริง | ใช้ `SUPABASE_URL` แทน |
| EXE / Installer | Browser + deployed web app | ผู้ใช้ไม่ต้องติดตั้ง EXE | เปิด URL ผ่าน browser |

---

## 2. แผนผัง Tansub แบบ "เดินข้อมูล"

```text
ผู้ใช้
  |
  v
Browser (Chrome / Safari / Edge)
  |
  | 1. เปิดหน้า /customers
  v
FE: React + TanStack Router
  |
  | 2. กดค้นหา / บันทึก / เปิดรายการ
  v
Data access / Server logic
  |
  +--> Supabase Client --------------------+
  |                                         |
  +--> TanStack Start server / middleware   |
                                            v
                                      Supabase
                                            |
                                  +---------+---------+
                                  |                   |
                                Auth               PostgreSQL
                                  |                   |
                                  |             tables / views
                                  |             functions / RPC
                                  |             RLS / triggers
                                  v                   v
                              User/session       ข้อมูลธุรกิจ
```

**จำง่าย:** Web App ไม่ได้หมายความว่า "ทุกอย่างอยู่ในหน้าเว็บ" แต่เป็นหลายชั้นที่คุยกันผ่าน HTTP/SDK/API

---

## 3. ตารางหลัก: ไฟล์ไหนทำหน้าที่อะไร

| ชั้น | คำเรียกง่าย ๆ | ไฟล์/โฟลเดอร์ใน Tansub | ทำอะไร | ถ้าจะปรับ UI/Logic ควรเริ่มดูตรงนี้ |
|---|---|---|---|---|
| FE | หน้าจอ | `src/routes/` | หน้าหลักของระบบ | ใช่ |
| FE | ชิ้นส่วนหน้าจอ | `src/components/` | Form, Table, Dialog, Layout ฯลฯ | ใช่ |
| FE | Business helper | `src/lib/` | validation, formatting, data helper | บางกรณี |
| FE | State / data cache | React Query (`@tanstack/react-query`) | โหลด/เก็บ cache/refresh data | บางกรณี |
| Middleware | ด่านตรวจ login | `src/integrations/supabase/auth-middleware.ts` | ตรวจ Bearer token ก่อนให้ server function ทำงาน | ถ้าแก้ auth ต้องดู |
| Middleware | Auth context | `src/integrations/supabase/auth-attacher.ts` | เชื่อมข้อมูล user/session เข้ากับ request | ถ้าแก้ auth ต้องดู |
| BE | Server-side code | `src/routes/`, `src/*.functions.ts`, server modules | Logic ที่ควรทำฝั่ง server | ถ้ามี server action |
| DB connection | Client connection | `src/integrations/supabase/client.ts` | สร้าง Supabase client สำหรับ app | ปกติไม่ต้องแก้ |
| DB connection | Admin connection | `src/integrations/supabase/client.server.ts` | server-only client ด้วย service role | ห้ามเอาไปฝั่ง FE |
| DB | Schema / tables | Supabase project | เก็บข้อมูลจริง | ใช้ migration/SQL ที่ควบคุม |
| DB | Function / RPC | Supabase PostgreSQL functions | Logic ที่ต้องทำใกล้ DB | ใช้เมื่อ business rule อยู่ DB |
| Governance | กฎระบบ | `AGENTS.md`, `docs/*.md` | บอก AI/developer ว่าห้ามทำอะไร/ต้องตรวจอะไร | ควรอ่านก่อนแก้ |

---

## 4. FE คืออะไร? เทียบกับ PC App

| PC App | Web App | ตัวอย่าง |
|---|---|---|
| `FormCustomer` | `customers/index.tsx` + components | หน้าทะเบียนลูกค้า |
| `TextBox` | React `<Input>` | ชื่อ, เบอร์โทร |
| `ComboBox` | Select / searchable component | สถานะ / สาขา |
| `DataGrid` | Table + pagination | รายชื่อลูกค้า |
| `Button_Click` | `onClick` / mutation | กดบันทึก |
| `Form_Load` | `useQuery`, `useEffect` | โหลดข้อมูลเมื่อเปิดหน้า |
| `MessageBox.Show()` | `toast` / Dialog | แจ้งผลบันทึก |
| `Class Customer` | TypeScript interface/type | `CustomerRow` |

### ตัวอย่างจริง

หน้า Customer ใช้ `useQuery` เพื่ออ่านข้อมูล และใช้ `useMutation` สำหรับการบันทึก/ส่งคำขอแก้ไข โดยเรียก Supabase จากหน้าเดียวกันได้ในกรณีที่ออกแบบไว้แบบนั้น

ไฟล์สำคัญ: `src/routes/_authenticated/customers/index.tsx`

---

## 5. BE คืออะไร?

สำหรับคนมาจาก PC App ให้คิดว่า **BE = Code ที่เราไม่อยากให้ browser เป็นคนตัดสินใจเอง**

| PC App | Web App |
|---|---|
| โปรแกรม EXE รัน logic ในเครื่อง | Browser รัน FE; server รัน logic ที่ต้องป้องกัน |
| ต่อ DB จาก application | FE/Server ติดต่อ Supabase ผ่าน client/API |
| Connection string อยู่ใน config | URL/key มาจาก environment variables |
| DLL / class library | server modules / functions / libraries |
| สิทธิ์บางอย่างเช็คใน application | ควรบังคับซ้ำที่ server/DB เช่น Auth/RLS |

Tansub ใช้ TanStack Start และ Vite ตาม `package.json`; มี `@tanstack/react-start`, `vite` และ `nitro` อยู่ใน project dependencies/devDependencies.

---

## 6. Middleware คืออะไร?

ให้คิดว่า Middleware = **รปภ.หน้าประตู**

```text
Browser
   |
   v
Request
   |
   v
Middleware: "มี token ไหม? token ถูกไหม?"
   |
   +---- ไม่ผ่าน ----> Unauthorized
   |
   +---- ผ่าน ------> Server Function / Business Logic
```

Tansub มี `requireSupabaseAuth` ใน `src/integrations/supabase/auth-middleware.ts` ซึ่งตรวจ Authorization Bearer token และตรวจ claims ก่อนส่งต่อ request

**ข้อควรจำ:** Middleware ไม่ใช่ Database และไม่ใช่ FE แต่เป็นด่านกลางก่อนเข้าถึง server logic

---

## 7. Save to DB — เวลากด "บันทึก" เกิดอะไรขึ้น?

### ตัวอย่าง: เพิ่มลูกค้า

```text
กด "บันทึกข้อมูล"
      |
      v
React mutation
      |
      +--> validate form
      |
      +--> ตรวจ duplicate identity
      |
      +--> ขอเลขเอกสารผ่าน RPC: next_doc_no
      |
      +--> INSERT customers
      |
      v
Supabase PostgreSQL
      |
      v
สำเร็จ -> toast + refresh query
```

ใน `customers/index.tsx` มีการเรียก `supabase.from("customers").insert(...)` และเรียก RPC `next_doc_no` ก่อน insert

**เทียบ PC App:** คล้าย `Validate()` → `GetNextDocumentNo()` → `INSERT INTO customers ...` → `RefreshGrid()`

---

## 8. Edit to DB — จุดสำคัญของ Tansub

อย่าคิดว่า "กด Edit = UPDATE DB ทันที" เสมอไป

ใน Tansub ปัจจุบัน **การแก้ข้อมูลลูกค้าในหน้า Customer ถูกออกแบบให้ส่ง `approval_requests` ก่อน** สำหรับ operation ที่ต้องอนุมัติ แทนการ update `customers` ตรง ๆ

```text
ผู้ใช้กด "ขอแก้ไข"
      |
      v
ตรวจข้อมูลใหม่
      |
      v
INSERT approval_requests
      |
      v
ผู้อนุมัติพิจารณา
      |
      v
จึงค่อยดำเนินการเปลี่ยนข้อมูลตาม workflow
```

นี่เป็นตัวอย่างสำคัญว่า **UI action ≠ DB action เสมอไป**

---

## 9. Search from DB — Search มีได้ 2 แบบ

| แบบ | ทำงานอย่างไร | ตัวอย่าง |
|---|---|---|
| DB Query | ให้ DB ค้นข้อมูล | `select(...).eq(...)` |
| RPC Search | เรียก PostgreSQL function | `global_customer_history_search` |
| FE Filter | โหลดข้อมูลแล้วกรองใน browser | `includesThaiSearch(...)` ใน customer list |

หน้า Customer ปัจจุบันโหลด customer สูงสุด 1,000 records แล้วมี filter/search ฝั่ง FE สำหรับรายการที่โหลดมา ขณะเดียวกัน historical search ใช้ RPC `global_customer_history_search`

**ข้อควรจำ:** ถ้าข้อมูลโตมาก การ search ฝั่ง FE ไม่ควรเป็น default ระยะยาว ควรพิจารณาให้ DB/API search เป็นตัวหลัก

---

## 10. Connection String — ต่างจาก PC App อย่างไร?

### PC App แบบเดิม

```text
Server=192.168.1.10;
Database=TANSUB;
User ID=xxx;
Password=xxx;
```

Application ต่อ SQL Server โดยตรง

### Tansub Web App

แนวคิดเป็น:

```text
SUPABASE_URL=<project URL>
SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

Client ฝั่ง browser ใช้ environment variables ผ่าน Vite และ server-side code ใช้ environment variables เช่นกัน

**สำคัญ:** repository มี `.env` แต่คู่มือนี้ไม่แสดงค่าจริงของ secret/key และไม่ควรนำ secret ไป commit ใน source code

---

## 11. Server / IP Address — ต้องรู้ไหม?

สำหรับ Tansub/Supabase แบบ managed **ไม่ควรเริ่มต้นจากการหา IP ของ DB server**

ให้คิดแบบนี้:

```text
PC App ยุคเดิม
App -> 192.168.x.x -> SQL Server

Tansub
Browser / Server -> SUPABASE_URL -> Supabase API -> PostgreSQL
```

ดังนั้นเวลาจะเปลี่ยน environment เช่น Demo / Dev / Prod สิ่งที่สำคัญกว่าการจำ IP คือ **environment variables / Supabase project ที่ application กำลังชี้อยู่**

---

## 12. DB Name — ทำไมไม่เห็นเหมือน SQL Server?

ใน managed PostgreSQL เช่น Supabase ผู้พัฒนา application มักทำงานกับ:

- Project
- Database schema เช่น `public`
- Tables
- Views
- Functions / RPC
- RLS policies
- Migrations

มากกว่าการ hard-code `Server + Database` ใน source code

**สำหรับ Tansub:** source code ฝั่ง app รู้จัก Supabase URL และ key; รายละเอียด PostgreSQL database/schema เป็นส่วนของ Supabase project และ migration/DB governance

---

## 13. Setup FE / BE / Middleware — ถ้าต้องติดตั้งใหม่

| งาน | PC App | Tansub Web App |
|---|---|---|
| Install runtime | .NET/Java/Runtime | Node/Bun + browser tooling ตาม project |
| Install dependency | DLL/NuGet | `package.json` + lockfile |
| Start developer mode | Run EXE / IIS | `npm run dev` (`vite dev`) |
| Build | Compile EXE | `npm run build` (`vite build`) |
| Configure DB | app.config | environment variables / Supabase connection |
| Configure login | AD/custom auth | Supabase Auth |
| Deploy | Copy EXE / IIS | Web hosting/deployment platform |
| Update user | Install new version | Deploy new web version; user refreshes browser |

Project scripts ปัจจุบันมี `dev`, `build`, `build:dev`, `preview`, `lint`, `format`

---

## 14. "ถ้าจะเปลี่ยนอะไร ต้องแก้ไฟล์ไหน?" — Cheat Sheet

| อยากแก้ | เริ่มดูที่ | ตัวอย่าง |
|---|---|---|
| ข้อความบนหน้าจอ | route/component | `src/routes/...` |
| สี/ปุ่ม/กล่อง | component/UI | `src/components/`, `src/components/ui/` |
| เพิ่ม field ใน form | route/component + type/schema | Customer form |
| Validation | schema/helper | `zod` schema / `src/lib/` |
| โหลดข้อมูล | `useQuery` / data function | `supabase.from(...).select(...)` |
| เพิ่มข้อมูล | mutation / server function | `.insert(...)` หรือ RPC |
| แก้ข้อมูล | mutation / approval workflow | `.update(...)` หรือ `approval_requests` |
| ค้นข้อมูล | query / RPC / FE filter | `.select`, RPC, `includesThaiSearch` |
| Login | auth hooks + Supabase auth | `useAuth` / integration |
| สิทธิ์ | middleware + RLS + business rules | `auth-middleware.ts` + DB policies |
| เลขเอกสาร | DB RPC | `next_doc_no` |
| Business rule สำคัญ | `src/lib/` + DB function/policy | identity/approval rules |
| Database schema | migration/SQL governance | `docs/sql/` และ Supabase migrations |
| Environment | `.env` / deployment secrets | `SUPABASE_URL` ฯลฯ |
| กฎที่ AI ต้องทำตาม | `AGENTS.md` | อ่านก่อนให้ AI แก้ code |
| เอกสาร architecture/governance | `docs/` | impact review / infrastructure governance |

---

## 15. ตัวอย่างแบบ "ผมรู้ Web Form แต่ไม่รู้ React"

### งาน A: เพิ่มช่อง "LINE ID"

**PC App mindset:**

```text
Form -> TextBox LINE_ID -> Save()
```

**Tansub mindset:**

```text
Route/Component
   -> state ของ form
   -> validation/schema
   -> mutation
   -> Supabase insert/update/RPC
   -> DB column
```

ต้องตรวจอย่างน้อย 4 จุด:

1. UI มี input หรือยัง
2. Form state มี field หรือยัง
3. Validation schema รับ field หรือยัง
4. Save mutation ส่ง field เข้า DB หรือ workflow หรือยัง

และถ้า DB ยังไม่มี column ต้องเพิ่ม migration ก่อน

---

### งาน B: เปลี่ยนชื่อปุ่ม

เช่น `"บันทึกข้อมูล"` → `"บันทึกและส่งตรวจสอบ"`

โดยทั่วไปเริ่มจาก route/component ที่แสดงปุ่มนั้นได้เลย ไม่จำเป็นต้องแตะ BE หรือ DB ถ้าเป็นแค่ข้อความ

---

### งาน C: เปลี่ยนกฎ "แก้ข้อมูลลูกค้าได้ทันที"

**อย่าเริ่มแก้ปุ่ม**

เพราะนี่เป็น business rule

ให้ trace:

```text
UI
 ↓
mutation
 ↓
approval_requests / server function
 ↓
DB function / RLS / workflow
 ↓
DB
```

ต้องตรวจทั้งเส้นทาง ไม่เช่นนั้น UI อาจดูเหมือนแก้ได้ แต่ DB ยังปฏิเสธ หรือในทางกลับกัน

---

## 16. สิ่งที่ "แก้เองได้ง่าย" กับ "ควรให้ AI/Developer ทำ"

| ระดับ | ตัวอย่าง | ความเสี่ยง | แนะนำ |
|---|---|---:|---|
| 🟢 ง่าย | เปลี่ยน label, placeholder, คำอธิบาย | ต่ำ | ทำเองได้ |
| 🟢 ง่าย | เปลี่ยน layout/column ของ table | ต่ำ-กลาง | ทำเองได้ถ้ารู้ไฟล์ |
| 🟡 กลาง | เพิ่ม field ใน form ที่ DB มีอยู่แล้ว | กลาง | ทำได้ แต่ต้อง trace 4 จุด |
| 🟡 กลาง | เพิ่ม filter/search | กลาง | ทำได้ถ้าเข้าใจ query |
| 🟠 ยาก | เปลี่ยน save/update behavior | สูง | ให้ AI ช่วย trace impact ก่อน |
| 🟠 ยาก | เปลี่ยน approval workflow | สูง | ต้อง Impact Review |
| 🔴 สูง | แก้ RLS / DB function / trigger | สูงมาก | ทำผ่าน migration + test |
| 🔴 สูง | เปลี่ยน environment / connection | สูงมาก | ตรวจ Demo/Dev/Prod ก่อน |
| 🔴 สูง | เปลี่ยน service-role / secrets | สูงมาก | ห้ามแก้แบบทดลองเอง |

---

## 17. Golden Rule สำหรับคนมาจาก PC App

ก่อนแก้ Web App ให้ถาม 5 ข้อ:

```text
1. สิ่งที่ฉันจะแก้อยู่ใน FE หรือไม่?
2. ถ้าไม่ใช่ FE มันไป BE / Middleware / DB หรือไม่?
3. ข้อมูลวิ่งจากหน้าเว็บไป DB ผ่านอะไร?
4. การแก้นี้กระทบสิทธิ์/approval/business rule หรือไม่?
5. ถ้าผิด จะกระทบข้อมูลจริงหรือแค่หน้าจอ?
```

ถ้าตอบได้ 5 ข้อนี้ จะสามารถแก้ Tansub เรื่องเล็ก ๆ ได้เองจำนวนมากโดยไม่ต้องเป็น Web Developer เต็มตัว

---

## 18. Current Tansub Reference Points

- Repository: `superchoice-ai/tansub`
- Default branch: `main`
- Frontend stack: React + TanStack Router/Start + Vite
- Data access: Supabase JS
- Database: Supabase/PostgreSQL
- Authentication: Supabase Auth
- Server auth middleware: `src/integrations/supabase/auth-middleware.ts`
- Client Supabase: `src/integrations/supabase/client.ts`
- Server/admin Supabase: `src/integrations/supabase/client.server.ts`
- Main application routes: `src/routes/`
- Reusable UI/components: `src/components/`
- Business/data helpers: `src/lib/`
- Governance/documentation: `AGENTS.md`, `docs/`

> Note: This document intentionally does not record passwords, service-role keys, private tokens, or actual environment secrets.
