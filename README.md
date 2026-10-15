# white-sahara-studio — OasisFx

ชุดเครื่องมือสร้าง asset (VFX, SFX, Animation และ Sprite frames) สำหรับ Godot 4
ชื่อเครื่องมือคือ **OasisFx** (ในสเปกเดิมเรียกว่า "Godot Asset Studio")

แนวคิด: คน, ChatGPT หรือ Claude เขียน **preset เป็น JSON** → CLI ตรวจความถูกต้อง →
สร้างไฟล์ `.tscn` ที่ใช้ node มาตรฐานของ Godot → นำไปใช้ในเกม White Sahara หรือเกมอื่นได้

## เป้าหมายที่ปรับแล้ว (2026-10-15)

ปลายทางคือ **โปรแกรม Windows Desktop ที่สร้างด้วย Godot + Headless CLI ใช้ Core ร่วมกัน**
คนเปิดแอปเพื่อแก้ preset, preview และ export ได้โดยไม่ต้องเปิด Godot Editor ส่วน AI เรียก CLI
ในเครื่องหรือ cloud ที่มี source และ Godot พร้อมใช้งาน

**Phase 1C ทำแล้ว:** แอปอยู่ใน `app/` build เป็น `OasisFx.exe` ได้ (ดู [desktop.md](addons/oasis_fx/docs/desktop.md))
**Phase 2 ทำแล้ว:** สร้างเสียงแบบหลาย layer (SFX) ได้ทั้งใน CLI และแอป (ดู [sfx_format.md](addons/oasis_fx/docs/sfx_format.md))
**Phase 3 ทำแล้ว:** animation แบบ keyframe + event สำหรับ scene ที่มีอยู่แล้ว (เช่นตัวละครที่ใช้ Skeleton2D) และ sprite frames จาก sprite sheet (ดู [animation_format.md](addons/oasis_fx/docs/animation_format.md))

![OasisFx desktop app](docs/images/desktop_app.png)

![OasisFx — แก้เสียง](docs/images/desktop_sfx.png)

![OasisFx — แก้ animation](docs/images/desktop_animation.png)

รายละเอียดและคำสั่งงานล่าสุดอยู่ใน [Spec v1.1](Godot_Asset_Studio_Claude_Code_Implementation_Spec.md)
และ [CLAUDE.md](CLAUDE.md) ซึ่งใช้แทนทิศทาง UI เดิมใน audit

## สถานะ

| Phase | เนื้อหา | สถานะ |
|---|---|---|
| 0 | สำรวจ repo และสภาพแวดล้อม ([AUDIT.md](AUDIT.md)) | ✅ เสร็จ |
| 1A | schema, loader, validator, CLI `validate`/`generate`, Fire Burst, headless tests | ✅ เสร็จ (แก้ test runner ตาม review แล้ว) |
| 1B | หลาย emitter (สูงสุด 8), preset ตัวอย่าง 5 แบบ, validate-all/generate-all, manifest, runtime lifecycle, demo, AI guide | ✅ เสร็จ |
| 1C | แอป Windows แยก: preset editor, preview, save/export และ Windows package | ✅ ทำแล้ว รอรับงาน (ยังไม่ได้ทดสอบบนเครื่อง Windows จริง) |
| 2 | SFX Composer: preset เสียงหลาย layer, runtime, timeline ในแอป, export เสียงเข้าเกม | ✅ ทำแล้ว รอรับงาน (ยังไม่ได้ฟังเสียงจริง — cloud ไม่มีลำโพง) |
| 3 | Animation Timeline: keyframe ของ node ใน scene เดิม (bone, sprite, polygon), event ที่เรียก VFX/SFX, sprite frames, timeline + preview ในแอป | ✅ ทำแล้ว รอรับงาน (ยังไม่ได้ลองกับตัวละครจริงของ White Sahara — repo เกมไม่อยู่ใน session นี้) |
| 4 | Rigging (สร้าง/แก้ rig, IK, costume) | ยังไม่เริ่ม |

## โครงสร้าง repo

```
project.godot          โปรเจกต์ของแอป (main scene = app/main.tscn) และ host สำหรับเทสต์ addon
addons/oasis_fx/       ตัว addon — copy โฟลเดอร์นี้ไปใส่เกมได้เลย
examples/runtime_demo/ เดโมการใช้ effect ในเกม + scene ที่ generate แล้ว (ใช้เป็น golden test)
tests/                 เทสต์ระดับ repo (แอป, เดโม และ golden files)
docs/images/           ภาพ preview ที่ render จริง
app/                   แอป desktop (main.tscn, ui/, services/, export/ = plugin ตอน build)
export_presets.cfg     การตั้งค่า export สำหรับ Windows และ Linux
tools/                 เครื่องมือสำหรับนักพัฒนา (render ภาพ preview, สังเคราะห์เสียงและวาด sprite sheet ตัวอย่าง)
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
(คลิกซ้าย = Fire Burst, คลิกขวา = Ice Nova, Space = ฟันดาบ, C = ทำอาหาร, A = เชฟฟาดทัพพี, S = เชฟดีใจ) — effect ที่มีเสียงคู่กันจะเล่นเสียงด้วย

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
[รูปแบบ preset เสียง](addons/oasis_fx/docs/sfx_format.md),
[รูปแบบ animation และ sprite frames](addons/oasis_fx/docs/animation_format.md),
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
- รันจาก source: ไฟล์ที่ได้เหมือนกับที่ CLI สร้างทุก byte; **build ที่แพ็กแล้วได้ scene ที่ทำงานเหมือนกันแต่ข้อความไม่ตรงกันทุก byte**
  (id ของ ext_resource เป็นตัวเลข และเขียนค่า default ลงไปด้วย เพราะ Godot release build ไม่มีข้อมูลฝั่ง editor — พบตอนทำ Phase 2)
- copy runtime script ให้เฉพาะเมื่อเกมยังไม่มี

**ผลการตรวจ:**
- เทสต์ทั้งหมด **116 passed, 0 failed**
- build Linux ที่แพ็กแล้วผ่าน `--smoke-test` และ export เข้าโฟลเดอร์ชื่อไทยได้
- scene ที่ export เปิดเล่นในโปรเจกต์แยกได้
- **NOT RUN:** การเปิด .exe บน Windows จริง, file dialog ของ Windows และ GPU จริง (มี checklist ให้ทดสอบเองใน [desktop.md](addons/oasis_fx/docs/desktop.md))

~~ยังไม่รองรับ export preset ที่ใช้ไฟล์ภาพ~~ → Phase 2 รองรับแล้ว ถ้าไฟล์อยู่ในโปรเจกต์เกม (ดูด้านล่าง)

## Phase 2: SFX Composer

preset เสียง (`<id>.sfx.json`) คือการ **เรียงไฟล์เสียงที่มีอยู่แล้ว** (wav/ogg/mp3) หลาย layer —
เริ่มเมื่อไร ดังเท่าไร pitch ตัดช่วงไฟล์ fade loop และสุ่มไฟล์/pitch/ความดังทุกครั้งที่เล่น
OasisFx ไม่ได้สร้างเสียงเองหรือดาวน์โหลดเสียง

```json
{"schema_version": 1, "asset_type": "sfx", "id": "sword_slash_sfx", "display_name": "Sword Slash SFX",
 "layers": [
   {"id": "whoosh", "source": "res://audio/whoosh_1.wav", "variants": ["res://audio/whoosh_2.wav"], "random_pitch_percent": 6, "source_license": "CC0"},
   {"id": "impact", "source": "res://audio/impact.wav", "start_ms": 140, "gain_db": -3, "source_license": "CC0"}]}
```

- **ได้อะไร:** `<id>.tscn` = `Node2D` + `AudioStreamPlayer`/`AudioStreamPlayer2D` ต่อ layer + runtime
  `OasisSfxEffect` (เล่นตาม offset, สุ่ม variant ไม่ซ้ำไฟล์เดิมติดกัน, fade, trim, loop, ลบตัวเองเมื่อจบ)
  ใช้ในเกม: `OasisSfxEffect.spawn(preload("res://sfx/sword_slash_sfx.tscn"), self, position)`
- **CLI เดิมทุกคำสั่งรองรับ `.sfx.json`:** `validate`, `validate-all`, `generate`, `generate-all`, `format`, `schema sfx`
- **schema:** `schemas/sfx.v1.schema.json` สร้างจากตาราง field `sfx_spec.gd` เหมือน VFX; VFX v1 ไม่เปลี่ยน
- **ตัวอย่าง 4 เสียง:** `sword_slash_sfx`, `fire_burst_sfx`, `cooking_success_sfx`, `cooking_sizzle_loop`
  ใช้ไฟล์เสียงที่สังเคราะห์เองด้วย `tools/synth_example_sounds.gd` (CC0) เดโมเล่นเสียงคู่กับ effect แล้ว
- **License:** ทุก layer มี `source_author`/`source_license` ถ้าว่างจะเตือน
- **แอป:** ปุ่ม *New sound*, timeline แสดง layer/fade/loop/playhead, เลือก **Game project…** แล้วปุ่ม **…**
  แปลงไฟล์ในเกมเป็น `res://` ให้อัตโนมัติ, export เข้าเกม: ไฟล์ที่เกมมีอยู่แล้ว = ใช้ (ไม่เขียนทับ),
  ไฟล์ตัวอย่างของ OasisFx = copy ให้ (พร้อมคำเตือน), ไฟล์ที่ไม่มีที่ไหนเลย = error
- **WAV mixdown:** ยังไม่ทำ ทดลองแล้วว่าเป็นไปได้ด้วย Movie Maker ของ Godot (ต้องมีจอ/Xvfb) — รายละเอียดใน sfx_format.md

**ผลการตรวจ Phase 2:**
- เทสต์ทั้งหมด **142 passed, 0 failed** (exit 0) และได้ผลเดียวกันบนสำเนาใหม่ที่ไม่มี `.godot/`
- preset ตัวอย่าง 9 ไฟล์ผ่าน JSON Schema ด้วย Python `jsonschema`
- build Linux/Windows ใหม่, Linux ผ่าน `--smoke-test` (preview เสียงและ export เสียงเข้าโฟลเดอร์ชื่อไทย)
- **NOT RUN:** ฟังเสียงจริง (ไม่มีอุปกรณ์เสียงใน cloud), เปิด .exe บน Windows, GPU จริง


## Phase 3: Animation Timeline

มี preset ใหม่ 2 แบบ:

| ชนิด | ไฟล์ | ได้อะไร | ใช้ทำอะไร |
|---|---|---|---|
| `animation` | `<id>.anim.json` | `<id>.tres` (Godot Animation) | ขยับ node ของ scene ที่มีอยู่แล้วในเกม (เช่น bone ของ Skeleton2D, sprite, polygon) ด้วย keyframe + **event** (hit_frame, footstep, cooking_complete) ที่เรียก VFX/SFX ของ OasisFx |
| `sprite_frames` | `<id>.frames.json` | `<id>.tres` (SpriteFrames) | ตัด animation แบบทีละเฟรมจาก sprite sheet ไปใช้กับ AnimatedSprite2D |

- **ไม่สร้าง/ไม่แก้ rig เดิม:** preset ชี้ไปที่ scene ของเกม (`target_scene`) และอ่านไฟล์ `.tscn` แบบ **ข้อความ**
  เพื่อตรวจว่า node path มีจริงและเป็นชนิดที่ถูกต้อง (ไม่โหลดหรือรัน script ใด ๆ) ถ้าพิมพ์ path ผิดจะบอก path ที่น่าจะใช่
- **ปลอดภัย:** property ที่ animate ได้มีแค่ position, rotation_degrees, scale, opacity, modulate, visible, frame, z_index
  และ event เรียกได้เฉพาะ method ตายตัว `OasisAnimationEvents.oasis_event()` ซึ่งแสดงได้เฉพาะ scene ที่ OasisFx สร้าง
- **Event เป็นแค่ภาพ/เสียง:** ไม่ตัดสินดาเมจ เกมฟัง signal `event_triggered` เองได้
- **ตัวอย่าง:** rig เชฟ (`presets/examples/rigs/chef_rig.tscn`) + animation 3 แบบ (idle วนลูป, ฟาดทัพพีพร้อมไฟและเสียงตอนโดน,
  กระโดดดีใจพร้อมประกาย) + sprite sheet เปลวไฟ CC0 ที่วาดด้วย `tools/synth_example_sprites.gd`
- **แอป:** เมนู *New ▾* มี Animation / Sprite frames; preview สร้างตัวแทนของ scene จากไฟล์ข้อความแล้วเล่น animation จริง,
  timeline แสดง track/key/event (คลิกเลือก track, ลากเพื่อดูท่า), แก้ key/event ได้, เลือก node จากรายการ,
  sprite frames แสดง sheet พร้อมกริดและเฟรมปัจจุบัน; export `.tres` เข้าเกมพร้อม effect ที่ event ใช้
- **โครงสร้างภายใน:** เพิ่ม registry ของชนิด asset (`asset_types.gd`) ให้ validator/schema/serializer/generator/CLI/แอป
  ใช้ร่วมกัน — schema และ golden ของ VFX/SFX ออกมาเหมือนเดิมทุก byte

**ผลการตรวจ Phase 3:**
- เทสต์ทั้งหมด **163 passed, 0 failed** (exit 0) และได้ผลเดียวกันบนสำเนาใหม่ที่ไม่มี `.godot/`
- preset ตัวอย่าง 13 ไฟล์ผ่าน JSON Schema ทั้ง 4 แบบด้วย Python `jsonschema`
- animation ที่สร้างเล่นบน rig จริงใน Godot (ท่า, event, effect เกิดที่ปลายทัพพี) และ export เข้าโปรเจกต์แยกแล้วเล่นได้
- build Linux/Windows ใหม่, Linux ผ่าน `--smoke-test` ครบทั้ง 4 ชนิด (export เข้าโฟลเดอร์ชื่อไทย), ภาพหน้าจอจริงอยู่ใน `docs/images/`
- **NOT RUN:** เปิด .exe บน Windows, ลองกับตัวละครจริงของ White Sahara, GPU จริง

## License

MIT — ดู [LICENSE](LICENSE)
