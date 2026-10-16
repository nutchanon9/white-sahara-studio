# Phase 0 — Repository audit (OasisFx)

> **Historical audit:** observations below describe the original Phase 0 session.
> The owner subsequently selected a standalone Windows desktop app built with Godot,
> sharing the core with the headless CLI. Specification v1.1 and `CLAUDE.md` supersede
> future EditorPlugin/dock plans below; the original observations are preserved.

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

---

## 7. ภาคผนวก (2026-10-15): การตัดสินใจใน Phase 1B

ส่วนนี้เพิ่มต่อท้าย ไม่ได้แก้ข้อสังเกตเดิมด้านบน

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| ขยาย schema | คง `schema_version: 1` และเพิ่มเฉพาะ field แบบ optional; ขยาย emitter สูงสุด 1 → 8 | preset ของ 0.1 ทุกไฟล์ยังถูกต้องและได้ผลเหมือนเดิม จึงไม่ต้องมี migration |
| JSON Schema | สร้างจาก `vfx_spec.gd` (`vfx_schema.gd`, คำสั่ง `schema --write`) และมีเทสต์เทียบไฟล์ทุก byte | ป้องกัน schema ไม่ตรงกับ validator; ตรวจกับ Python `jsonschema` 4.26 (Draft 2020-12) แล้วผ่าน |
| Playback | script เล็ก ๆ `src/runtime/oasis_fx_effect.gd` (class `OasisFxEffect`) ติดอยู่กับ root ของ scene ที่ generate | ทำ delay, ปิด emitter ที่ duration, loop, ลบตัวเองโดยไม่แตะ node แม่ และ restart/pause ได้ ซึ่ง GPUParticles2D ทำเองไม่ได้; ไม่ใช่ `@tool` จึงไม่เล่นหรือลบตัวเองเมื่อเปิดใน editor |
| ผลกับเกม | scene อ้างถึง runtime script ด้วย path → เกมต้องมี `addons/oasis_fx/src/runtime/` | Phase 1C exporter จะต้อง copy/map ไฟล์นี้ (ระบุไว้ใน `dependencies` ของ manifest แล้ว) |
| พฤติกรรม scene เปลี่ยนจาก 1A | เดิม emitter `emitting = true` เล่นเองตอน instantiate; ตอนนี้ `emitting = false` และให้ runtime สั่งเล่น (`auto_play` ค่าเริ่มต้น true) | เพื่อให้ delay/loop/cleanup ทำงานได้; สำหรับผู้ใช้ผลเหมือนเดิม (เล่นทันที) |
| Determinism ของ ext_resource | ใช้ `Resource.set_id_for_path()` ให้ id คงที่ (`oasis_fx_runtime`, `<emitter>_texture_file`) | ค่าเริ่มต้นของ Godot สุ่ม id แบบ `1_ab3xy`; CLI ไม่เขียน uid ของ script ทั้งบน clone ใหม่และหลัง import → ผลเหมือนกัน (ทดสอบแล้ว) |
| Manifest | `oasis_fx_manifest.json` หนึ่งไฟล์ต่อโฟลเดอร์ output, sort key, ไม่มี timestamp | รู้ว่าไฟล์ไหนถูกแก้มือ (เตือนตอน `--force`) และรู้ dependency สำหรับ export ใน 1C |
| Batch | `generate-all` ทำทั้งหมดหรือไม่ทำเลย (ตรวจทุกไฟล์, id ซ้ำ, ไฟล์ที่มีอยู่แล้ว ก่อนเขียน) | ไม่เหลือโฟลเดอร์ที่ generate ไปครึ่งเดียว |
| Exit code ของ CLI | ใช้ `ErrorCapture` (Logger) ร่วมกับ test runner; มี error ใดถูก log → exit 1 | พบว่า script error ใน `_run()` เดิมทำให้ CLI exit 0 (ทดสอบซ้ำได้) |
| Golden files | commit scene ที่ generate แล้วใน `examples/runtime_demo/fx/` และให้เทสต์ระดับ repo (`tests/`) generate ใหม่แล้วเทียบ | เดโมรันได้ทันทีบน clone ใหม่ และจับการเปลี่ยน output โดยไม่ตั้งใจ |
| ทิศทางหมุน | ตรวจจากภาพจริง: `orbit_velocity` > 0 หมุนทวนเข็มบนจอ, `rotation_degrees` > 0 หมุนตามเข็ม | เอกสารเดิมในร่างแรกเขียนทิศ orbit ผิด แก้แล้วหลัง render |
| ภาพ preview | ภาพใน `docs/images/` render จริงด้วย Xvfb + Mesa llvmpipe (software OpenGL) | ใช้ดูทิศทาง/สี/ขนาด ไม่เท่ากับการตรวจบน GPU จริงหรือบน Windows |

---

## 8. ภาคผนวก (2026-10-15): การตัดสินใจใน Phase 1C (แอป desktop)

ตอบคำถามสเปก v1.1 หัวข้อ 15:

| คำถาม | คำตอบ |
|---|---|
| branch/commit และเวอร์ชัน Godot ที่ทดสอบ | `claude/cool-brown-hrne5t` ต่อจาก `87884f3`; Godot 4.7.2-stable + export templates 4.7.2 (official) |
| `app/` ใช้ core โดยไม่ให้ CLI พึ่ง UI ได้อย่างไร | `app/` preload core (validator/builder/generator/serializer) โดยตรง; addon ไม่อ้างถึง `res://app/` เลย (มีเทสต์ตรวจ) และมีเทสต์รัน CLI ในโปรเจกต์ที่มีแค่โฟลเดอร์ addon |
| preset/settings/ไฟล์ชั่วคราวอยู่ที่ไหน | `user://` = `%APPDATA%\OasisFx` (`config/use_custom_user_dir`): `settings.cfg`, `presets/` (workspace เริ่มต้น), `oasis_fx_export_staging/`; ตัวอย่างใน `res://` อ่านอย่างเดียว และ document ปฏิเสธการเขียน `res://` |
| dependency ใน workspace map ไป `res://` ของเกมอย่างไร | หา `project.godot` จากโฟลเดอร์ที่เลือกขึ้นไป → path ส่วนที่เหลือคือ `res://` ในเกม; scene ใส่ uid คงที่ตาม path นั้น จึงเหมือนกับผลของ CLI ในเกมทุก byte; runtime script ไปที่ path เดิม `res://addons/oasis_fx/src/runtime/`; preset ที่ใช้ไฟล์ภาพถูกปฏิเสธพร้อมคำอธิบาย (ยังไม่ทำ mapping) |
| ตรวจ export ในโปรเจกต์แยกอย่างไร | เทสต์สร้างโปรเจกต์เกมใหม่ชั่วคราว export ลงไป แล้วรัน Godot อีก process เปิด scene: เล่นเอง, ลบตัวเอง, node แม่ไม่ถูกแตะ; ทำแบบเดียวกันกับ build Linux ที่แพ็กแล้ว |
| pause/restart/lifecycle ใช้ร่วมกันระหว่าง preview กับเกมอย่างไร | preview สร้าง effect ด้วย builder ตัวเดียวกับ generator และเล่นด้วย `OasisFxEffect` ตัวเดียวกัน (ปิด `free_when_finished` และ `auto_play` เท่านั้น) |
| runtime error ถูกจับใน test entrypoint อย่างไร | `ErrorCapture` (Logger) ใน runner และ CLI; UI test เจอบั๊กจริงจากการจับ error นี้ (dialog ซ้อนตอน export) และแก้แล้ว |
| export template / รูปแบบ package / การตรวจบน Windows | Windows x86_64: `OasisFx.exe` ฝัง pck + `OasisFx.console.exe`, script แบบ text, `modify_resources=false` (ไม่มี rcedit); export และตรวจไส้ในไฟล์แล้ว; **การเปิดบน Windows ยังไม่ได้รัน** |

การตัดสินใจอื่น:
- เลือก window แยกสำหรับ dialog (`embed_subwindows=false`) และใช้ native file dialog เมื่อ OS รองรับ
- เพิ่ม `preset_serializer.gd` + คำสั่ง `format` เพื่อให้ไฟล์ที่แอปบันทึกกับไฟล์ที่ AI/คนเขียน มีรูปแบบเดียวกัน; จัดรูป preset ตัวอย่างใหม่ (ค่าไม่เปลี่ยน, golden scene ไม่เปลี่ยน)
- ขยาย `PathUtils` ให้ชื่อโฟลเดอร์ใช้ตัวอักษร Unicode ได้ (ภาษาไทย) แต่ยังห้าม `..`, `.`, ชื่อซ่อน, `res://.godot` และโฟลเดอร์ของ addon
- เปลี่ยน `project.godot`: `run/main_scene` = แอป, ชื่อ "OasisFx", custom user dir, ขนาดหน้าต่าง 1440×900 — เหตุผล: repo นี้คือแอป; CLI/เทสต์ใช้ `--script` จึงไม่โหลด main scene

---

## 9. ภาคผนวก (2026-10-15): การตัดสินใจใน Phase 2 (SFX Composer)

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| รูปแบบ preset | `asset_type: "sfx"`, `schema_version: 1`, ไฟล์ `<id>.sfx.json`, ตาราง field `sfx_spec.gd` | ใช้ loader/validator/serializer/schema builder ตัวเดิม; ตาราง field เป็นแหล่งเดียวของ validator, JSON Schema, เอกสาร และ inspector |
| VFX | schema และ golden scene ของ VFX ไม่เปลี่ยน (ยกเว้นคำอธิบาย `asset_type` ใน schema) | preset เดิมยังใช้ได้ |
| Node ที่สร้าง | `Node2D` + `AudioStreamPlayer` (หรือ `AudioStreamPlayer2D` เมื่อ `positional`) ต่อ layer + runtime `oasis_sfx_effect.gd` | ใช้ node มาตรฐาน; timing/variant/fade/loop ทำใน runtime ด้วยนาฬิกาของตัวเอง จึงเหมือนกันทุก audio driver รวม Dummy ที่ใช้ทดสอบ |
| ไฟล์เสียงตอน generate | scene อ้างไฟล์ด้วย path (placeholder + `take_over_path`) ไม่ต้อง import ก่อน | clone ใหม่กับโปรเจกต์ที่ import แล้วได้ไฟล์เหมือนกันทุก byte (ทดสอบแล้ว); ทำแบบเดียวกันกับ `texture: "file"` ของ VFX |
| ผลข้างเคียงกับ VFX | visibility rect อัตโนมัติของ `texture: "file"` ถือว่าภาพ 64 px (เดิมใช้ขนาดจริง) | ไม่โหลดภาพตอน generate อีกต่อไป; ระบุใน preset_format.md |
| ตัวสุ่ม | `seed` -1 = สุ่มจริง, ≥0 = ลำดับเดิมทุกครั้งที่รัน (ตั้งครั้งเดียว ไม่ reset ทุก play) | ทดสอบได้ และการเล่นแต่ละครั้งยังต่างกัน |
| Loop + fade | `fade_in_ms` ของ layer ที่ loop ใช้ครั้งแรกครั้งเดียว; `fade_out_ms` บน loop ซ้ำทุกรอบและมีคำเตือน | เห็นจาก timeline ว่า fade-in ซ้ำทุกรอบทำให้เสียงวูบ |
| ไฟล์เสียงตัวอย่าง | สังเคราะห์เองแบบ deterministic (`tools/synth_example_sounds.gd`) และให้เป็น CC0 | ไม่มีปัญหา license และไม่ต้องดาวน์โหลด |
| หาไฟล์ `res://` | `ValidationReport.res_roots`: CLI = โปรเจกต์ที่รัน; แอป = โปรเจกต์เกมที่เลือกก่อน แล้วค่อยไฟล์ในแอป | preset อ้าง path ในเกม ซึ่งเป็นที่ที่ scene จะโหลดจริง |
| Export ไฟล์ประกอบ | มีในเกมแล้ว = ใช้ (ไม่เขียนทับ); เป็นไฟล์ตัวอย่างของแอป = copy; นอกนั้น = error | ไม่แตะไฟล์ของเกม; ปลดข้อจำกัด `texture: "file"` ของ Phase 1C ได้ด้วยกฎเดียวกัน |
| ไฟล์ต้นฉบับใน package | plugin สำหรับ build `app/export/` (เปิดใน `project.godot`) ใส่ไฟล์ `.wav` ต้นฉบับลง pck | Godot export ใส่แต่ไฟล์ที่ import แล้ว (QOA) แอปที่แพ็กแล้วจึงอ่าน/copy ไฟล์ต้นฉบับไม่ได้ — smoke test ที่ขยายจับได้ |
| Test runner | auto-import (`godot --headless --import`) เมื่อไฟล์ที่ import หายไป | เทสต์ที่เล่นเสียงต้องใช้ไฟล์ที่ import แล้ว; clone ใหม่ยังรันคำสั่งเดียวได้ |
| WAV mixdown | ไม่ทำ; ทดสอบความเป็นไปได้แล้วด้วย Movie Maker (`--write-movie`) ได้ WAV จริงใต้ Xvfb แต่ `--headless` abort | ตามสเปกข้อ 8: ทำเมื่อพิสูจน์ได้ และเกมเล่น scene หลาย layer ได้โดยตรง |

ข้อค้นพบที่แก้คำกล่าวเดิม:
- **Phase 1C บอกว่า "scene ที่ export จากแอปเหมือน CLI ทุก byte"** — จริงเมื่อรันจาก source เท่านั้น
  build ที่แพ็กแล้ว (release template) เขียน id ของ ext_resource เป็นตัวเลขและเขียนค่า default ของ property ด้วย
  เพราะ `Resource.set_id_for_path` และค่า default ของ script เป็นฟีเจอร์ฝั่ง editor; scene ทำงานเหมือนกันและ
  ผลของแอปเองคงที่ทุกครั้ง แต่ข้อความไม่ตรงกับ CLI — บันทึกไว้ใน desktop.md
- ข้อความ `ObjectDB instances leaked` / `resources still in use at exit` หลังรันเทสต์เสียง เป็นพฤติกรรมของ Godot 4.7.2
  กับ Dummy audio driver ตอนปิดโปรแกรม (`AudioStreamPlayer` ธรรมดาเล่นไฟล์เดียวก็เกิด) ไม่ใช่ leak ของ OasisFx

---

## 10. ภาคผนวก (2026-10-15): การตัดสินใจใน Phase 3 (Animation Timeline)

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| ชนิด asset | `animation` (`.anim.json` → Animation `.tres`) และ `sprite_frames` (`.frames.json` → SpriteFrames `.tres`) แยกกัน | สเปกข้อ 9 ให้ keyframe/skeleton กับ sprite sheet เป็นคนละ workflow; ผลลัพธ์เป็น resource มาตรฐานที่ใส่ AnimationPlayer / AnimatedSprite2D ของเกมได้ทันที |
| Registry | `src/core/asset_types.gd` เป็นที่เดียวที่บอก field table, suffix, ไฟล์ schema, นามสกุล output ของแต่ละชนิด | ก่อนหน้านี้มีการเช็ก `"sfx"` กระจายหลายสิบจุด; refactor แล้ว schema/golden ของ VFX/SFX ไม่เปลี่ยนแม้แต่ byte เดียว |
| Rig เดิมของเกม | preset ชี้ `target_scene`; OasisFx อ่าน `.tscn` เป็นข้อความด้วย `scene_outline.gd` (ตาม instanced scene ได้ 6 ชั้น) ไม่โหลด/ไม่รัน และไม่แก้ไฟล์ของเกม | สเปก: "import rather than regenerate" rig; ไม่ทำให้ script ของเกมทำงานใน validator/แอป |
| ความปลอดภัย | property ที่ animate ได้มาจาก whitelist 8 ตัว; event เรียก method ตายตัว `oasis_event` บน node `OasisAnimationEvents`; ฝั่ง runtime แสดงเฉพาะ scene ที่มี runtime script ของ OasisFx; ค่า property ในไฟล์ scene decode เฉพาะชนิดข้อมูลธรรมดา (ปฏิเสธ `Object(`) | สเปกข้อ 9: ห้ามรับ node path/method name แบบไม่จำกัดจาก preset |
| หน่วย | `rotation_degrees` ในไฟล์ แปลงเป็น `rotation` (เรเดียน) ใน track; `opacity` → `modulate:a`; interpolation ไม่ wrap มุม | อ่านง่ายสำหรับคน/AI และหมุนเกิน 180° ได้ตามที่เขียน |
| Event → VFX/SFX | ใช้ method track หนึ่ง track; argument เป็น PackedScene (อ้างด้วย path) + NodePath; effect ไปอยู่ใต้ parent ของ root ตัวละคร (ตั้ง `effects_parent` ได้) | เป็นของ Godot ล้วน, dependency ถูกบันทึกใน manifest (รวมสิ่งที่ effect scene ต้องใช้) |
| ตัวอย่างอ้าง effect นอก addon | animation ตัวอย่างอ้าง `examples/runtime_demo/fx/*.tscn`; เทสต์ "addon อย่างเดียว" จึง copy ไฟล์ที่ generate แล้วไปด้วย | generator เขียนลง `res://addons/oasis_fx` ไม่ได้ (ตั้งใจ); เกมจริงจะ generate effect ไว้ก่อนอยู่แล้ว |
| Preview ในแอป | สร้างตัวแทน scene จาก outline ด้วย node มาตรฐาน (Polygon2D/Sprite2D/Bone2D/…) + AnimationPlayer ที่เล่น Animation จาก builder ตัวเดียวกับ generator; event แสดงเป็น marker แทนการเล่น effect จริง | scene ของเกมโหลดในแอปไม่ได้อย่างปลอดภัย (resource/script ของเกม) |
| แพ็กเกจ | plugin `app/export/` ใส่ไฟล์ดิบของ rig, sprite sheet และ effect ตัวอย่างลง pck (Godot แปลง `.tscn` เป็น binary ตอน export) | validator อ่าน scene เป็นข้อความ และ exporter ต้อง copy ไฟล์ข้อความเข้าเกม |
| ยังไม่ทำ | bezier track, AnimationTree, การสร้าง/แก้ rig/IK/weight (Phase 4), เสียงแบบ audio track (ใช้ event + SFX แทน) | ขอบเขต Phase 3 |

ข้อค้นพบ:
- AnimationPlayer เรียก method track แบบ deferred (`callback_mode_method` ค่าเริ่มต้น) — เทสต์รอ 1 frame ก่อนตรวจ event
- Bone2D ที่ไม่มี bone ลูกเตือน "cannot calculate bone length" — rig ตัวอย่างตั้ง `length`/`bone_angle` เองแล้ว
- sprite sheet ต้องเว้นขอบใส ไม่งั้น texture filter ดึงพิกเซลเฟรมข้าง ๆ มา (เห็นจากภาพหน้าจอ แก้ใน tool แล้ว)

---

## 11. ภาคผนวก (2026-10-15): 0.5.1 — export จากแอปที่แพ็กแล้วตรงกับ CLI

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| ต้นเหตุ | Godot release template: `Resource.set_id_for_path()` ไม่มีผล และค่า default ของ property ใน script ไม่รู้ (ข้อมูลฝั่ง editor) | ยืนยันจากไฟล์จริงที่ build Linux เขียน (ภาคผนวก 9) |
| วิธีแก้ | generator ตั้ง id แบบเดิม **และ** หลังบันทึกแปลงข้อความเอง (`normalize_saved_text()`): เปลี่ยน id ของ ext_resource ตามแผนที่ path → id, เรียงตาม id, เปลี่ยน `ExtResource("…")` ทุกที่, ตัด property ของ root node ที่เท่าค่า default ของ runtime script (ค่า default ได้จากการสร้าง instance ของ script) | ใช้โค้ดทางเดียวกันทั้ง CLI และแอป; ข้อความจาก editor ไม่เปลี่ยน (golden ทั้งหมดเหมือนเดิม) จึงไม่ต้อง migrate ไฟล์ที่ CLI สร้างไว้แล้ว |
| ทางเลือกที่ไม่ใช้ | ให้แอปเขียน `.tscn` เองทั้งไฟล์ / ปิดการแปลงในแอป | ซ้ำกับ ResourceSaver ของ Godot และเสี่ยงต่างจาก CLI มากกว่า |
| หลักฐาน | fixture จริงจาก build ที่แพ็กแล้ว 4 ไฟล์ (ทุกชนิด) + smoke test ใน build ที่แพ็กแล้ว (`matches_cli`) + เทียบไฟล์ export กับ CLI ในเกมเดียวกัน | แยกระหว่างเทสต์ headless กับการตรวจใน release build จริง |

แก้ข้อสังเกตเดิมในภาคผนวก 9 ("ข้อความไม่ตรงกับ CLI"): ตั้งแต่ 0.5.1 ตรงกันแล้ว สำหรับ build Linux ที่ตรวจจริง; Windows ยังไม่ได้รัน


---

## 12. ภาคผนวก (2026-10-15): Phase 4 — Rigging (0.6.0)

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| รูปแบบ | preset ชนิดใหม่ `rig` (`<id>.rig.json` → `<id>.tscn`) ใช้ registry เดิม (`asset_types.gd`), field table `rig_spec.gd`, schema สร้างจาก table | validator/schema/serializer/CLI/แอปใช้ร่วมกันโดยไม่ต้องเขียนแยก |
| node ที่สร้าง | Skeleton2D + Bone2D (rest, length, bone_angle ตั้งเอง) + Sprite2D/Polygon2D แบบแข็ง + Marker2D + `SkeletonModification2DTwoBoneIK` + AnimationPlayer (RESET, `pose_<name>`) + `OasisAnimationEvents` | ทั้งหมดเป็น node มาตรฐานของ Godot 4.7.2; animation preset (Phase 3) ใช้กับ rig ที่สร้างได้ทันที |
| skin | เก็บใน dictionary ที่ export ของ `oasis_rig.gd` (`{skin: {part path: {texture, color, visible}}}`) | ไม่ต้องมี scene ซ้ำต่อชุด; คืนค่าเดิมได้เสมอ (เก็บค่า base ก่อนเปลี่ยน) |
| IK หลาย instance | runtime สร้าง modification stack ใหม่ต่อ instance ใน `_ready()` | instance ของ scene เดียวกันแชร์ stack resource; ทดลองแล้วว่าขาของ rig ตัวที่สองผิด; `resource_local_to_scene` ทำให้ log "Bone index out of range" |
| นำเข้า rig เดิม | อ่าน `.tscn` แบบข้อความด้วย `scene_outline.gd`, พับ transform ของ node คั่นกลางเข้า bone/part, ลำดับการวาด → `z_index` 0…100, ชื่อ → snake_case | ไม่โหลด/รัน script ของเกมและไม่แก้ scene เดิม; สิ่งที่แปลงไม่ได้รายงานเป็น note (weight, IK, skew, region, animation, ชื่อที่เปลี่ยน) |
| ขอบเขต | ไม่ทำ mesh deformation/bone weight, IK แบบอื่น, rig อัตโนมัติ | สเปก §10 ให้ "optional deformation" และให้ทำอย่างสมจริง; weight ต้องมีเครื่องมือวาด weight ซึ่งเกินขอบเขต milestone นี้ |

ข้อค้นพบ:
- IK ใน headless ทำงาน (ทดสอบก่อนเริ่ม); modification stack ต้อง `enabled = true` และ target เป็น path เทียบกับ Skeleton2D
- import: ถ้า z ของชิ้นส่วนติดลบ ชิ้นส่วนจะไปอยู่หลังพื้นหลังของเกม → เริ่มที่ 0
- แอป: แถบ preview ยาวเกินหน้าจอเมื่อเพิ่มตัวเลือก skin/pose → ย้ายไปแถวของตัวเอง (เห็นจากภาพหน้าจอ); list editor ซ้อนกันวางเต็มความกว้าง

---

## 13. ภาคผนวก (2026-10-15): 0.7.0 — ชิ้นส่วนบิดงอตาม bone (optional deformation ของ Phase 4)

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| วิธีดัด | ดัดจุดบน CPU ใน `oasis_rig.gd` (`update_deformation()`, `process_priority` 1000 ให้ทำหลัง animation/IK) ด้วยสูตร skinning ของ Godot; ตัวเลือก `gpu_deform` สำหรับใช้ GPU | spike: GPU skinning ใน Compatibility renderer (Mesa llvmpipe) วาดจุดของ bone ตัวที่ 2 ขึ้นไปผิด แม้ในท่าปกติ — ตรวจด้วยภาพจริงหลายแบบ (ภาพ spike ไม่ได้ commit); CPU ตรวจด้วยเทสต์ headless ได้ |
| ที่เก็บ weight | `Polygon2D.bones` แบบมาตรฐาน (path เทียบกับ Skeleton2D) และปล่อย `skeleton` ว่าง | scene ยังเป็นรูปแบบของ Godot; เปิด GPU ได้ภายหลังโดยไม่ต้องแปลงข้อมูล |
| schema | field optional ใหม่ใน part: `weights`, `uv`, `internal_vertex_count`, `polygons`; ชนิด field ใหม่ `number_list`, `index_lists` | ไม่ต้องขึ้น schema_version; preset เดิมยังถูกต้องและไฟล์ scene ที่สร้างเหมือนเดิมทุก byte (hash ของ preset ใน manifest เปลี่ยนเพราะมีค่า default ใหม่) |
| part ที่บิดงอ | ต้องติดกับ root (`bone` "") | จุดของมันขยับตาม bone หลายตัวอยู่แล้ว ถ้าติดกับ bone ด้วยจะถูกขยับซ้ำ |
| weight อัตโนมัติ | 2 bone ที่ใกล้ที่สุดต่อจุด, 1/d⁴ แล้ว normalize, ปัดเศษ 0.001 | เรียบง่ายและคาดเดาได้; จุดบนข้อต่อได้ครึ่งต่อครึ่ง; ไม่มีแปรงระบาย (เกินขอบเขต) |
| นำเข้า | เก็บ weight เมื่อ `skeleton` ของ Polygon2D ชี้ไปที่ Skeleton2D ที่นำเข้า (หรือว่างใน rig ของ OasisFx); ข้าม IKTargets ของ rig ที่ OasisFx สร้าง | weight ที่ไม่มี skeleton ไม่ทำให้ Godot ดัดอยู่แล้ว → นำเข้าแบบแข็งพร้อม note |

---

## 14. ภาคผนวก (2026-10-16): 0.8.0 — WAV mixdown และ GitHub CI

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| วิธี mixdown | `AudioStreamPlayback.mix_audio()` ต่อ layer, รวมเองใน GDScript (`sfx_mixdown.gd`) | ทำงานใน headless โดยไม่ต้องมีการ์ดเสียง/หน้าจอ (ทดลองแล้ว); Movie Maker (ภาคผนวกเดิมใน sfx_format.md) ต้องมีหน้าจอและเขียนภาพทุกเฟรม |
| กฎเวลา | เรียก `_layer_duration` / `_fade_gain` ของ `oasis_sfx_effect.gd` โดยตรง | ไม่มีโค้ดซ้ำ ผลจึงตรงกับที่เกมเล่น |
| การสุ่ม | mixdown เป็น take เดียว: ไฟล์ที่ `variant` ของแต่ละ layer, ไม่สุ่ม pitch/volume | ไฟล์เสียงหนึ่งไฟล์เก็บความสุ่มไม่ได้; ผลเหมือนเดิมทุกครั้ง (ทดสอบได้) |
| clip | รายงานจำนวน sample; `--normalize` (−1 dBFS) แบบเลือกเอง; แอป normalize เฉพาะเมื่อจะ clip และบอกผู้ใช้ | ไม่เปลี่ยนความดังแบบเงียบ ๆ ใน CLI |
| CI | GitHub Actions บน ubuntu-24.04, Godot 4.7.2 จาก release ทางการ + ตรวจ SHA-256 (ตรงกับ binary ที่ใช้ใน session นี้), import → validate-all → format --check → เทสต์ทั้งหมด | สเปก §6 แนะนำ; ผู้ใช้ตอบ "ทำต่อเลย" หลังจากเสนอ CI; ไม่ build ตัวติดตั้งเพราะ export templates ใหญ่ |

---

## 15. ภาคผนวก (2026-10-16): 0.8.1 — วัดประสิทธิภาพฝั่ง CPU

| เรื่อง | การตัดสินใจ | เหตุผล |
|---|---|---|
| วิธีวัด | จับเวลาช่วง process ของแต่ละเฟรมด้วย node ที่ทำงานก่อนสุดและหลังสุด | `Performance.TIME_PROCESS` ไม่ได้อัปเดตทุกเฟรมใน headless (ค่า p95 เท่ากับ max ทุกครั้งในการวัดรอบแรก) |
| ฉากทดสอบ | ใช้เฉพาะ asset ตัวอย่างที่ generate แล้ว, สุ่มแบบมี seed | ทำซ้ำได้; ใช้ทั้งในเครื่องมือวัดและในเทสต์ |
| pooling / quality presets | ยังไม่ทำ | ฉากหนักใช้ CPU เฉลี่ย 3.2 ms/เฟรม (ไม่ถึง 16.7 ms ของ 60 fps); GPU วัดไม่ได้ (NOT RUN) |
| การดัดบน CPU | sparse weights (normalize ครั้งเดียว) + ข้ามเมื่อ transform เท่าเดิม | งู 50 จุด × 6 bone: 89 → ~22–37 µs ต่อเฟรมขณะขยับ, ~0 ขณะนิ่ง |
| ข้อความ "resources still in use at exit" ในเครื่องมือ | รอ 0.5 วินาทีก่อนออก | เกิดจากออกโปรแกรมเร็วเกินไปขณะ audio server ยังถือ stream ของเสียงวนลูป ไม่ใช่การรั่วของ runtime (ตรวจด้วย --verbose) |
