# 스킬 문서 재작성 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `skills/`의 12개 SKILL.md를 superpowers 원리(음성·장치·"Match the Form to the Failure")로 재작성하고, 링크·index 표기를 정본화하며, 스킬이 인용하는 스펙/AGENTS의 표기 오류·갭을 정정한다.

**Architecture:** 원칙-우선 접근. 먼저 (1) 작성 가이드로 공통 규약을 못박고 (2) 스킬이 인용할 정본(스펙/AGENTS)을 정정한 뒤 (3) 우선순위 순으로 12개 스킬을 재작성한다. 스킬의 **동작·의무는 바꾸지 않는다** — 형식·표기·가독성만 정합한다(내용의 정본은 `docs/specs/spec.md` §4의 per-skill 섹션).

**Tech Stack:** Markdown(SKILL.md), YAML frontmatter, bash 검증 스크립트(`scripts/*.sh`, `tests/run.sh`), mermaid 흐름도.

**설계 정본:** `docs/specs/2026-07-11-skill-doc-rewrite-design.md`

## Global Constraints

- **동작 불변:** 스킬의 워크플로우 로직·의무는 spec §4 그대로 유지. 이번 작업은 형식·표기만.
- **링크 표기:** 본문·인용·Related·Conflicts·frontmatter(`relationships.target`·`superseded_by`)는 전부 `[[slug]]` **파일명만**. 유일한 예외 = `wiki-project-record`의 `decisions.md` 변경기록 `[[changes/archive/YYYY-MM-DD-{slug}]]`.
- **index.md 표기:** `## 카테고리` 섹션 아래 `| [표시명](상대경로.md) | 설명 |` 마크다운-표.
- **description 규칙:** `…할 때 사용 — <트리거·슬래시커맨드>` 형식. 트리거·증상만, **워크플로우 요약 금지**. 한국어 기준. frontmatter 총 ≤1024자, `name`은 소문자·숫자·하이픈만.
- **헤딩 언어:** 한국어 유지.
- **공통 절차 중복 서술 금지:** Config Gate(§3-2)·Content Trust Boundary·쓰기 종료 시퀀스(§3-6)·QMD refresh(§3-5)는 스펙/AGENTS 단일 출처를 **인용만**.
- **음성/톤:** 2인칭 명령형, 짧고 단정. 위험 규칙엔 `MUST`/`NEVER` + ✅/❌.
- **커밋 트레일러:** 모든 커밋 끝에 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## Shared Verification Recipe (SVR)

각 스킬 재작성 태스크가 호출하는 공통 검증. `$F`는 대상 SKILL.md 경로.

```bash
F=skills/<skill>/SKILL.md

# 1) folder-qualified 링크 없음 (예외 스킬은 아래 태스크에서 별도 명시)
#    카테고리/wiki 접두 링크가 잡히면 위반.
grep -nE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings|changes)/' "$F" \
  && echo "VIOLATION: folder-qualified link" || echo "OK: links filename-only"

# 2) description 형식 — '할 때 사용' 트리거 존재
sed -n '3p' "$F" | grep -q '할 때 사용' && echo "OK: description trigger" || echo "CHECK: description"

# 3) frontmatter 총 길이 ≤1024자
head -4 "$F" | wc -c | awk '{ if ($1<=1024) print "OK: frontmatter size "$1; else print "VIOLATION: frontmatter "$1" >1024" }'

# 4) 절차형 스킬 필수 섹션 존재 (read-only/router/table 유형은 태스크별 조정)
for h in '## 개요' '## 언제 사용' '## 워크플로우'; do
  grep -qF "$h" "$F" && echo "OK: $h" || echo "MISSING: $h"
done
```

**콘텐츠 충실도 체크(수동):** 재작성된 스킬의 트리거·입력·워크플로우 단계·쓰기 타깃·표기·불변식이 spec §4 해당 per-skill 섹션의 의무와 1:1 대응하는지 항목별 확인. 누락·추가·변경 없음.

**회귀 체크:** 스펙/스크립트/훅을 건드린 태스크 후 `bash tests/run.sh` 전체 통과 확인.

---

## Task 1: 작성 가이드 신설

**Files:**
- Create: `docs/skill-authoring-guide.md`

**Interfaces:**
- Produces: 이후 모든 스킬 태스크가 인용하는 공통 규약 단일 출처(§2·§3 of design).

- [ ] **Step 1: 가이드 작성**

`docs/skill-authoring-guide.md`에 아래 내용을 담는다 (설계 문서 §2·§3을 운영 규칙으로):

```markdown
# 스킬 작성 가이드

llm-wiki-harness 스킬(SKILL.md) 작성·수정 시 단일 기준. 신규·수정 모두 적용.

## 강제 4가지 (전 스킬)
1. description = `…할 때 사용 — <트리거·슬래시커맨드>`. 트리거·증상만, 워크플로우 요약 금지. 한국어.
2. 음성/톤 = 2인칭 명령형, 짧고 단정. 위험 규칙엔 MUST/NEVER + ✅/❌.
3. 공통 절차(Config Gate·Content Trust Boundary·쓰기 종료 시퀀스·QMD refresh)는 스펙/AGENTS 단일 출처 인용만 — 재서술 금지.
4. 링크 표기: 본문·frontmatter 모두 [[slug]] 파일명. index.md는 `| [표시명](상대경로.md) | 설명 |`.

## 기본 스켈레톤 (절차형)
# 스킬 이름 / ## 개요 / ## 언제 사용 / ## 워크플로우(번호 단계, 한 줄 압축 금지) / ## 품질 체크

## 유형별 변형 (Match the Form to the Failure)
- 라우터형(using-llm-wiki): 규칙 + 라우팅 표
- 테이블형(wiki-lint): 체크 표 중심
- read-only형(wiki-query·wiki-status): "쓰지 않는다" 경계 강조 + 검색 사다리
- 위험 지점: 해당 지점에만 장치(금지 박스/명시 게이트/강조 규칙/불변성 규칙)

## 장치 사용 규칙
- mermaid 흐름도: 비자명 분기에만. 선형 절차엔 번호 목록.
- Red Flags / 합리화 표: 규율 위반이 실제 우려되는 곳에만.
```

- [ ] **Step 2: 커밋**

```bash
cd /Users/juno/IdeaProjects/llm-wiki-harness
git add docs/skill-authoring-guide.md
git commit -m "docs: 스킬 작성 가이드 신설 (재작성 공통 규약 단일 출처)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 스펙 §3-3 표기 정본 + AGENTS 정합

**Files:**
- Modify: `docs/specs/spec.md` (§3-3 페이지 포맷 영역, 라인 279·317·786·1314·1521 및 §3-3 내 신규 규칙 삽입)
- Modify: `AGENTS.md:19` (링크 규칙)

**Interfaces:**
- Produces: 링크 표기 정본 규칙 + index.md 엔트리 표기 정의 + 중첩링크 주의. 이후 모든 스킬이 이 규칙을 인용.

- [ ] **Step 1: 표기 정본 규칙을 §3-3에 명문화**

`docs/specs/spec.md` §3-3(페이지 포맷) 안, `[[wiki-link]]` 설명(line 327 부근) 뒤에 규칙 블록 삽입:

```markdown
#### 링크·index 표기 규칙 (정본)

- **본문 링크 / 인용 / Related pages / Conflicts sources:** `[[slug]]` 파일명만. (Obsidian 그래프 소비)
- **frontmatter `relationships.target` / `superseded_by`:** `[[slug]]` 파일명만. slug 전역 유일(§110)하고 build-link-graph.sh가 본문+frontmatter를 한 그래프로 통합(§4-6)하므로 경로 불필요.
- **index.md 엔트리:** `## 카테고리` 섹션 아래 `| [표시명](wiki-루트-상대경로.md) | 한 줄 설명 |` 마크다운-표.
- **예외:** decisions.md의 `변경 기록:`만 `[[changes/archive/YYYY-MM-DD-{slug}]]` folder-qualified(§4-9-2 링크 안정성 의무).
```

- [ ] **Step 2: folder-qualified 오류 예시 정정**

아래 라인의 링크를 파일명 형태로 수정 (표시는 예시이므로 대표 slug로):
- `spec.md:279` `target: "[[concepts/related]]"` → `target: "[[related-concept]]"`
- `spec.md:317` `superseded_by: "[[wiki/path/replacement-page]]"` → `superseded_by: "[[replacement-page]]"`
- `spec.md:786` `[[summaries/meetings/{file}]]` → `[[{meeting-slug}]]`
- `spec.md:1314` `[[summaries/papers/old]]` → `[[old-paper-slug]]`
- `spec.md:1521` `target: "[[summaries/articles/topic/source-a]]"` → `target: "[[source-a]]"`

(단, `[[changes/archive/...]]` 형태 — line 1866·1995 등 — 은 예외이므로 **건드리지 않는다**.)

- [ ] **Step 3: 중첩 frontmatter 링크 주의 확인**

`spec.md:337-338`이 이미 "중첩 frontmatter `[[wikilink]]`는 Obsidian 그래프 미인식, 소비자는 머신"을 명시함 — Step 1 규칙과 정합하는지 확인만. 불일치 없으면 수정 불필요.

- [ ] **Step 4: AGENTS.md 링크 규칙 정합**

`AGENTS.md:19`의 `링크는 [[wiki-link]]`를 아래로 교체:

```
- 내부 링크는 [[slug]] (파일명만, 폴더 경로 없음). index.md는 마크다운-표 `| [표시명](상대경로.md) | 설명 |`.
```

- [ ] **Step 5: 검증 — 스펙에 잔존 folder-qualified 링크 없음(예외 제외)**

Run:
```bash
cd /Users/juno/IdeaProjects/llm-wiki-harness
grep -nE '\[\[(wiki|summaries|concepts|entities|projects|meetings)/' docs/specs/spec.md
```
Expected: 출력 없음 (모두 정정됨). `[[changes/...]]`·`[[knowledge/...]]` 형태는 위 패턴에 안 걸리며 예외로 허용.

- [ ] **Step 6: 회귀 테스트**

Run: `bash tests/run.sh`
Expected: `── 전체 통과 ──`

- [ ] **Step 7: 커밋**

```bash
git add docs/specs/spec.md AGENTS.md
git commit -m "docs: 링크·index 표기 정본화 (본문·frontmatter [[slug]] 통일)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 스펙 §4-3/§4-4 index 서브섹션 규칙 + §4-5 한국어화 + §4-7 status 로그

**Files:**
- Modify: `docs/specs/spec.md` (§4-3 ingest-url, §4-4 wiki-capture, §4-5 wiki-query, §4-7 wiki-status)

**Interfaces:**
- Consumes: Task 2의 index 표기 정의.
- Produces: 스킬 재작성 태스크(Task 6·7·11·15)가 반영할 정정된 스펙 의무.

- [ ] **Step 1: index 서브섹션 "없으면 생성" 규칙 명시**

`spec.md:924`(ingest-url Step 7) 및 `:1008`(wiki-capture Step 3 index)에 규칙 추가:
```
wiki/index.md에 해당 서브섹션(summaries/web · summaries/sessions)이 없으면 새로 만들고 추가한다.
(wiki-setup은 최상위 카테고리 섹션만 시드하며 서브섹션을 하드코딩하지 않는다.)
```

- [ ] **Step 2: §4-5 wiki-query 답변 블록 한국어화**

`spec.md:1105-1108`의 영어 라벨을 교체:
```
> 위키 기반:
> [답변 + [[slug]] 인용]
> 참고 페이지: [[page-a]], [[page-b]]
> 공백: [wiki가 커버하지 못하는 부분]
```
그리고 `:1110`의 "인용 포맷: [[wikilink]] 기본" 문구는 유지(정본).

- [ ] **Step 3: §4-7 wiki-status 로그 라인 추가**

`spec.md` §4-7 워크플로우 마지막(현재 Step 5 리포트 뒤)에 log append 단계를 추가:
```
Step 6: wiki/log.md 상태 조회 기록 (read-only 예외 — 관찰 기록, §3-6)
  [YYYY-MM-DD] STATUS unprocessed=N recent_ingest="{경로}" token_estimate=K
  ※ log append 실패해도 리포트는 이미 전달됨 → 스킬 실패 아님 (self-healing)
```
그리고 §3-5 스킬별 적용 표(line 540)의 wiki-status 행 주석에 "log append만 예외" 명시(§3-6 line 565와 정합).

- [ ] **Step 4: 검증**

Run:
```bash
cd /Users/juno/IdeaProjects/llm-wiki-harness
grep -n 'Based on the wiki' docs/specs/spec.md   # 기대: 출력 없음(한국어화됨)
grep -n 'STATUS unprocessed' docs/specs/spec.md  # 기대: 1건(추가됨)
bash tests/run.sh                                 # 기대: 전체 통과
```

- [ ] **Step 5: 커밋**

```bash
git add docs/specs/spec.md
git commit -m "docs: 스펙 정합 3건 (index 서브섹션 규칙·query 한국어화·status 로그)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: wiki-project-design 재작성 🔴

**Files:**
- Modify: `skills/wiki-project-design/SKILL.md`
- Reference: `skills/wiki-project-design/references/mermaid-conventions.md` (기존 유지)

**콘텐츠 정본:** spec §4-9-2 (`docs/specs/spec.md:1843-1960`) + §4-9 공통(1717-1792).

- [ ] **Step 1: 재작성**

기본 스켈레톤 + 위험지점 장치로 재작성:
- **description:** `프로젝트 design 문서를 만들거나 발전시킬 때 사용 — "아키텍처 설계", "도메인 모델", "/wiki-project-design"`
- **## 개요** 1~2줄: architecture/domain/conventions를 change-proposal 경유로 진화시키는 스킬.
- **## 언제 사용:** 트리거 + 경계(init 문서는 R, decisions는 record로 위임).
- **## 워크플로우:** 현재 한 줄 압축(구 line 23)을 **번호 단계 0~8로 분해**(spec 1932-1949 대응). surface↔semantic 분기와 change 라이프사이클은 **mermaid 흐름도 1개**로.
- **## Change-proposal 규약:** 제안 템플릿(class ② frontmatter + `## 동기`/`## Delta`/`## 근거`/`## 영향`)을 코드펜스로.
- **## 품질 체크:** spec 1952-1960 항목.
- **표기:** `[[changes/archive/...]]`는 예외로 folder-qualified 유지(decisions.md 변경기록 링크). 그 외 링크는 `[[slug]]`.

- [ ] **Step 2: 검증 (SVR + 예외)**

Run SVR with `F=skills/wiki-project-design/SKILL.md`. **단, folder-qualified 체크는 `[[changes/archive/` 만 허용:**
```bash
F=skills/wiki-project-design/SKILL.md
grep -nE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' "$F" && echo "VIOLATION" || echo "OK"
grep -nE '\[\[changes/(archive/)?' "$F" && echo "NOTE: change-link 예외(정상)"
```
Expected: 첫 grep 출력 없음(OK), 콘텐츠 충실도 수동 체크 통과.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-project-design/SKILL.md
git commit -m "docs(skill): wiki-project-design 재작성 (워크플로우 번호화·mermaid·표기 정합)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: wiki-project-record 재작성 🔴

**Files:**
- Modify: `skills/wiki-project-record/SKILL.md`

**콘텐츠 정본:** spec §4-9-3 (`spec.md:1964-2054`) + §4-9 공통.

- [ ] **Step 1: 재작성**
- **description:** `프로젝트 이벤트를 기록할 때 사용 — "결정 기록", "트러블슈팅", "미팅 요약", "/wiki-project-record"`
- **## 개요:** decision/troubleshooting/meeting/backlog 라우팅 싱크.
- **## 라우팅:** 4-way 라우팅을 **mermaid 흐름도**로(design-affecting decision → design 위임 분기 포함).
- **## 워크플로우:** 현재 한 줄 압축(구 line 61)을 번호 단계 0~6으로 분해.
- **## 불변성 규칙:** 파일별 불변성 차등(decisions·meetings 완전 불변 / troubleshooting open→resolved / backlog living)을 **표 + 강조 규칙**으로. append-only 위반 금지 박스.
- **## 파일 포맷:** decisions.md 항목·backlog.md·troubleshooting 케이스 템플릿을 코드펜스로.
- **표기 예외:** decisions.md `변경 기록:` → `[[changes/archive/YYYY-MM-DD-{slug}]]` folder-qualified 유지.
- **## 품질 체크:** spec 2046-2054.

- [ ] **Step 2: 검증**

동일 예외 적용 grep(Task 4 Step 2 패턴) + 콘텐츠 충실도 수동 체크. mermaid 블록 문법 확인(` ```mermaid `).

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-project-record/SKILL.md
git commit -m "docs(skill): wiki-project-record 재작성 (라우팅 mermaid·불변성 규칙·워크플로우 번호화)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: ingest-url 재작성 🔴

**Files:**
- Modify: `skills/ingest-url/SKILL.md`

**콘텐츠 정본:** spec §4-3 (`spec.md:854-940`). Task 3 Step 1(index 서브섹션 규칙) 반영.

- [ ] **Step 1: 재작성**
- **description:** `URL을 wiki에 저장할 때 사용 — "이 링크 정리해줘", "/ingest-url <url> [--source-type ...]"`
- **## 개요 / ## 언제 사용.**
- **## Content Trust Boundary:** 웹=미신뢰, 네트워크는 주어진 URL로만(SSRF/injection 방어)을 **명시 게이트 박스**로(현재 산문 매몰 → 승격).
- **## 워크플로우:** 번호 단계 0~10(spec 864-939). fetch 실패→stub 분기 명시.
- **## 품질 체크 신설:** ≥2 링크, web/≠articles/ 불변식, source_url dedupe, 저작권(요약 not copy).
- **index:** Step 7에서 `summaries/web` 섹션 없으면 생성(Task 3).
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run SVR with `F=skills/ingest-url/SKILL.md`. `## 품질 체크` 존재 확인:
```bash
grep -qF '## 품질 체크' skills/ingest-url/SKILL.md && echo OK || echo MISSING
```
+ 콘텐츠 충실도 수동 체크.

- [ ] **Step 3: 커밋**

```bash
git add skills/ingest-url/SKILL.md
git commit -m "docs(skill): ingest-url 재작성 (Trust Boundary 게이트·품질체크 신설·index 정합)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: wiki-capture 재작성 🟡

**Files:**
- Modify: `skills/wiki-capture/SKILL.md`

**콘텐츠 정본:** spec §4-4 (`spec.md:944-1027`). Task 3 Step 1 반영.

- [ ] **Step 1: 재작성**
- **description:** `현재 대화 지식을 wiki에 보존할 때 사용 — "이거 기록해줘", "save this to the wiki", "/wiki-capture"`
- **## 개요:** 항상 summaries/sessions에 먼저 저장, 승격은 명시 요청 시만.
- **## 비밀 마스킹 규칙:** API키·토큰·비밀번호 → `[REDACTED]` 항상 / 이메일·이름·경로는 마스킹 안 함을 **강조 규칙 박스**로(현재 산문 매몰 → 승격, spec 978-983).
- **## 워크플로우:** 번호 단계 0~6.
- **## 품질 체크 신설:** frontmatter 고정값(base_confidence 0.42·status unverified), provenance 마커, index sessions 섹션 없으면 생성.
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run SVR with `F=skills/wiki-capture/SKILL.md` + `grep -qF '[REDACTED]'` 마스킹 규칙 존재 확인 + 콘텐츠 충실도.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-capture/SKILL.md
git commit -m "docs(skill): wiki-capture 재작성 (마스킹 규칙 승격·품질체크·index 정합)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: wiki-ingest 재작성 🟡

**Files:**
- Modify: `skills/wiki-ingest/SKILL.md`

**콘텐츠 정본:** spec §4-2 (`spec.md:674-851`).

- [ ] **Step 1: 재작성**
- **description:** 기존 유지·정합(`raw/ 로컬 파일을 ingest할 때 사용 — "ingest this", "/ingest <path>", "raw 처리해줘"`).
- **## Content Trust Boundary + 경로 가드:** Step 1.5 hard guard(`realpath` + `{VAULT}/{RAW}/` prefix 체크)를 **명시 게이트 박스**로 가독화(현재 산문 blob, spec 724-726).
- **## 워크플로우:** 번호 단계 0~10 유지·가독화. concept 생성 게이트(3조건, >5개 승인) 명시.
- **## 품질 체크:** 1:1 미러, ≥2 링크, 모든 주장 출처, 충돌→§3-3.
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run SVR with `F=skills/wiki-ingest/SKILL.md` + 콘텐츠 충실도.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-ingest/SKILL.md
git commit -m "docs(skill): wiki-ingest 재작성 (경로가드 게이트화·가독화)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: wiki-setup 재작성 🟡

**Files:**
- Modify: `skills/wiki-setup/SKILL.md`

**콘텐츠 정본:** spec §4-1 (`spec.md:571-670`).

- [ ] **Step 1: 재작성**
- **description:** 트리거 형식으로 정합(`새 볼트를 초기화하거나 깨진 설정을 복구할 때 사용 — "wiki 초기화", "볼트 설정", "/wiki-setup [--repair|--update-path|--update-qmd]"`). 현재 트리거 없는 3문장 → 트리거 형식.
- **## 개요:** 다른 스킬보다 먼저 실행, 유일하게 Config Gate 비적용(스스로 config 생성).
- **## 모드:** `--vault/--yes/--repair/--update-path/--update-qmd`를 표로.
- **## 워크플로우:** 13단계 번호 유지·가독화. index 초기 템플릿은 **최상위 카테고리 섹션만** 시드(Task 3 정합).
- **## 재지정·재정합.**
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run SVR (단 이 스킬은 Config Gate 인용 없음이 정상 — SVR 섹션 체크는 유형 조정). 콘텐츠 충실도.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-setup/SKILL.md
git commit -m "docs(skill): wiki-setup 재작성 (description 트리거화·모드 표·index 시드 정합)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: wiki-knowledge 재작성 🟡

**Files:**
- Modify: `skills/wiki-knowledge/SKILL.md`

**콘텐츠 정본:** spec §4-8 (`spec.md:1494-1681`).

- [ ] **Step 1: 재작성**
- **description:** `여러 요약·개념·세션을 종합해 knowledge 페이지를 만들거나 갱신할 때 사용 — "종합해줘", "정리해서 knowledge로", "/wiki-knowledge"`
- **## 개요:** 종합(synthesis) — ingest와 구분. **사용자 주도만, 자동생성 금지**를 강조.
- **## 워크플로우:** 번호 단계 0~8(new/update 분기). synthesis-plan 미리보기(Step 2.5).
- **## 페이지 템플릿:** 8섹션 코드펜스.
- **## 중첩링크 주의(신설):** `relationships:` 중첩 frontmatter 링크는 Obsidian 그래프에 안 잡힘 — 사람용 연결은 본문 `[[slug]]`·Related pages가 담당(spec 337-338, Task 2 정합).
- **## 분할 트리거 / ## 품질 체크.**
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run SVR + `grep -qF '그래프' skills/wiki-knowledge/SKILL.md`(중첩링크 주의 존재) + 콘텐츠 충실도.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-knowledge/SKILL.md
git commit -m "docs(skill): wiki-knowledge 재작성 (중첩링크 주의 추가·자동생성 금지 강조)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: wiki-query 재작성 🟡

**Files:**
- Modify: `skills/wiki-query/SKILL.md`

**콘텐츠 정본:** spec §4-5 (`spec.md:1031-1136`). Task 3 Step 2(한국어 라벨) 반영.

- [ ] **Step 1: 재작성 (read-only형)**
- **description:** `wiki에 저장된 지식을 질문·조회할 때 사용 — "wiki에서 찾아줘", "~에 대해 뭐 있지?", "/wiki-query"`
- **## 개요 / ## read-only 경계:** log append 외 아무것도 안 씀. QMD는 발견용, 인용은 파일 본문 검증.
- **## 검색 사다리:** Step 0~7 번호 유지·가독화(hot→index→QMD→section→full).
- **## 답변 포맷:** **한국어 라벨**(`위키 기반:` / `참고 페이지:` / `공백:`, Task 3). 인용 `[[slug]]`, stale/proposed 표시.
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run SVR (read-only형: `## 품질 체크` 대신 검색 사다리 — 섹션 체크 조정). 한국어 라벨 확인:
```bash
grep -qF '참고 페이지' skills/wiki-query/SKILL.md && echo OK || echo MISSING
grep -q 'Based on the wiki' skills/wiki-query/SKILL.md && echo "VIOLATION: 영어 잔존" || echo OK
```
+ 콘텐츠 충실도.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-query/SKILL.md
git commit -m "docs(skill): wiki-query 재작성 (검색 사다리 가독화·답변 라벨 한국어화)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: wiki-project-init 재작성 ℹ️

**Files:**
- Modify: `skills/wiki-project-init/SKILL.md`

**콘텐츠 정본:** spec §4-9-1 (`spec.md:1796-1839`) + §4-9 공통.

- [ ] **Step 1: 재작성**
- **description:** `프로젝트를 시작·(재)정의할 때 사용 — "프로젝트 시작", "새 프로젝트 정리", "/wiki-project-init"`(트리거만, 산출물 서술 제거).
- **## 개요 / ## 인터뷰 패턴:** `[NEEDS CLARIFICATION]` 마커 ≤5, 잔존 시 status unverified.
- **## 워크플로우:** 번호 단계 0~7. overview/context/goals 생성(goals는 논의 시만, **비목표 섹션 필수**).
- **## 경계 / ## 품질 체크.**
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run SVR with `F=skills/wiki-project-init/SKILL.md` + 콘텐츠 충실도(비목표 필수 규칙 포함).

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-project-init/SKILL.md
git commit -m "docs(skill): wiki-project-init 재작성 (description 트리거화·인터뷰 패턴 정리)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: using-llm-wiki 재작성 (라우터형) ℹ️

**Files:**
- Modify: `skills/using-llm-wiki/SKILL.md`

**콘텐츠 정본:** spec §5-1 + 배포 설계 §5·§6 + `AGENTS.md`(정정된 Task 2 반영).

**멀티플랫폼 소비 구조 (중요):** 이 스킬은 Claude 전용이 아니다 — **Claude·Codex·Cursor 셋 다 SessionStart 훅으로 `using-llm-wiki/SKILL.md`를 주입**받는다(배포 설계 §5). Antigravity만 훅이 없어 대신 **`AGENTS.md`**(글로벌 `~/.gemini/config/AGENTS.md` symlink)를 상시 로드한다. 즉 `using-llm-wiki`(스킬)와 `AGENTS.md`(축약판)는 **같은 부트스트랩 내용의 두 표현**이므로 **반드시 동기화**돼야 한다. 어긋나면 Antigravity만 다른 규칙을 로드하게 된다.

- [ ] **Step 1: 재작성 (라우터형 — 스켈레톤 대신 규칙+라우팅 표)**
- **description:** `LLM Wiki 볼트에서 작업할 때 사용 — 세션 시작 시 규칙·라우팅 로드`(부트스트랩).
- **## Config Gate (Step 0):** `resolve-vault.sh` 인용.
- **## 불변 규칙:** raw 불변 / 쓰기 종료 시퀀스 / 출처 / 페이지=한국어 / 파일명 소문자-하이픈 / **링크 `[[slug]]`(Task 2 정합)**.
- **## QMD refresh:** §3-5 요지 인용.
- **## 라우팅 표:** 의도→스킬 매핑(AGENTS.md와 동일).
- **표기:** `[[slug]]`.
- **동기화 필수:** 위 4개 부트스트랩 내용(Config Gate·불변 규칙·쓰기 종료 시퀀스·라우팅)이 `AGENTS.md`(Task 2에서 정정됨)와 의미상 일치해야 한다. AGENTS.md는 Codex 32 KiB 예산상 축약판이므로 **표현은 짧아도 규칙 자체는 동일**해야 한다.

- [ ] **Step 2: 검증 — 표기 + using-llm-wiki ↔ AGENTS.md 동기**

Run:
```bash
F=skills/using-llm-wiki/SKILL.md
grep -nE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' "$F" && echo VIOLATION || echo OK
grep -qF 'slug' "$F" && echo "OK: 링크 규칙 정합"

# 부트스트랩 4요소가 양쪽에 모두 존재하는지 기계 체크
for kw in 'resolve-vault' 'raw' 'index' 'log' 'hot' 'QMD'; do
  s=$(grep -qF "$kw" "$F" && echo Y || echo -); a=$(grep -qF "$kw" AGENTS.md && echo Y || echo -)
  echo "$kw  skill=$s  agents=$a"
done
```
Expected: 첫 grep 출력 없음(OK). 각 키워드가 `skill`·`agents` 양쪽 모두 `Y`.

**동기 대조(수동, 필수):** using-llm-wiki와 AGENTS.md를 나란히 놓고 4개 부트스트랩 내용을 항목별 대조 —
1. **Config Gate** — `resolve-vault.sh` 호출·exit 분기 규칙 동일한가
2. **불변 규칙** — raw 불변 / 쓰기 종료 시퀀스(page→index→log→hot→QMD) / 출처 / 페이지=한국어 / 링크 `[[slug]]` 동일한가
3. **QMD refresh** — §3-5 요지 동일한가
4. **라우팅 표** — 11개 스킬 의도→스킬 매핑이 1:1 일치하는가

불일치 발견 시: **정본 계층은 `docs/specs/spec.md` → `skills/using-llm-wiki/`(+`references/`) → `AGENTS.md` → 개별 SKILL.md** 순이다. 따라서 skill 허브와 AGENTS.md가 어긋나면 **AGENTS.md 쪽을 허브에 맞춘다** — AGENTS.md는 비-Claude 도구용 축약 미러이지 정본이 아니다(현행 `AGENTS.md` 머리말도 "공통 절차의 본문은 `skills/using-llm-wiki/`"라고 선언한다). 둘 다 spec과 어긋나면 spec을 기준으로 양쪽을 고친다. (표현 길이는 달라도 규칙 내용은 같아야 함.)

- [ ] **Step 3: 커밋**

```bash
git add skills/using-llm-wiki/SKILL.md
git commit -m "docs(skill): using-llm-wiki 재작성 (라우터형·AGENTS 링크 규칙 정합)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: wiki-lint 재작성 (테이블형) ℹ️

**Files:**
- Modify: `skills/wiki-lint/SKILL.md`

**콘텐츠 정본:** spec §4-6 (`spec.md:1140-1358`).

- [ ] **Step 1: 재작성 (테이블형 유지, 밀집 셀 분해)**
- **description:** 기존 유지·정합(`wiki 문제를 감사·린트할 때 사용 — "lint", "audit", "점검해줘", "/wiki-lint [--fix [--yes]]"`).
- **## 17개 체크 표:** 유지. 단 **밀집 셀 분해** — check 13 provenance_drift의 4임계값(Δ≥0.20, ambiguous>0.15, inferred>0.40 등)을 셀 안 나열이 아니라 하위 불릿으로.
- **## --fix 모델:** dry-run 기본 / 배치 확인 / **불가역(raw 삭제)은 항상 개별 확인**을 **mermaid 분기** 또는 표로.
- **## 마무리:** `--fix` 쓰기 발생 시만 QMD refresh.
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run:
```bash
F=skills/wiki-lint/SKILL.md
grep -nE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' "$F" && echo VIOLATION || echo OK
grep -c '^|' "$F"   # 표 행 존재 확인
```
+ 17체크 전부 존재 확인(수동) + 콘텐츠 충실도.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-lint/SKILL.md
git commit -m "docs(skill): wiki-lint 재작성 (밀집 셀 분해·--fix 분기 가독화)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: wiki-status 재작성 (read-only형) ℹ️

**Files:**
- Modify: `skills/wiki-status/SKILL.md`

**콘텐츠 정본:** spec §4-7 (`spec.md:1360-1490`, Task 3 Step 3 로그 라인 반영).

- [ ] **Step 1: 재작성**
- **description:** `ingest 대기 raw·처리 현황·볼트 상태를 알고 싶을 때 사용 — "남은 거 뭐야?", "볼트 상태", "/wiki-status"`
- **## 개요 / ## wiki-lint와의 경계:** status="무엇이 남았나", lint="무엇이 깨졌나". 겹치는 탐지도 **보고만**.
- **## 워크플로우:** 번호 단계 0~6. **Step 6 로그 라인 추가**(Task 3 Step 3: `[YYYY-MM-DD] STATUS …`).
- **표기:** `[[slug]]`.

- [ ] **Step 2: 검증**

Run:
```bash
F=skills/wiki-status/SKILL.md
grep -nE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' "$F" && echo VIOLATION || echo OK
grep -qF 'STATUS' "$F" && echo "OK: 로그 라인" || echo MISSING
```
+ 콘텐츠 충실도.

- [ ] **Step 3: 커밋**

```bash
git add skills/wiki-status/SKILL.md
git commit -m "docs(skill): wiki-status 재작성 (경계 명료화·STATUS 로그 라인)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: 볼트 전체 정합 스윕 (최종 검증)

**Files:**
- Modify: (필요 시 잔여 수정만)

- [ ] **Step 1: 전 스킬 folder-qualified 링크 스윕**

Run:
```bash
cd /Users/juno/IdeaProjects/llm-wiki-harness
grep -rnE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' skills/
```
Expected: 출력 없음. (`[[changes/archive/...]]`는 위 패턴에 안 걸림 = 예외 허용.)

- [ ] **Step 2: 전 스킬 description 형식 스윕**

Run:
```bash
for f in skills/*/SKILL.md; do
  sed -n '3p' "$f" | grep -q '할 때 사용' || echo "CHECK description: $f"
done
```
Expected: 출력 없음.

- [ ] **Step 3: index 표기 예시 일관성 확인**

Run:
```bash
grep -rn '\[\[.*\]\].*—.*index\|index.*\[\[' skills/ | head
```
index 관련 서술이 마크다운-표 형식을 가리키는지 수동 확인(위키링크 목록 잔재 없음).

- [ ] **Step 4: 전체 회귀 테스트**

Run: `bash tests/run.sh`
Expected: `── 전체 통과 ──`

- [ ] **Step 5: spec §4 per-skill 의무 대조 최종 체크(수동)**

12개 스킬 각각을 spec §4 해당 섹션과 대조 — 트리거·워크플로우 단계·쓰기 타깃·불변식 누락/변경 없음 확인. 갭 발견 시 해당 스킬 태스크로 복귀 수정.

- [ ] **Step 6: 최종 커밋 (잔여 수정 있을 때만)**

```bash
git add -A
git commit -m "docs(skill): 볼트 전체 표기·정합 스윕 마무리

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review 결과

- **Spec coverage:** 설계 §4(스펙 정합 6건) → Task 2·3. 설계 §5(12 스킬) → Task 4~15. 설계 §3-E(작성 가이드) → Task 1. 최종 검증 → Task 16. 갭 없음.
- **표기 예외 일관성:** `[[changes/archive/...]]` 예외는 Task 4·5의 grep에서 명시 제외, Task 16 전역 스윕 패턴도 이를 안 잡음 — 일관.
- **의존성:** Task 1(가이드)·2·3(정본) → 그 뒤 스킬 태스크. Task 3의 스펙 정정을 Task 6·7(index 서브섹션)·11(query 라벨)·15(status 로그)가 소비 — 순서 정합.
- **동작 불변 원칙:** 모든 스킬 태스크가 "콘텐츠 정본 = spec §4" 명시, 내용 추가·삭제 없음.
