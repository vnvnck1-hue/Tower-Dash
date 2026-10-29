# 타워대시 모델링에 "구조적 텍스처링" 적용 방향

참고 기사: 80.lv — *Structural Approach to Texturing a Temple* (Bart de Vries, Desecrated Temple, 2019).
핵심은 "자산을 쪼개고, 자산마다 **텍스처 전략을 미리 정해** 시트로 관리한 뒤, 트림시트·타일링·공유 UV·메시 데칼로 텍스처 예산을 아끼고, 베이크를 끝낸 뒤에 색·조명을 잡는다"는 것.

예시 캡처: `screenshots/trim/` (아래 각 절에 파일명).
예시 코드: `scripts/trim_kit.gd`, `shaders/toon_trim.gdshader`, `tools/build_trim_sheet.gd`, `tools/preview_trim.gd`, `tools/blender_bake_step.py`.

---

## 0. 현재 상태와 기사 방식의 차이

| | 현재 타워대시 | 기사 방식 |
|---|---|---|
| 지오메트리 | `MeshBuilder` 가 탑·나선 계단·소품을 전부 **절차적으로 생성** | 블록아웃 → 부품 단위로 쪼개 하이폴 스컬핏 → 로우폴 베이크 |
| 표면 디테일 | `toon_stone.gdshader` 가 벽돌·모르타르·때·눈을 **셰이더 안에서 절차적으로** 계산 (텍스처는 `brick_detail.png` 1장) | 트림시트 1장 + 타일링 3장 + 고유 텍스처 소수 + 메시 데칼 |
| 눈·칩 | 버텍스 컬러(COLOR.b)로 눈, 셰이더 노이즈로 때 | 엣지 베이크 데칼 스트립을 표면 위에 띄움 |
| 반복 단위 | PITCH(24) 의 정수 분할로 모든 패턴 주기 고정 | 모듈(한 계단 블록)을 복제·변형 |

절차적 방식은 되감기 이음새가 없고 파라미터로 바로 튜닝된다는 장점이 커서 **통째로 교체할 이유는 없다.** 기사에서 가져올 것은 "표면을 그리는 방법"이 아니라 **자산을 분류하고 디테일을 어디에 둘지 정하는 구조**다.

---

## 1. 자산 분류 시트 (기사의 엑셀 색상 코드)

기사처럼 모든 자산에 전략 색을 붙인다. 캡처 `screenshots/trim/breakdown.png` 가 실제 씬을 이 색으로 칠한 것이다.

| 색 | 전략 | 타워대시 자산 | 비고 |
|---|---|---|---|
| 핑크 | **트림시트** (가로 타일링 띠 1장) | 계단 모듈의 라이저·바깥면 눈 띠·슬래브 몸체, 난간·코벨 캡·갤러리 상판·사슬 앵커 | 세로 방향 반복이 없는 "띠" 모양 면 전부 |
| 하늘색 | **타일링 텍스처** | 탑 벽(벽돌), 배경 벽(석재+회반죽), 디딤판 윗면·밑면(플래그스톤) | 넓고 평평한 면. 지금의 절차적 벽돌을 그대로 써도 분류상 여기 |
| 노랑 | **텍스처 1장 공유 + 복제/미러** | 종, 샹들리에, 사슬(MultiMesh), 벽 계단, 고블린 파츠 | 한 번 만들고 인스턴스 |
| 빨강 | **고유 텍스처** | 깃발 문장, 촛불, 플레이어 검 | 화면에서 시선이 가는 곳에만 허용 |
| 보라 | **메시 데칼** (알파 스트립, 표면 1.5cm 위) | 눈 모자·눈 코(계단 코), 깨진 모서리, 혈흔(이미 Decal 노드) | 지오메트리를 스컬핑하지 않고 엣지를 정의 |

규칙: 새 소품을 추가할 때 먼저 이 표의 한 칸에 넣는다. 빨강이 늘어나면 설계가 잘못된 것이다(기사: 빨강은 문·해골 등 몇 개뿐).

---

## 2. 트림시트 1장으로 "띠 모양 면" 통일

`textures/trim_sheet.png` (1024×512, 128px = 1 world unit, 가로 8u 반복). 캡처 `screenshots/trim/trim_sheet_labeled.png`.

| 행 | 픽셀 | 월드 높이 | 용도 |
|---|---|---|---|
| R0 코니스 몰딩 | 0–64 | 0.5u | 난간 상판, 코벨 캡, 갤러리 가장자리 |
| R1 석판 코스 | 64–256 | 1.5u | 계단 슬래브 몸체(1.3u), 피어 몸체 |
| R2 눈 띠 | 256–352 | 0.75u | 계단 바깥면 윗단(SNOW_BAND 0.9 중 윗부분) |
| R3 라이저 석판 | 352–416 | 0.5u | 계단 라이저(0.375u) |
| R4 쇠띠+리벳 | 416–448 | 0.25u | 사슬 앵커, 난간 철물 |
| R5 데칼 눈 모자 | 448–480 | α | 디딤판 바깥 가장자리·계단 코 |
| R6 데칼 깨진 모서리 | 480–512 | α | 눈 띠 아래, 라이저 상단 |

- 시트는 `tools/build_trim_sheet.gd` 가 팔레트(`main.gd` 의 STAIR_LIT/STONE_SHADOW/SNOW/INK)로 **절차 생성**한다. 손그림으로 바꿀 때도 행 규격만 지키면 코드는 그대로다.
- 셰이더 `shaders/toon_trim.gdshader`: 텍스처는 **라이트 톤으로만** 칠하고, 그림자 밴드는 셰이더가 `shadow_tint` 쪽으로 내린다(`toon_stone` 과 같은 하드 밴딩 규칙, 잉크 픽셀은 재조명 안 함). 그래서 팔레트가 한 곳(main.gd)에 유지된다.
- 되감기 불변식: 트림 u 는 월드 호 길이이고 모듈마다 `INSTANCE_CUSTOM.x` 로 오프셋을 더하므로 한 바퀴 둘레(TAU×13.7 ≈ 86u)가 8u 의 정수배가 아니어도 모듈 경계에서만 이음새가 생긴다(모듈 경계는 원래 라이저 턱이라 안 보임).

---

## 3. 계단은 "모듈 1개 × 복제" (기사의 5단 계단 베이크)

기사는 계단 5단+측면 벽돌 2개를 한 번 스컬핑·베이크한 뒤 복제·변형했다. 타워대시는 나선이라 **쐐기 모듈 1개**를 `MultiMesh` 로 한 바퀴 64번 인스턴스한다.

- `TrimKit.step_module()` : 라이저·눈 띠·슬래브 몸체·측면(트림 서피스) + 디딤판·밑면(타일링 서피스). 모듈당 **14 쿼드**. 캡처 `kit_studio.png`, `kit_wire.png`.
- `TrimKit.build_run()` : 계단 k0..k1 에 `Transform3D(Basis(UP,(i+0.5)·da), (0, i·STEP_H, 0))` 로 배치, `STAIR_GAPS` 는 건너뜀. 적 배치용 `ClimbWorld.step_transform()` 과 같은 좌표계.
- 비교: 현재 `helix_stairs` 는 6.5바퀴 × 64단을 한 메시(약 416단 × 5면)로 만든다. 모듈 방식은 드로우콜 1개·메시 1개이고, 계단 디자인을 바꿀 때 모듈 하나만 고치면 된다.
- 캡처: `closeup_before.png` → `closeup_after.png`, `game_before.png` → `game_after.png` (계단 1~59번만 교체, 나머지는 기존 절차 계단이라 경계에서 두 방식을 나란히 볼 수 있음).

**남는 과제**: 현재 슬래브 밑면 아케이드(`arcade_enabled` 셰이더 컷아웃)는 모듈에 없다. 모듈로 가려면 아케이드 아치를 별도 "피어 모듈"(8개/바퀴, 노랑 분류)로 분리해야 한다.

---

## 4. 메시 데칼로 엣지 정의 (스컬핑 대신)

기사: 큐브 엣지만 스컬핑해 납작한 스트립에 베이크하고, 마스크를 칠해 건물 메시에서 살짝 띄웠다.

- `TrimKit.step_decals()` : 눈 모자(디딤판 바깥 0.5u + 턱 아래 0.32u), 눈 코(라이저 쪽 0.42u + 라이저 0.26u), 깨진 모서리 띠(눈 띠 아래 0.3u). 표면에서 0.015 띄우고 `alpha_cut` 로 자른다. 모듈당 5 쿼드.
- 지금의 버텍스 컬러 눈(`COLOR.b`, `snow_level`)을 대체할 수 있다. 데칼은 **텍스처만 바꿔 눈→이끼→핏자국** 으로 계절/스테이지 변주가 가능하고, 지오메트리는 그대로다.
- 혈흔은 이미 `Decal` 노드(투영 데칼)다. 벽면처럼 곡면이 큰 곳은 투영 데칼, 계단 엣지처럼 형태가 고정된 곳은 메시 데칼로 나눈다.

---

## 5. Blender 하이폴 → 로우폴 베이크 (이 PC: 헥스 블레이드/.tools 의 Blender 5.2.2)

기사처럼 "한 번 스컬핑하고 베이크해서 모듈에 굽는" 흐름을 계단 모듈 1개로 재현한 것이 `tools/blender_bake_step.py` 다. 캡처 `blender_bake_panel.png`, 베이크 `bake_normal.png` / `bake_ao.png` / `bake_edge.png`.

```bash
"D:/2020_이전승찬파일/작업,내파일/2026/프로토타입 게임/헥스 블레이드/.tools/blender/blender-5.2.2-windows-x64/blender.exe" -b --factory-startup --python-exit-code 1 --python tools/blender_bake_step.py -- --out screenshots/trim
```

- 하이폴: 박스 + Bevel(0.07, 3분할) + Simple Subdiv 3 + Clouds Displace(0.012) + 모서리 칩(아이코스피어 Boolean 7개).
- 로우폴: 12 트라이 박스, Smart UV. 베이크: 탄젠트 노멀, AO(선택→활성, 케이지 0.12).
- **엣지 마스크**는 Pointiness 대신 베이크된 노멀의 기울기(1−N.z)로 만든다. 평평한 모듈에서는 이쪽이 훨씬 깨끗하고, 그대로 R6 "깨진 모서리" 데칼 행의 소스가 된다.
- 로우폴 머티리얼은 Godot 셰이더와 같은 규칙(노멀·광원 내적 → 2밴드, 엣지 마스크 → 하이라이트)으로 미리보기한다. Blender 에서 보이는 것이 Godot 에서 보이는 것과 같아야 왕복이 줄어든다.

언제 쓰나: 절차 메시로는 안 나오는 형태(깨진 계단 코, 조각난 코벨, 종의 부조, 깃발 문장 양각)에 한해 Blender 에서 모듈을 만들고 glTF 로 들여온다. 탑 벽·계단 기본형은 절차 메시 유지.

---

## 6. 색·조명 순서 (기사의 가장 큰 교훈)

기사: 모든 자산을 **베이크까지 끝낸 뒤** 텍스처·조명을 했고(3.5개월 → 2주), 1차 텍스처 직후 조명을 넣어 어떤 색을 고칠지 판단했다.

타워대시 적용:
1. 자산 분류 시트(§1)와 트림 행 규격(§2)을 먼저 확정한다. 이후 소품 추가는 규격 안에서만.
2. 지오메트리/UV 단계에서는 `--flatdebug` 처럼 **회색 플랫 셰이딩**으로만 본다(`kit_studio.png` 가 그 상태). 색은 보지 않는다.
3. 1차 색은 팔레트 상수만으로(현재 `main.gd` 팔레트가 그 역할). 조명(`LIGHT_FROM`, 포커스 할로, 촛불 글로벌)을 켠 상태에서 고칠 색을 고른다.
4. 마지막에 LUT(`textures/grade_lut.png`, `--grade`)로 톤 통일. 기사도 LUT 로 마무리했지만, 우리 LUT 는 현재 레퍼런스에서 멀어져 꺼져 있다. 트림/데칼 색이 들어온 뒤 `tools/build_lut.py` 를 다시 돌려 재평가.

---

## 7. 단계별 실행 계획

| 단계 | 내용 | 산출물 | 판단 기준 |
|---|---|---|---|
| A | 자산 분류 시트 확정, README 에 표 추가 | 이 문서 §1 | 빨강(고유) 5개 이하 |
| B | 트림시트 행 규격 확정 → 손그림(또는 Aseprite) 으로 교체 | `textures/trim_sheet.png` | `trim_sheet_labeled.png` 와 같은 행 구조 |
| C | 계단 모듈을 본 게임에 적용(`helix_stairs` → `TrimKit` MultiMesh), 아케이드 피어 모듈 분리 | `main.gd _build_world` | 플레이 중 되감기 이음새 없음, 드로우콜 감소 |
| D | 눈/칩 메시 데칼로 버텍스 눈 대체, 스테이지별 데칼 텍스처 | `TrimKit.step_decals` | 데칼 텍스처만 바꿔 분위기 전환 가능 |
| E | 난간·캡·갤러리 상판을 R0/R4 트림으로 | `MeshBuilder.box` 에 trim UV 모드 | 소품 머티리얼 수 감소 |
| F | Blender 모듈(깨진 코, 종 부조 등) glTF 임포트 파이프라인 | `assets/kit/*.glb` | `toon_trim` 로 바로 렌더 |
| G | 조명 켠 상태로 색 재조정, LUT 재생성 | 팔레트 상수, `grade_lut.png` | 키비주얼 대비 |

C 가 가장 큰 변경이라 다른 세션이 `main.gd`/`mesh_builder.gd` 를 편집 중인 지금은 건드리지 않았다. 이 예시는 `tools/preview_trim.gd` 가 런타임에 계단 범위를 교체해 보여 준 것이다.

---

## 8. 예시 재현

```bash
# 1) 트림시트·플래그스톤 텍스처 생성
/e/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tools/build_trim_sheet.gd
```

```bash
# 2) 전후·분류·키트·시트 캡처 (screenshots/trim/*.png)
/e/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . --windowed --script tools/preview_trim.gd -- --out=screenshots/trim
```

| 파일 | 내용 |
|---|---|
| `game_before.png` / `game_after.png` | 기본 카메라, 계단 1~59번을 모듈 키트로 교체 전/후 |
| `closeup_before.png` / `closeup_after.png` | 계단 근접. 왼쪽 끝이 기존 절차 계단과의 경계 |
| `breakdown.png` | 자산별 텍스처 전략 색상 코드(§1) |
| `kit_studio.png` / `kit_wire.png` | 모듈 7개만 회색 스튜디오, 와이어프레임 |
| `trim_sheet_labeled.png` | 트림시트 행 설명 |
| `blender_bake_panel.png`, `bake_*.png` | Blender 하이폴→로우폴 베이크 + 메시 데칼 데모 |
