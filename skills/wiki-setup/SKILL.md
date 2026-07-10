---
name: wiki-setup
description: 새 볼트를 초기화하거나 깨진 설정을 복구할 때 사용 — "wiki 초기화", "볼트 설정", "set up wiki", "/wiki-setup [--repair|--update-path|--update-qmd]".
---

# wiki-setup

## 개요
볼트를 초기화하거나 복구한다. **다른 어떤 wiki 스킬보다 먼저 실행되어야 한다** — 모든 스킬이 의존하는 볼트 설정(`.wiki-config.json`)과 전역 포인터(`~/.llm-wiki/default-vault`)를 이 스킬이 만든다. **유일하게 Config Gate를 실행하지 않는 스킬**이다 — 게이트(`resolve-vault.sh`)가 읽을 설정이 아직 없는 시점에 실행되므로, 스스로 config를 생성하는 것 자체가 이 스킬의 일이다.

## 언제 사용
- **트리거:** "wiki 초기화", "볼트 설정", "set up wiki", `/wiki-setup [--repair|--update-path|--update-qmd]`.
- **아니면:** 볼트가 이미 정상 동작 중이면 다시 실행할 필요 없다 — 다른 wiki 스킬은 각자 Config Gate로 기존 설정을 읽는다.

## 모드

| 플래그 | 동작 |
|---|---|
| (없음) | 대화형 초기화 — 볼트 경로를 묻고 각 단계를 확인하며 진행 |
| `--vault <path>` | 워크플로우 Step 1 질의 스킵, 지정한 경로를 볼트로 사용 |
| `--yes` | `--vault`와 함께 사용. Step 2 이하 모든 확인을 기본값 수락으로 진행(단, 전역 포인터가 *다른* 볼트를 가리킬 때는 예외 — Step 4 참고) |
| `--repair` | 기존 `.wiki-config.json` 경로 재검증 + 누락된 필수 파일·디렉터리만 재생성. 전역 포인터는 건드리지 않음 |
| `--update-path` | 볼트가 이동/이름변경됐을 때 config + 전역 포인터를 재지정. 상세는 [재지정·재정합](#재지정재정합) |
| `--update-qmd` | QMD 컬렉션 전체 reconcile(update+embed+ls). 상세는 [재지정·재정합](#재지정재정합) |

**멱등(idempotent) — 존재 여부만 확인한다.** 아래 워크플로우가 다루는 모든 파일·디렉터리는 없으면 생성하고 있으면 그대로 둔다. 포맷이 오래돼 보여도 기존 내용을 절대 덮어쓰지 않는다 — stale 포맷 진단은 `wiki-lint --fix`의 일이지 이 스킬의 일이 아니다.

## 워크플로우

1. 볼트 절대 경로를 묻는다 (`--vault`가 있으면 스킵).
2. `raw_dir="raw"`, `wiki_dir="wiki"` 기본값을 제안하고 확인받는다 (`--yes`면 자동 수락).
3. `<vault>/.wiki-config.json`을 작성한다 — 스키마는 최소주의로 유지한다("볼트가 어디인가"에만 답한다; QMD·플래그·기능 키는 두지 않는다):
   ```json
   { "version": 1, "vault": { "path": "<abs>", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "YYYY-MM-DD" }
   ```
4. 전역 포인터 `~/.llm-wiki/default-vault`(볼트 절대 경로 한 줄)를 쓴다.
   - 이미 존재하고 **다른** 경로를 가리키면 `old → new`를 보여주고 확인 후 덮어쓴다. `.bak` 백업은 만들지 않는다 — 되돌리려면 그 경로로 `--update-path`를 다시 실행하면 된다.
   - **MUST:** `--yes`에서도 다른 볼트를 가리키는 포인터를 조용히 덮어쓰지 않는다. 중단하고 `--update-path`를 명시적으로 실행하라고 사용자에게 알린다 — 비대화형 실행이 다른 볼트의 포인터를 가로채선 안 된다.
   - 이 포인터 덕분에 어느 디렉터리에서 실행하든 다른 스킬이 볼트를 resolve할 수 있다.
5. 없으면 고정 디렉터리를 생성한다: `wiki/concepts/` `wiki/knowledge/` `wiki/entities/` `wiki/projects/` `wiki/meetings/` `wiki/archived/`.
   - ❌ `wiki/summaries/` 하위 폴더는 여기서 만들지 않는다 — ingest가 `raw/` 구조를 미러링하며 그때그때 만든다(YAGNI).
   - ❌ `raw/` 하위 폴더, `benchmark/`, `meta/`도 만들지 않는다.
6. `wiki/index.md` — 없으면 초기 템플릿을 생성한다. **최상위 카테고리 섹션만 시드한다**: `summaries` / `concepts` / `knowledge` / `entities` / `projects`. 서브섹션(`summaries/web`, `summaries/sessions` 등)은 하드코딩하지 않는다 — 해당 서브섹션이 처음 필요한 시점에 그 ingest 계열 스킬(`ingest-url`·`wiki-capture` 등)이 직접 만든다.
   ```markdown
   # Index

   ## summaries
   | 페이지 | 설명 |
   |---|---|

   ## concepts
   | 페이지 | 설명 |
   |---|---|

   ## knowledge
   | 페이지 | 설명 |
   |---|---|

   ## entities
   | 페이지 | 설명 |
   |---|---|

   ## projects
   | 페이지 | 설명 |
   |---|---|
   ```
7. `wiki/log.md` — 없으면 날짜 찍힌 `INIT` 항목으로 시드한다(원장; frontmatter 없는 plaintext).
   ```
   [YYYY-MM-DD] INIT — vault created
   ```
8. `wiki/hot.md` — 없으면 아래 템플릿으로 생성한다. **이 템플릿이 hot.md의 단일 출처다** — 다른 쓰기 스킬은 "hot.md 없으면 §4-1 Step 8 템플릿으로 생성"이라고 이 위치만 인용하고 재서술하지 않는다.
   ```
   ---
   title: Hot Cache
   updated: YYYY-MM-DD
   ---
   # Hot Cache
   *A ~500-word semantic snapshot of recent activity.*
   ## Recent Activity
   - [TIMESTAMP] INIT — vault created
   ## Active Threads
   *None yet.*
   ## Key Takeaways
   *None yet.*
   ## Flagged Contradictions
   *None yet.*
   ```
   **복구 예외:** `log.md`는 있는데 `hot.md`가 없으면(마이그레이션·`--repair`), 빈 템플릿 대신 `log.md`의 최근 ~10개 항목으로 Recent Activity를 재구성한다.
9. QMD 설정을 확인한다 — "qmd가 설치돼 있나요?"
   - 설치됨 → `${QMD_CLI:-qmd} collection add <vault>/<wiki_dir> --name wiki` (이미 `qmd collection list`에 경로가 있으면 생략) → `qmd update` 실행. QMD 설정은 어디에도 저장하지 않는다 — qmd 자체 레지스트리가 단일 출처. 빈 볼트는 `update`만 하고 `embed`는 하지 않는다.
   - 미설치 → "Grep fallback으로 동작합니다. 설치 후 `/wiki-setup --update-qmd`로 등록할 수 있습니다." 안내.
10. `<vault>/.manifest.json` — 없으면 `{ "version": 1 }`로 생성한다.
11. `<vault>/.wiki-config.example.json` — 절대 경로를 제거한 빈 템플릿을 생성한다(git 추적 대상).
12. 볼트가 git 저장소면 `.gitignore`에 `.wiki-config.json`이 있는지 확인한다(머신별 절대 경로이므로 추적 제외한다) — `.example` 파일은 추적 상태로 유지한다.
13. 생성한 항목과 이미 존재해서 유지한 항목을 구분한 sanity-check 목록을 출력한다.

## 재지정·재정합

### `--update-path` (볼트 재지정)
볼트가 이동했거나 머신을 옮긴 경우 사용한다.
1. 사용자에게 새 볼트 절대 경로를 묻는다.
2. `<vault>/.wiki-config.json`의 `vault.path`를 새 경로로 갱신한다.
3. 전역 포인터 `~/.llm-wiki/default-vault`를 새 경로로 갱신한다 — 기존 값이 다른 경로면 워크플로우 Step 4와 동일하게 `old → new`를 보여주고 확인 후 덮어쓴다.
4. 경로 유효성을 확인한다: `wiki/index.md`, `wiki/log.md`, `wiki/hot.md` 존재 여부를 점검하고 결과를 보고한다.

### `--update-qmd` (전체 QMD 재정합)
per-skill refresh(§3-5)는 쓰기마다 증분 갱신하지만, QMD를 껐다 켠 사이 쓰기가 쌓였거나·머신을 옮겼거나·git pull/외부 편집으로 볼트가 스킬 밖에서 바뀌면 일괄 reconcile이 필요하다.
1. **QMD 게이트 판정(§3-5).** CLI 미설치 → 설치 안내 후 중단. 컬렉션 미등록 → 워크플로우 Step 9의 등록(`${QMD_CLI:-qmd} collection add <vault>/<wiki_dir> --name wiki`)부터 수행한다.
2. **§3-5 명령 시퀀스를 컬렉션 전체에 적용한다:**
   - `${QMD_CLI:-qmd} update` — 볼트 전체 해시 스캔(신규·변경·삭제 반영).
   - update가 벡터 필요를 보고하면 `${QMD_CLI:-qmd} embed` (전체 reconcile은 대개 필요하다).
   - `${QMD_CLI:-qmd} ls "$QMD_WIKI_COLLECTION"` — **컬렉션 전체 가시성 검증.** per-skill refresh의 단일 페이지 검증과 달리, 여기선 컬렉션 전체를 확인한다.
3. `log.md`에 기록한다: `[YYYY-MM-DD] QMD-RECONCILE pages_indexed=N embedded=true|false`.
4. §3-5 상태 문자열로 결과를 보고한다. QMD 실패는 볼트를 롤백하지 않고 QMD 상태만 별도 보고한다.

## 기존 파일 보존 정책
`index.md`/`log.md`/`hot.md`는 **존재 여부만** 확인한다. 있으면 내용 불문 유지한다 — 포맷이 낡았거나 frontmatter가 없어도 손대지 않는다. 포맷 노후의 진단·보강은 `wiki-lint --fix`의 책임이다(detect-and-repair) — setup이 내용까지 검사하면 책임이 중복된다. "백업 후 재생성"은 채택하지 않는다: 사용자 데이터를 LLM이 재생성하는 건 위험하고, 백업은 git의 일이다.

install.sh는 플랫폼에 스킬/스크립트/훅을 배포한다; wiki-setup은 *볼트*만 설정한다.

## 품질 체크
```
□ vault 서명 확립: wiki/index.md + wiki/log.md 둘 다 존재 (resolve-vault.sh의 E_NOT_A_VAULT 판정 기준)
□ .wiki-config.json에 절대경로 vault.path 기록됨
□ ~/.llm-wiki/default-vault가 이 볼트를 가리킴 (다른 볼트를 가리키던 경우 사용자 확인 거쳐 갱신)
□ 고정 디렉터리(concepts/knowledge/entities/projects/meetings/archived) 존재, summaries 하위는 생성 안 함
□ index.md는 최상위 카테고리 섹션만 시드됨 (서브섹션 하드코딩 없음)
□ hot.md 존재 — 없었다면 위 Step 8 템플릿 또는 log.md 기반 복구로 생성됨
□ .manifest.json, .wiki-config.example.json 존재
□ git 저장소면 .gitignore에 .wiki-config.json 등록됨 (.example은 추적 유지)
□ QMD 상태(등록/미설치) 최종 보고에 포함
□ sanity-check 출력: 신규 생성 vs 기존 유지 구분
```
