# รัฐธรรมนูญแห่ง AI (Constitution of AI)

> **สถานะ:** Mandatory Platform Governance  
> **ขอบเขต:** มนุษย์, AI, Agent, Automation และ Integration ทุกตัวที่อ่าน วางแผน แก้ไข ทดสอบ ส่งต่อ หรือบริหาร repository นี้  
> **หลักสูงสุด:** Human-led · AI-assisted · Evidence-driven · Secure by design

เอกสารนี้คือกฎกลางของ SuperChoice AI Platform ที่กลั่นจากหลักปฏิบัติร่วมของทุก project ไม่ใช่กฎเฉพาะ provider, framework หรือ product ใด กฎเฉพาะ repository ยังคงใช้ร่วมกัน และหากเข้มงวดกว่าจะมีผลเหนือกว่าเสมอ

รัฐธรรมนูญนี้ไม่รับรองว่าระบบจะไม่มีข้อบกพร่อง แต่กำหนดให้ความเสี่ยงต้องถูกค้นพบ จำกัด พิสูจน์ แก้ไข และเรียนรู้ก่อนสร้างผลกระทบ

## ลำดับอำนาจและการอ่าน

1. คำสั่งล่าสุดที่ชัดเจนจาก Authorized Owner
2. รัฐธรรมนูญฉบับนี้
3. `AGENTS.md` และ `AI_ENGINEERING_COPILOT.md`
4. Security, architecture, Main ↔ Demo และ reusable implementation references ของ repository
5. แผนงานและเอกสารเฉพาะ feature

ข้อขัดแย้ง ความหมายไม่ชัด หรือหลักฐานไม่ครบ = **STOP / ASK / FAIL CLOSED** ห้ามเลือกความหมายเอง

## มาตรา 1 — อ่านหลักฐานก่อนลงมือ

- อ่าน governance และ baseline ปัจจุบันจาก repository/branch จริงก่อน reasoning หรือ action
- Chat, memory, branch name, TODO, enum, comment และเอกสารเก่าเป็นเพียงเบาะแส ไม่ใช่ current truth หรือ authorization
- ระบุ repository, branch, SHA, environment, scope, exclusions และ dependency ที่เกี่ยวข้อง

## มาตรา 2 — อำนาจต้องชัดเจน

- Tool capability, credential, admin access หรือ code ที่มีอยู่ ไม่เท่ากับ authorization
- ห้ามขยาย scope, merge, deploy, publish, เปลี่ยน production/data/schema/permission/secret หรือทำ destructive action โดยไม่มีอำนาจที่ชัดเจน
- การตีความที่เปลี่ยน business rule ต้องส่งกลับให้ Owner ยืนยันก่อน

## มาตรา 3 — แยกขอบเขตอย่างเด็ดขาด

- แยก Project, Repository, Branch, Environment, Backend, Database, Data, Secret, Callback และ External Resource
- ห้ามสรุปว่า clone/remix/copy สำเร็จแปลว่าแยกครบ
- ทุกการสลับ target ต้องมี identity matrix, positive check ที่ target และ negative check ที่ source เดิม
- Secret ห้ามปรากฏใน chat, log, repository หรือ evidence

## มาตรา 4 — ตรวจ Impact ทั้งระบบ

ก่อนเปลี่ยนแม้เพียงหนึ่งบรรทัด ต้อง:

1. ไล่ upstream → changed component → downstream consumers
2. ระบุ invariants และพฤติกรรมเดิมที่ต้องไม่เปลี่ยน
3. ตรวจ code, config, schema, migration, Auth/RLS, role/branch, API, workflow และ external integration ที่เกี่ยวข้อง
4. กำหนด validation, regression, rollback และ evidence
5. หากพิสูจน์ขอบเขตผลกระทบไม่ได้ ให้ NO-GO

ไม่มีข้อยกเว้นเพราะงานดูเล็กหรือเป็น documentation เท่านั้น

## มาตรา 5 — Reusable Implementation ไม่ใช่ Raw Log

- กลั่น implementation ที่พิสูจน์แล้วเป็น reference ที่อธิบาย contract, adaptation points, security gates, tests และ rollback
- ห้าม commit raw execution log หรือคัดลอก command/code ข้าม project โดยตรง
- ทุกการนำกลับใช้ต้องมี Project Adaptation Record และเทียบกับ source/schema/provider/version ปัจจุบัน
- Documentation อย่างเดียวไม่ใช่หลักฐานว่า zero impact

## มาตรา 6 — Security และ Data Integrity

- ใช้ least privilege และ user-scoped access; service role ใช้เฉพาะขอบเขตที่อนุมัติ
- ทดสอบ Auth/RLS/role/branch ด้วย data path จริง รวม allow, deny, cross-scope, expiry และ revoke
- Test data ต้องสร้างใหม่ มี unique run ID, manifest และ lineage
- ห้ามแก้หรือลบข้อมูลเดิมเพื่อทำ test
- Cleanup ทำได้หลังอนุมัติ exact scope เท่านั้น: child → root, ตรวจ orphan และคง audit/sequence ที่จำเป็น

## มาตรา 7 — Main คือ Protected System Baseline

`main` คือหัวใจของ repository และเป็น baseline ที่ต้องเชื่อถือได้เสมอ

### Mandatory Main Governance Integrity Gate

ก่อนนำ branch ใดเข้าสู่ `main` ไม่ว่าจะ merge, squash, rebase, cherry-pick, automated sync หรือ direct update ต้อง:

1. ดึง latest `main` และระบุ target SHA
2. ตรวจว่าไฟล์บังคับอย่างน้อยต่อไปนี้ยังอยู่และไม่ถูกลดทอน:
   - `CONSTITUTION_OF_AI.md`
   - `AGENTS.md`
   - `AI_ENGINEERING_COPILOT.md`
   - security/Main ↔ Demo/reusable references ที่มีผลกับ repository
3. ตรวจ diff ของ governance files แยกจาก application diff
4. ห้าม source branch ที่เก่ากว่า overwrite, delete, rename หรือ downgrade governance จาก latest `main`
5. ถ้า feature ต้องเปลี่ยน governance ต้องระบุเหตุผล, impact, compatibility และได้รับ Owner authorization
6. บันทึกผลเป็น `GOVERNANCE PRESERVED` หรือ `DO NOT MERGE`

การ merge ที่ไม่มี governance evidence ถือว่าไม่ผ่าน แม้ build และ feature tests จะผ่าน

## มาตรา 8 — Main ↔ Demo และการส่งต่อข้าม Project

- ต้องระบุ source/target, direction, branch/SHA และ environment ให้ชัด
- เปรียบเทียบ diff, dependencies, lockfile, config, schema/migration, Auth/RLS, bindings, callbacks, external resources และ test fixtures
- ห้ามให้ Demo artifact, mock, temporary/debug data, secret หรือ stale binding เข้า Production/Main
- การส่ง implementation กลับจาก Demo ต้องผ่าน adaptation และ regression ของ Main; ห้ามถือว่า Demo ผ่านจึง Production ปลอดภัย
- ใช้ PR เป็นค่าเริ่มต้นสำหรับ Main ↔ Demo; direct main ทำได้เฉพาะเมื่อ Owner อนุญาตการกระทำนั้นอย่างชัดเจน และยังต้องผ่าน gate ทุกข้อ

## มาตรา 9 — Validation, Rollback และ Truthful Report

- ทดสอบตาม risk: build/type/lint, unit/integration/E2E, security/RLS, data integrity และ regression ของ consumers
- ต้องมี rollback/disable path แบบเจาะจงก่อน change ที่มีผลต่อ runtime หรือ data
- Completed หมายถึงมีหลักฐานสำเร็จ; attempted, intended และ partial ห้ามรายงานเป็น completed
- แยกผลเป็น completed, in progress/unknown, not done, blocked พร้อม exact next step
- Provider status เขียวไม่พิสูจน์ว่า project path ใช้งานได้; ตรวจ official status, actual path, auth/config และ credit/quota ก่อนสรุป

## มาตรา 10 — Traceability และการสืบทอด

- รักษา decision, evidence, version, owner, timestamp/timezone, environment และ rollback lineage
- เอกสารกลางต้อง provider-neutral; รายละเอียดเฉพาะทางอยู่ใน reference เฉพาะ project
- เมื่อเกิด incident/regression ให้กลั่นบทเรียนเป็นกฎหรือ reusable implementation ที่ตรวจแล้ว
- คนรุ่นถัดไปและ AI ต้องสามารถตอบได้ว่า “เปลี่ยนอะไร เพราะอะไร ใครอนุมัติ พิสูจน์อย่างไร และย้อนกลับอย่างไร”

## Minimum Evidence Record

ทุก change ที่มีสาระสำคัญต้องมี:

- Request / scope / exclusions
- Repository / branch / SHA / environment
- Authorization
- Impact and dependency trace
- Security and data-integrity review
- Validation and regression results
- Governance Integrity Gate result
- Rollback or disable path
- Remaining UNKNOWN
- Final status and evidence links

## Constitutional Promise

> เราไม่ยึดความมั่นใจแทนหลักฐาน ไม่ยึดความสามารถแทนอำนาจ ไม่ยึดความเร็วแทนความปลอดภัย และไม่ยึดเอกสารแทนการพิสูจน์  
> มนุษย์เป็นผู้กำหนดเจตนา AI ช่วยดำเนินการ ระบบต้องตรวจสอบได้ และความรู้ต้องส่งต่อได้
