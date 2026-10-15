# white-sahara-studio — OasisFx

ชุดเครื่องมือสร้าง asset (VFX และในอนาคต SFX / Animation) สำหรับ Godot 4
ชื่อเครื่องมือคือ **OasisFx** (ในสเปกเดิมเรียกว่า "Godot Asset Studio")

แนวคิด: คน, ChatGPT หรือ Claude เขียน **preset เป็น JSON** → CLI ตรวจความถูกต้อง →
สร้างไฟล์ `.tscn` ที่ใช้ node มาตรฐานของ Godot → นำไปใช้ในเกม White Sahara หรือเกมอื่นได้

## เป้าหมายที่ปรับแล้ว (2026-10-15)

ปลายทางคือ **โปรแกรม Windows Desktop ที่สร้างด้วย Godot + Headless CLI ใช้ Core ร่วมกัน**
คนเปิดแอปเพื่อแก้ preset, preview และ export ได้โดยไม่ต้องเปิด Godot Editor ส่วน AI เรียก CLI
ในเครื่องหรือ cloud ที่มี source และ Godot พร้อมใช้งาน โค้ด CLI/Core ของ Phase 1A ใช้ต่อได้
ขณะนี้ยังไม่มีหน้าต่างแอปหรือ Windows package; Phase 1C จะสร้างส่วนนี้ ไม่ใช่ EditorPlugin dock

รายละเอียดและคำสั่งงานล่าสุดอยู่ใน [Spec v1.1](Godot_Asset_Studio_Claude_Code_Implementation_Spec.md)
และ [CLAUDE.md](CLAUDE.md) ซึ่งใช้แทนทิศทาง UI เดิมใน audit

## สถานะ

| Phase | เนื้อหา | สถานะ |
|---|---|---|
| 0 | สำรวจ repo และสภาพแวดล้อม ([AUDIT.md](AUDIT.md)) | ✅ เสร็จ |
| 1A | schema, loader, validator, CLI `validate`/`generate`, Fire Burst, headless tests | ทำแล้ว; รอแก้ test runner ตาม review |
| 1B | หลาย emitter, preset ตัวอย่าง 4 แบบ, validate-all/generate-all, runtime lifecycle | ยังไม่เริ่ม |
| 1C | แอป Windows แยก: preset editor, preview, save/export และ Windows package | ยังไม่เริ่ม |
| 2–4 | SFX, Animation, Rigging | ยังไม่เริ่ม |

## โครงสร้าง repo

```
project.godot          ปัจจุบันเป็น host ทดสอบ; เพิ่ม entry scene ของแอปใน Phase 1C
addons/oasis_fx/       ตัว addon — copy โฟลเดอร์นี้ไปใส่เกมได้เลย
app/                  วางแผนเพิ่มใน Phase 1C สำหรับ desktop UI
tools/                 เครื่องมือสำหรับนักพัฒนา (เช่น render ภาพ preview)
AUDIT.md               รายงาน Phase 0
CLAUDE.md              คำแนะนำเริ่มงานและ milestone ปัจจุบัน
Godot_Asset_Studio_Claude_Code_Implementation_Spec.md   สเปกต้นฉบับ
```

## เริ่มใช้งาน

ต้องมี Godot 4.7.x (ทดสอบกับ 4.7.2-stable)

```bash
OASIS="godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd --"

# ตรวจ preset
$OASIS validate addons/oasis_fx/presets/examples/fire_burst.vfx.json

# สร้าง scene → res://generated/oasis_fx/fire_burst.tscn
$OASIS generate addons/oasis_fx/presets/examples/fire_burst.vfx.json

# รันเทสต์ทั้งหมด
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd
```

ในเครื่องที่มีหน้าจอ เปิดไฟล์ `generated/oasis_fx/fire_burst.tscn` ใน Godot Editor
แล้วเลือก node `flame` → ติ๊ก Emitting เพื่อดู effect

ภาพจริงของ Fire Burst ที่ render ใน cloud session (software OpenGL ผ่าน Xvfb, 8 เฟรมที่
0.05–1.1 วินาที) สร้างด้วย `tools/render_preview.gd`:

![Fire Burst preview](docs/images/fire_burst_preview.png)

เอกสารละเอียด: [addons/oasis_fx/README.md](addons/oasis_fx/README.md),
[รูปแบบ preset](addons/oasis_fx/docs/preset_format.md), [CLI](addons/oasis_fx/docs/cli.md)

## ข้อจำกัดของ cloud session

- แอปที่ติดตั้งใน PC ของผู้ใช้ไม่ได้ถูกเรียกจาก cloud อัตโนมัติ; cloud ใช้ source/CLI และ Godot ใน session นั้น
- ไม่มี GPU: การทดสอบอัตโนมัติรันแบบ `--headless` (ตรวจโครงสร้างและการโหลด scene ได้ แต่ไม่ได้วาดภาพ)
- ภาพ preview สร้างได้ด้วย `tools/render_preview.gd` ผ่าน Xvfb + Mesa (software OpenGL)
  ใช้ดูหน้าตาคร่าว ๆ เท่านั้น ควรเช็กใน Godot Editor บนเครื่องจริงอีกครั้ง

## ผล review ของ Phase 1A

ที่ commit `4c6e7bf` รัน suite เดิมด้วย Godot 4.7.2 ได้ **41 passed, 0 failed**
และไม่พบ script error ใน suite เดิม แต่การทดลองแยกพบว่า test runner ยังพิมพ์ PASS และ exit 0
เมื่อ test เกิด runtime error ก่อนบันทึก assertion failure ได้ จึงต้องแก้และเพิ่ม regression
ก่อนรับ Phase 1A/เริ่ม Phase 1B ดู reproduction และ acceptance ใน Spec หัวข้อ 13
การแก้เอกสารรอบนี้ยังไม่ได้แก้ตัว runner; ต้องรายงานจำนวน tests ใหม่หลังแก้จริง

## License

MIT — ดู [LICENSE](LICENSE)
