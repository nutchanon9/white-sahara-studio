# white-sahara-studio — OasisFx

ชุดเครื่องมือสร้าง asset (VFX และในอนาคต SFX / Animation) สำหรับ Godot 4
ชื่อเครื่องมือคือ **OasisFx** (ในสเปกเดิมเรียกว่า "Godot Asset Studio")

แนวคิด: คน, ChatGPT หรือ Claude เขียน **preset เป็น JSON** → CLI ตรวจความถูกต้อง →
สร้างไฟล์ `.tscn` ที่ใช้ node มาตรฐานของ Godot → นำไปใช้ในเกม White Sahara หรือเกมอื่นได้

## เป้าหมายที่ปรับแล้ว (2026-10-15)

ปลายทางคือ **โปรแกรม Windows Desktop ที่สร้างด้วย Godot + Headless CLI ใช้ Core ร่วมกัน**
คนเปิดแอปเพื่อแก้ preset, preview และ export ได้โดยไม่ต้องเปิด Godot Editor ส่วน AI เรียก CLI
ในเครื่องหรือ cloud ที่มี source และ Godot พร้อมใช้งาน

**Phase 1C ทำแล้ว:** แอปอยู่ใน `app/` build เป็น `OasisFx.exe` ได้ (ดู [desktop.md](addons/oasis_fx/docs/desktop.md))

![OasisFx desktop app](docs/images/desktop_app.png)

รายละเอียดและคำสั่งงานล่าสุดอยู่ใน [Spec v1.1](Godot_Asset_Studio_Claude_Code_Implementation_Spec.md)
และ [CLAUDE.md](CLAUDE.md) ซึ่งใช้แทนทิศทาง UI เดิมใน audit

## สถานะ

| Phase | เนื้อหา | สถานะ |
|---|---|---|
| 0 | สำรวจ repo และสภาพแวดล้อม ([AUDIT.md](AUDIT.md)) | ✅ เสร็จ |
| 1A | schema, loader, validator, CLI `validate`/`generate`, Fire Burst, headless tests | ✅ เสร็จ (แก้ test runner ตาม review แล้ว) |
| 1B | หลาย emitter (สูงสุด 8), preset ตัวอย่าง 5 แบบ, validate-all/generate-all, manifest, runtime lifecycle, demo, AI guide | ✅ เสร็จ |
| 1C | แอป Windows แยก: preset editor, preview, save/export และ Windows package | ✅ ทำแล้ว รอรับงาน (ยังไม่ได้ทดสอบบนเครื่อง Windows จริง) |
| 2–4 | SFX, Animation, Rigging | ยังไม่เริ่ม |

## โครงสร้าง repo

```
project.godot          โปรเจกต์ของแอป (main scene = app/main.tscn) และ host สำหรับเทสต์ addon
addons/oasis_fx/       ตัว addon — copy โฟลเดอร์นี้ไปใส่เกมได้เลย
examples/runtime_demo/ เดโมการใช้ effect ในเกม + scene ที่ generate แล้ว (ใช้เป็น golden test)
tests/                 เทสต์ระดับ repo (แอป, เดโม และ golden files)
docs/images/           ภาพ preview ที่ render จริง
app/                   แอป desktop (main.tscn, ui/, services/)
export_presets.cfg     การตั้งค่า export สำหรับ Windows และ Linux
tools/                 เครื่องมือสำหรับนักพัฒนา (เช่น render ภาพ preview)
AUDIT.md               รายงาน Phase 0
CLAUDE.md              คำแนะนำเริ่มงานและ milestone ปัจจุบัน
Godot_Asset_Studio_Claude_Code_Implementation_Spec.md   สเปกต้นฉบับ
```

## เริ่มใช้งาน

ต้องมี Godot 4.7.x (ทดสอบกับ 4.7.2-stable)

```bash
OASIS="godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd --"

# ตรวจ preset ทั้งโฟลเดอร์
$OASIS validate-all addons/oasis_fx/presets/examples

# สร้าง scene ทั้งหมด → res://generated/oasis_fx/<id>.tscn (+ oasis_fx_manifest.json)
$OASIS generate-all addons/oasis_fx/presets/examples

# รันเทสต์ทั้งหมด (addon + เทสต์ระดับ repo)
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd
```

ดู effect ทำงานจริง: เปิดโปรเจกต์ใน Godot → เปิด `examples/runtime_demo/runtime_demo.tscn` → กด F6
(คลิกซ้าย = Fire Burst, คลิกขวา = Ice Nova, Space = ฟันดาบ, C = ทำอาหาร)

ภาพหน้าจอจริงของเดโม (render ใน cloud ด้วย software OpenGL ผ่าน Xvfb):

![Runtime demo](docs/images/runtime_demo.png)

Preview ของ effect ตัวอย่าง (8 เฟรมตามเวลา สร้างด้วย `tools/render_preview.gd`):

| Effect | Preview |
|---|---|
| Fire Burst | ![Fire Burst](docs/images/fire_burst_preview.png) |
| Ice Nova | ![Ice Nova](docs/images/ice_nova_preview.png) |
| Sword Slash | ![Sword Slash](docs/images/sword_slash_preview.png) |
| Cooking Success | ![Cooking Success](docs/images/cooking_success_preview.png) |
| Campfire Loop | ![Campfire Loop](docs/images/campfire_loop_preview.png) |

เอกสารละเอียด: [addons/oasis_fx/README.md](addons/oasis_fx/README.md),
[รูปแบบ preset](addons/oasis_fx/docs/preset_format.md), [CLI](addons/oasis_fx/docs/cli.md),
[คู่มือให้ AI เขียน preset](addons/oasis_fx/docs/ai_authoring_guide.md)

## ข้อจำกัดของ cloud session

- แอปที่ติดตั้งใน PC ของผู้ใช้ไม่ได้ถูกเรียกจาก cloud อัตโนมัติ; cloud ใช้ source/CLI และ Godot ใน session นั้น
- ไม่มี GPU: การทดสอบอัตโนมัติรันแบบ `--headless` (ตรวจโครงสร้างและการโหลด scene ได้ แต่ไม่ได้วาดภาพ)
- ภาพ preview สร้างได้ด้วย `tools/render_preview.gd` ผ่าน Xvfb + Mesa (software OpenGL)
  ใช้ดูหน้าตาคร่าว ๆ เท่านั้น ควรเช็กใน Godot Editor บนเครื่องจริงอีกครั้ง

## ผล review ของ Phase 1A

ที่ commit `4c6e7bf` รัน suite เดิมด้วย Godot 4.7.2 ได้ **41 passed, 0 failed**
และไม่พบ script error ใน suite เดิม แต่การทดลองแยกพบว่า test runner ยังพิมพ์ PASS และ exit 0
เมื่อ test เกิด runtime error ก่อนบันทึก assertion failure ได้

**แก้แล้ว:** runner ดักทุก script/engine error ด้วย `Logger` (`OS.add_logger`) แล้วนับเป็น test ล้มเหลว
มี timeout ต่อ test และมี regression `tests/test_runner.gd` (12 tests) ที่รันคำสั่ง runner จริงกับ test ตัวอย่าง
ที่ตั้งใจให้พัง ตอนจบงานแก้ review ผลรันทั้งหมดคือ **53 passed, 0 failed**

## Phase 1B

- **Schema v1 ขยายแบบเข้ากันได้ย้อนหลัง:** field ใหม่เป็น optional ทั้งหมด preset ของ 0.1 ยังใช้ได้เหมือนเดิม
  field ใหม่ ได้แก่ `delay_seconds`, `rotation_degrees`, `origin`, รูปทรง `circle_outline`/`ring`,
  `emission_offset`, `radial`/`tangential`/`orbit` velocity, `angle`, `angular_velocity`, `hue_variation`,
  texture `ring`/`streak`/`square`, `align_to_velocity`, `preprocess_seconds`
  ตัว schema ถูกสร้างจากตาราง field อัตโนมัติ และตรวจด้วย `jsonschema` ของ Python แล้ว
- **Runtime:** `OasisFxEffect` จัดการ delay, หยุด emitter ที่ duration, loop, restart/stop/pause และลบตัวเอง
  (ไม่แตะ node แม่)
- **CLI:** `validate-all` และ `generate-all` (ทำทั้งหมดหรือไม่ทำเลย), `schema`, manifest
  ถ้า OasisFx เองเกิด script error จะ exit 1 แทน 0
- **ผลเทสต์ล่าสุด: 86 passed, 0 failed** (exit 0) บน Godot 4.7.2 และได้ผลเดียวกันบนสำเนาใหม่ที่ไม่มี `.godot/`

## Phase 1C: แอป desktop

**เปิดจาก source:**
```bash
godot --path .
```

**Build สำหรับ Windows** (ต้องมี export templates 4.7.2):
```bash
godot --headless --path . --export-release "Windows Desktop" build/windows/OasisFx.exe
```
ได้ไฟล์ `OasisFx.exe` (~105MB, ฝังข้อมูลไว้ในไฟล์เดียว) และ `OasisFx.console.exe`

**สิ่งที่ทำได้ในแอป:**
- เปิดตัวอย่าง (อ่านอย่างเดียว) และ preset ของตัวเองใน workspace (`%APPDATA%\OasisFx\presets`)
- ปรับค่าด้วย control ที่มี type และช่วงค่าตรงกับ validator
- preview ทันที พร้อม Play/Pause/Stop/Restart, พื้นหลัง, grid และ zoom
- แสดง error/warning พร้อม path ของ field
- Save/Save As ในรูปแบบ canonical และถามก่อนทิ้งงานที่ยังไม่บันทึก

**Export เข้าเกม:**
- เลือกโฟลเดอร์ในโปรเจกต์เกม แอปหา `project.godot` เอง แล้วแสดงรายการไฟล์ที่จะเขียนก่อน
- ไฟล์ที่ได้เหมือนกับที่ CLI สร้างทุก byte
- copy runtime script ให้เฉพาะเมื่อเกมยังไม่มี

**ผลการตรวจ:**
- เทสต์ทั้งหมด **116 passed, 0 failed**
- build Linux ที่แพ็กแล้วผ่าน `--smoke-test` และ export เข้าโฟลเดอร์ชื่อไทยได้
- scene ที่ export เปิดเล่นในโปรเจกต์แยกได้
- **NOT RUN:** การเปิด .exe บน Windows จริง, file dialog ของ Windows และ GPU จริง (มี checklist ให้ทดสอบเองใน [desktop.md](addons/oasis_fx/docs/desktop.md))

**ยังไม่รองรับ:** export preset ที่ใช้ไฟล์ภาพ (`texture: "file"`) ออกจากแอป ให้ใช้ CLI ในโปรเจกต์เกมแทน

## License

MIT — ดู [LICENSE](LICENSE)
