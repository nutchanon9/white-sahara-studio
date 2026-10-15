# Phase 0 — Repository audit (OasisFx)

วันที่: 2026-10-15 · branch: `claude/cool-brown-hrne5t` · ผู้ตรวจ: Claude Code (cloud session)

## 1. สภาพ repo ก่อนเริ่มงาน

| สิ่งที่ตรวจ | ผล |
|---|---|
| ไฟล์ใน repo | `README.md` (2 บรรทัด), `LICENSE` (MIT, 2026 nutchanon9), `Godot_Asset_Studio_Claude_Code_Implementation_Spec.md` |
| `project.godot` | **ไม่มี** |
| `addons/`, `tools/`, `tests/`, `art/`, `assets/` | **ไม่มี** |
| commit history | 2 commits (`Initial commit`, `Add files via upload`) |
| `mannequin.tscn` / Skeleton2D / ระบบเสียง | **ไม่มีใน repo นี้** |

**ข้อสรุป:** repo นี้เป็น **repo เครื่องมือแยกต่างหาก** ไม่ใช่ตัวเกม White Sahara

- ใน repo นี้จึงไม่มี gameplay, art pipeline หรือ rig ของ White Sahara ให้เสี่ยงทำพัง
- ข้อมูล White Sahara ในสเปก (Godot 4.7.2, `tools/`, `tests/`, `mannequin.tscn`, commit `5a4c870`)
  **ยังไม่ได้ตรวจสอบจริง** เพราะ repo เกมไม่ได้ถูกเพิ่มเข้า session นี้
- การนำไปใช้กับเกม: copy `addons/oasis_fx/` ไปไว้ในโปรเจกต์เกม (ดูความเสี่ยงข้อ 5)

## 2. สภาพแวดล้อม cloud session

| สิ่งที่ตรวจ | ผล |
|---|---|
| Godot ที่ติดตั้งมาก่อน | ไม่มี |
| ติดตั้ง | ดาวน์โหลด official build `Godot_v4.7.2-stable_linux.x86_64` จาก GitHub releases ไว้ที่ `~/godot/` (นอก repo) และ link ไปที่ `/usr/local/bin/godot` |
| `godot --version` | `4.7.2.stable.official.ed1daf0bf` (ตรงกับเวอร์ชันที่สเปกบอกว่า White Sahara ใช้) |
| Headless (`--headless`) | ใช้ได้: รัน `--script`, `--editor --quit`, `--import` ได้ |
| GPU | ไม่มี |
| แสดงภาพ | มี Xvfb + Mesa llvmpipe → render ด้วย `--rendering-driver opengl3` ได้ (software, ใช้ดูคร่าว ๆ) |
| Audio | ไม่มีอุปกรณ์เสียง (Godot ใช้ dummy driver แทนอัตโนมัติ) |

## 3. สิ่งที่พบเกี่ยวกับ Godot 4.7 ระหว่างตรวจ (มีผลต่อการออกแบบ)

ตรวจ API จริงด้วย `ClassDB` แทนการเดา:

1. **`.tscn` ของ Godot 4.7 เก็บ `unique_id=<สุ่ม>` ในทุก node** ถ้าบันทึกตรง ๆ ไฟล์จะต่างกันทุกครั้ง
   → generator แทนค่าด้วย id ที่คำนวณจาก path ของ node ผ่าน `PackedScene._get_bundled_scene()`
   / `_set_bundled_scene()` (ถ้าเวอร์ชันอื่นไม่มีค่านี้ก็ข้ามไป)
2. **`Resource.resource_scene_unique_id`** มีให้ใช้ → sub-resource ใช้ id อ่านง่ายและคงที่ เช่น `flame_process`
3. **`ResourceSaver.set_uid()`** ใช้กำหนด UID ของ scene ให้คงที่ได้ (ได้จาก path ของไฟล์ output)
   ไฟล์ใต้ `user://` ไม่มี UID (Godot ให้ UID เฉพาะไฟล์ในโปรเจกต์)
4. **`EditorDock` + `EditorPlugin.add_dock()`** เป็น API dock แบบใหม่ใน 4.7 (จดไว้ใช้ใน Phase 1C)
5. `ParticleProcessMaterial` มี `EMISSION_SHAPE_RING` แบบระนาบ → ใช้ทำวงกลมทึบใน 2D
   แทน `SPHERE` (ซึ่งถ้าฉายลง 2D จะไม่สม่ำเสมอ)
6. `String.contains("")` คืนค่า `false` ใน Godot (ต้องระวังในโค้ดเทสต์)

## 4. การตัดสินใจ (ตอบสเปกหัวข้อ 15)

| คำถาม | การตัดสินใจ |
|---|---|
| repo แยกหรือฝังในเกม? | repo แยก + addon ที่อยู่ในตัวเองครบ `addons/oasis_fx/`; ราก repo มี `project.godot` ไว้พัฒนา/ทดสอบเท่านั้น |
| ชื่อ | **OasisFx** (โฟลเดอร์ `oasis_fx`) แทน "Godot Asset Studio" ตามที่เจ้าของ repo เลือก |
| เวอร์ชัน Godot ที่ทดสอบ | 4.7.2-stable (pin ไว้ เพราะข้อความ `.tscn` อาจต่างกันระหว่างเวอร์ชัน) |
| สี/gradient ของ particle | `ParticleProcessMaterial.color_ramp` = `GradientTexture1D` 2–3 จุด (start / mid / end) |
| อะไร serialize, อะไรสร้างตอนรัน | ทุกอย่าง serialize ลง `.tscn` เป็น built-in resource; texture แบบ procedural (`GradientTexture2D`) ฝังในไฟล์ ไม่ต้องมีไฟล์ภาพ |
| preview ใน editor ไม่กระทบ scene ที่เปิดอยู่ | (Phase 1C) ใช้ `SubViewport` แยก และใช้ builder ตัวเดียวกับ generator |
| ไฟล์ generated อยู่ไหน / เก็บใน Git ไหม | ค่าเริ่มต้น `res://generated/oasis_fx/`; ใน repo เครื่องมือนี้ **ไม่ commit** (`.gitignore`); ในเกม **แนะนำให้ commit** เพราะไฟล์ deterministic และเกมต้องรันได้โดยไม่ต้องใช้ CLI |
| CLI ไม่พึ่ง EditorPlugin | CLI เป็น `SceneTree` script, ใช้ `preload()` แทน `class_name` จึงรันได้บน clone ใหม่ที่ยังไม่มี `.godot/` (ทดสอบแล้ว) |
| v0.1 ที่เล็กที่สุดที่ทดสอบใน cloud ได้ | Phase 1A: JSON → validate → `.tscn` → โหลด/instantiate แบบ headless + เทสต์อัตโนมัติ |

## 5. ความเสี่ยง

| ความเสี่ยง | ผลกระทบ | การจัดการ |
|---|---|---|
| ยังไม่ได้ตรวจ repo เกม White Sahara จริง | การรวมเข้าเกมอาจเจอ convention ที่ต่างไป | addon ไม่แตะไฟล์อื่นในโปรเจกต์ ไม่มี autoload ไม่แก้ project settings; ควรตรวจตอนนำไปใส่เกม |
| autoload ของเกมอาจทำงานเมื่อรัน CLI ด้วย `--script` ในโปรเจกต์เกม | CLI อาจช้าหรือ autoload พิมพ์ error | **ยังไม่ได้ทดสอบ** (repo นี้ไม่มี autoload) ต้องลองในโปรเจกต์เกม |
| ข้อความ `.tscn` ต่างกันระหว่างเวอร์ชัน Godot | diff ใหญ่เมื่ออัปเกรด engine | pin 4.7.2; เทสต์ determinism รันบนเวอร์ชันเดียว |
| ใช้ `_get_bundled_scene` / `_set_bundled_scene` (method ขึ้นต้นด้วย `_`) | อาจเปลี่ยนในเวอร์ชันหน้า | ตรวจ key ก่อนใช้ ถ้าไม่มีก็ข้าม; เทสต์ determinism จะจับได้ |
| preset ที่ใช้ไฟล์ภาพบน clone ใหม่ | โหลด texture ไม่ได้จนกว่าจะ import | error ที่บอกวิธีแก้ (`godot --headless --import`) |
| ตรวจหน้าตา effect ไม่ได้ใน headless | effect อาจดูไม่สวยแม้เทสต์ผ่าน | render ผ่าน Xvfb (software) ได้คร่าว ๆ; ต้องดูใน editor จริงอีกครั้ง |
| preset จาก AI ใส่ field แปลก ๆ หรือ path อันตราย | เขียนไฟล์นอกโปรเจกต์ / รันโค้ด | preset เป็นข้อมูลล้วน, field ที่ไม่รู้จัก = error, path ต้องเป็น `res://` ไม่มี `..`, output อยู่ใต้โฟลเดอร์ที่ sanitize แล้วเท่านั้น |

## 6. แผนและโครงสร้างไฟล์ที่ใช้จริง

```
project.godot                         host project (gl_compatibility renderer)
addons/oasis_fx/
  README.md
  cli/oasis_fx_cli.gd                 validate / generate / version / help
  src/core/oasis_fx.gd                ค่าคงที่ (version, path)
  src/core/vfx_spec.gd                ตารางนิยาม field (แหล่งข้อมูลเดียว)
  src/core/preset_loader.gd           อ่านไฟล์ + parse JSON
  src/core/preset_validator.gd        ตรวจ type/range/enum/path + กฎข้าม field
  src/core/validation_report.gd       เก็บ error/warning พร้อม path ของ field
  src/core/path_utils.gd              sanitize output dir, ตรวจ res:// path
  src/core/vfx_builder.gd             preset → node tree (built-in nodes เท่านั้น)
  src/core/vfx_generator.gd           บันทึก .tscn แบบ deterministic + กันเขียนทับ
  schemas/vfx.v1.schema.json
  presets/examples/fire_burst.vfx.json
  docs/preset_format.md, docs/cli.md
  tests/run_tests.gd + test_*.gd      เทสต์ headless
tools/render_preview.gd               (dev) render contact sheet ผ่าน Xvfb
```

ส่วนที่สเปกเสนอแต่ **ยังไม่ทำใน Phase 1A** (โดยตั้งใจ): `plugin.cfg`/`plugin.gd`, `src/editor/`,
`src/runtime/`, `asset_manifest.gd`, `validate-all`/`generate-all`, preset ตัวอย่างอีก 3 แบบ,
`ai_authoring_guide.md`, `architecture.md`, `compatibility.md`, GitHub Actions
