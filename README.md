# white-sahara-studio — OasisFx

ชุดเครื่องมือสร้าง asset (VFX และในอนาคต SFX / Animation) สำหรับ Godot 4
ชื่อเครื่องมือคือ **OasisFx** (ในสเปกเดิมเรียกว่า "Godot Asset Studio")

แนวคิด: คน, ChatGPT หรือ Claude เขียน **preset เป็น JSON** → CLI ตรวจความถูกต้อง →
สร้างไฟล์ `.tscn` ที่ใช้ node มาตรฐานของ Godot → นำไปใช้ในเกม White Sahara หรือเกมอื่นได้

## สถานะ

| Phase | เนื้อหา | สถานะ |
|---|---|---|
| 0 | สำรวจ repo และสภาพแวดล้อม ([AUDIT.md](AUDIT.md)) | ✅ เสร็จ |
| 1A | schema, loader, validator, CLI `validate`/`generate`, Fire Burst, headless tests | ✅ เสร็จ |
| 1B | หลาย emitter, preset ตัวอย่าง 4 แบบ, validate-all/generate-all, runtime lifecycle | ยังไม่เริ่ม |
| 1C | แผงควบคุมใน Godot Editor (preview, ปรับค่า, Generate) | ยังไม่เริ่ม |
| 2–4 | SFX, Animation, Rigging | ยังไม่เริ่ม |

## โครงสร้าง repo

```
project.godot          โปรเจกต์ Godot สำหรับพัฒนา/ทดสอบ addon (ไม่ใช่ตัวเกม)
addons/oasis_fx/       ตัว addon — copy โฟลเดอร์นี้ไปใส่เกมได้เลย
tools/                 เครื่องมือสำหรับนักพัฒนา (เช่น render ภาพ preview)
AUDIT.md               รายงาน Phase 0
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

- ไม่มี GPU: การทดสอบอัตโนมัติรันแบบ `--headless` (ตรวจโครงสร้างและการโหลด scene ได้ แต่ไม่ได้วาดภาพ)
- ภาพ preview สร้างได้ด้วย `tools/render_preview.gd` ผ่าน Xvfb + Mesa (software OpenGL)
  ใช้ดูหน้าตาคร่าว ๆ เท่านั้น ควรเช็กใน Godot Editor บนเครื่องจริงอีกครั้ง

## License

MIT — ดู [LICENSE](LICENSE)
