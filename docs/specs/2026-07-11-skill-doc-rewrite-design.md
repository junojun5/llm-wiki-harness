# 스킬 문서 재작성 — superpowers 정합 설계

**작성일:** 2026-07-11
**대상:** `llm-wiki-harness/skills/` 12개 SKILL.md
**정본 스펙:** `docs/specs/spec.md` (Harness Engineering Spec)

---

## 1. 배경 · 문제

`skills/`의 12개 SKILL.md는 독립 작성된 노트들이 습관만 수렴한 상태로, 세 가지 문제를 안고 있다.

1. **구조 불일치** — 공유 템플릿이 없다. `## 워크플로우`는 9개만, `## 품질 체크`는 5개만 존재. 같은 개념(Config Gate, Content Trust Boundary)이 스킬마다 다르게 서술된다.
2. **가독성** — 워크플로우가 한 줄에 압축된 벽 텍스트(`wiki-project-design`, `wiki-project-record`가 최악). 중요한 보안 규칙(경로 가드, 비밀 마스킹)이 산문에 파묻힌다.
3. **표기 오류** — wiki-link·index.md 표기가 스펙·스킬·실측 볼트 3자 간 드리프트. 특히 index.md 엔트리 표기는 스펙에 **정의된 적조차 없다**.

이 재작성은 superpowers 스킬의 일관성 원리를 이식해 세 문제를 동시에 닫는다.

### 1-1. superpowers에서 배운 것 (핵심)

superpowers의 메타 스킬 `writing-skills`는 고정 템플릿을 제시하지만, **실제 스킬들은 그 골격을 곧이곧대로 따르지 않는다**(brainstorming은 Checklist로 시작, writing-plans는 템플릿 덩어리). superpowers에서 진짜 일관된 것은:

- **음성/톤** — 2인칭 명령형, 짧고 단정, `MUST`/`NEVER`/`STOP`, ✅/❌
- **장치 툴킷** — Iron Law 박스, `Excuse|Reality` 합리화 표, Red Flags, 흐름도, 게이트 태그
- **핵심 원칙 — "Match the Form to the Failure"** (실패 유형에 형식을 맞춰라)

→ 따라서 우리도 **고정 필수 템플릿이 아니라 원칙-우선** 규약으로 간다.

---

## 2. 링크·index 표기 정본 (§표기 규약)

세 소비자(사람/Obsidian 그래프, 머신/wiki-query, GitHub 렌더)를 구분한 단일 규칙.

| 위치 | 소비자 | 표기 | 예시 |
|---|---|---|---|
| 본문 링크 / 인용 / Related pages / Conflicts sources | 사람·Obsidian | `[[slug]]` **파일명만** | `[[claude-code]]` |
| frontmatter `relationships.target` / `superseded_by` | 머신(wiki-query) | `[[slug]]` **파일명만으로 통일** | `[[karpathy-wiki-pattern]]` |
| `index.md` 엔트리 | 사람·GitHub·Obsidian | `\| [표시명](상대경로.md) \| 설명 \|` **마크다운-표** | `\| [Claude Code](knowledge/개발/claude-code.md) \| Anthropic CLI 에이전트 \|` |
| **예외:** `decisions.md`의 `변경 기록:` | 사람·머신 | `[[changes/archive/YYYY-MM-DD-{slug}]]` **folder-qualified 유지** | (spec §1866 링크 안정성 의무) |

**근거**
- **frontmatter 파일명 통일:** `scripts/build-link-graph.sh`가 본문 `[[link]]` + frontmatter `relationships` 타깃을 **한 그래프로 통합**한다(spec §1149). 표기가 갈리면 그래프가 깨진다. slug 전역 유일성이 이미 보장되므로(spec §110, 동음이의 `-2` suffix) 파일명만으로 충분하다.
- **index 마크다운-표:** 실측 볼트가 이미 사용 중이며(스펙엔 정의 없는 갭), Obsidian·GitHub 양쪽에서 클릭·렌더된다. `alwaysUpdateLinks: true`라 이동 시 경로 자동 갱신.
- **예외 1건:** spec §1866이 제안 파일의 최종 archive 경로를 미리 박아 링크 안정성을 확보하도록 명시 → folder-qualified 유지.

**정정 대상 (스펙 오류):** 아래 folder-qualified `[[...]]`는 위 규칙 위반이므로 파일명으로 수정한다.
- `spec.md:279` `[[concepts/related]]`, `:786` `[[summaries/meetings/{file}]]`, `:1314` `[[summaries/papers/old]]`, `:1521` `[[summaries/articles/topic/source-a]]`
- `spec.md:317` `[[wiki/path/replacement-page]]` — 유일하게 `wiki/` prefix까지 붙은 이질적 형태. 명백한 오류.

---

## 3. 스킬 공통 규약 (원칙-우선, 고정 템플릿 아님)

### 3-A. 전(全) 스킬 강제 4가지

1. **description** = `…할 때 사용 — <트리거·슬래시커맨드>`. 트리거·증상만 담고 **워크플로우를 요약하지 않는다**(superpowers writing-skills의 핵심 규칙 — 요약은 에이전트가 절차를 건너뛰는 지름길이 된다). 한국어 기준.
2. **음성/톤** = 2인칭 명령형, 짧고 단정한 문장. 위험 규칙엔 `MUST`/`NEVER` + ✅/❌ 대비.
3. **공통 절차 중복 서술 금지** — Config Gate(§3-2)·Content Trust Boundary·쓰기 종료 시퀀스(§3-6)·QMD refresh(§3-5)는 **스펙/AGENTS 단일 출처를 인용만** 한다. 각 스킬이 재서술하지 않는다.
4. **표기 규약(§2) 참조** — 각 스킬이 링크 표기를 재정의하지 않는다.

### 3-B. 기본 스켈레톤 (절차형 — 9개 대부분)

```
# 스킬 이름
## 개요        — 1~2줄. 무엇을 하는 스킬인가
## 언제 사용    — 트리거 + 언제 쓰지 않는가(경계)
## 워크플로우   — 번호 매긴 단계. 한 줄 압축 금지 (현재 최악 문제)
## 품질 체크    — 종료 전 검증 항목 (쓰기 스킬만)
```

헤딩 언어는 **한국어 유지**(볼트 언어 규약 일치).

### 3-C. 유형별 변형 (Match the Form to the Failure)

- **라우터형** (`using-llm-wiki`) — 스켈레톤 대신 규칙 + 라우팅 표
- **테이블형** (`wiki-lint`) — 17체크 표 중심
- **read-only형** (`wiki-query`·`wiki-status`) — "쓰지 않는다" 경계 강조, 품질체크 대신 검색 사다리
- **위험 지점 스킬** — 그 지점에만 장치 투입:
  - `raw/` 불변 → 금지 규칙 박스
  - Content Trust Boundary (`wiki-ingest`·`ingest-url`·`wiki-capture`) → 명시 게이트
  - 비밀 마스킹 (`wiki-capture`) → 강조 규칙
  - append-only 원장 (`wiki-project-record`의 decisions.md) → 불변성 규칙

### 3-D. 장치 사용 규칙

- **흐름도(mermaid)** — 비자명 분기에만. 예: `wiki-project-record` 라우팅, `wiki-lint --fix` 분기. 선형 절차엔 번호 목록(흐름도 금지).
- **Red Flags / 합리화 표** — 규율 위반이 실제 우려되는 곳에만. 예: raw 쓰기 유혹, 미검증 QMD 결과 회수, knowledge 자동생성 유혹.

### 3-E. 작성 가이드 신설

위 3-A~3-D를 **경량 작성 가이드 1장**(`docs/skill-authoring-guide.md`)으로 harness 레포에 남긴다. 앞으로 스킬 추가·수정 시 단일 기준이 되어 드리프트 재발을 막는다.

---

## 4. 스펙/AGENTS 정합 수정 (교차 절단)

재작성이 의존하는 **정본 자체의 오류·갭**을 타깃 수정한다 (스펙 전면 재작성 아님).

| # | 수정 | 위치 |
|---|---|---|
| 1 | 링크 표기 정본 규칙 명문화 + folder-qualified 오류 예시 수정(§2 정정 대상) | spec §3-3, AGENTS.md:19 |
| 2 | **index.md 엔트리 표기 정의 신설**(현재 갭) — 마크다운-표 형식 | spec §3-3 신설, lint check 6, wiki-setup 초기 템플릿 |
| 3 | index 서브섹션 정합 — setup은 **최상위 카테고리 섹션만** 시드하고, `ingest-url`·`wiki-capture`는 append 시 **자기 서브섹션(`summaries/web`·`summaries/sessions`)이 없으면 생성**한다("없으면 생성" 규칙으로 확정 — setup이 모든 서브섹션을 하드코딩하지 않음) | wiki-setup / ingest-url / wiki-capture |
| 4 | 중첩 frontmatter 링크 Obsidian 미인식 주의 명시 | wiki-knowledge |
| 5 | **wiki-status 로그 라인 추가** — §3-6은 status의 log append를 허용하나 §4-7엔 단계 없음. `[YYYY-MM-DD] STATUS …` 라인 추가로 wiki-query와 일관화 | spec §4-7 |
| 6 | **wiki-query 답변 블록 한국어화** — `Based on the wiki:` 등 영어 라벨을 `위키 기반:` / `참고 페이지:` / `공백:`으로 통일 | spec §4-5 |

---

## 5. 스킬별 재작성 범위 (12개)

| 스킬 | 유형 | 핵심 수정 | 우선순위 |
|---|---|---|---|
| `wiki-project-design` | 절차+위험 | 한 줄 워크플로우 → 번호 단계, change 라이프사이클 mermaid | 🔴 최우선 |
| `wiki-project-record` | 절차+라우팅 | 한 줄 워크플로우 분해, 라우팅 mermaid, 불변성 규칙 | 🔴 |
| `ingest-url` | 절차+신뢰경계 | 품질체크 신설, Trust Boundary 게이트화, index 섹션 정합 | 🔴 |
| `wiki-capture` | 절차+위험 | 비밀 마스킹 규칙 강조, index 섹션 정합, 품질체크 | 🟡 |
| `wiki-ingest` | 절차+신뢰경계 | Trust Boundary/경로가드 가독화(내용 견고, 형식 정리) | 🟡 |
| `wiki-setup` | 절차 | 13단계 정리, description 트리거 정합 | 🟡 |
| `wiki-knowledge` | 절차 | 중첩링크 주의 추가, 분할 트리거 명료화 | 🟡 |
| `wiki-query` | read-only | 검색 사다리 가독화, 답변 라벨 한국어화 | 🟡 |
| `wiki-project-init` | 절차 | 인터뷰 패턴·비목표 규칙 정리 | ℹ️ |
| `using-llm-wiki` | 라우터 | 규칙+라우팅 표 정합(AGENTS 미러) | ℹ️ |
| `wiki-lint` | 테이블 | 17체크 표 유지, 밀집 셀 분해 | ℹ️ 소폭 |
| `wiki-status` | read-only | 경계 명료화 + §4-5 로그 결정 반영 | ℹ️ 소폭 |

각 스킬의 상세 의무(트리거·입력·워크플로우 단계·쓰기 타깃·표기·불변식)는 spec §4의 per-skill 섹션이 정본이다. 재작성은 그 의무를 **형식만 바꿔** 충실히 반영하며 내용을 추가·삭제하지 않는다.

---

## 6. 실행 계획

1. **작성 가이드 신설** (`docs/skill-authoring-guide.md`) — §3 규약 못박기 (단일 출처)
2. **스펙/AGENTS 정합 수정** (§4) — 스킬이 인용할 정본을 먼저 정정
3. **스킬 재작성** — 우선순위 순(🔴→🟡→ℹ️), 가이드 + 정정된 스펙 기준
4. **검증** — 각 스킬을 spec §4 per-skill 의무와 대조 + 표기 일관성 볼트 스윕

상세 태스크 분해·검증 절차(스킬 동작 압박테스트 여부 포함)는 구현 계획(writing-plans) 단계에서 확정한다.

---

## 7. 비목표 (YAGNI)

- 스킬의 **동작·의무 변경** — 이번 작업은 형식·표기 정합만. 워크플로우 로직은 spec §4 그대로 유지.
- 스펙 전면 재작성 — §4의 6개 타깃 수정만.
- Phase 2 기능(`wiki-lint --consolidate` 등) 손대지 않음.
- 실측 볼트(`Documents/obsidian`)의 기존 페이지 마이그레이션 — 별도 작업(`feat/vault-redesign-migration`).
