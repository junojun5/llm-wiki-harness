# LLM Wiki Harness — 멀티 플랫폼 배포 설계

**작성일:** 2026-06-25
**상태:** 설계 확정 (구현 대기)
**기반 스펙:** [[2026-05-28-llm-wiki-harness-engineering]] (이하 "하네스 스펙")
**목표:** 하네스 스펙의 11개 스킬·스크립트·훅을 Claude Code / Codex / Cursor / Antigravity 4개 플랫폼에 배포 가능한 단일 git repo로 구현한다.

---

## 1. 범위

이 문서는 **배포 레이어**를 설계한다. 11개 스킬의 *내부 로직*은 하네스 스펙 §4가 단일 출처이며 여기서 재서술하지 않는다. 이 문서가 정의하는 것:

1. repo 디렉토리 레이아웃 (Superpowers v6 모델 기반)
2. 도구 비종속 런타임 홈 `~/.llm-wiki/` (포터블 스크립트 호출)
3. 스킬·스크립트·훅의 플랫폼별 매핑
4. 부트스트랩 스킬 `using-llm-wiki`
5. 훅 전략 (Claude·Codex·Cursor 기계적 가드 + Antigravity만 우아한 강등)
6. 하이브리드 배포 (마켓플레이스 + install.sh)
7. 컨텍스트 파일 (루트 AGENTS.md 단일 출처 + CLAUDE.md import)
8. README best-practice + 케이스별 사용 흐름
9. 구현 순서 (TDD)

**확정된 결정 (브레인스토밍):**
- 산출물 범위 = 전체 구현 (11개 스킬 본문 + 스크립트 + 훅 모두 작성)
- 배포 모델 = 하이브리드
- 훅 = Claude 기준 등록 + Codex·Cursor 네이티브 가드 + Antigravity만 우아한 강등 (멀티모델 리뷰 정정)
- repo 위치 = 볼트 밖 새 repo
- 부트스트랩 스킬 = 포함
- 스킬 작성 = `raw/articles/AI-코딩-에이전트/best-skill-creator/` 가이드 준수 (TDD: RED→GREEN→REFACTOR, description은 "Use when…" 트리거만)

---

## 2. 핵심 아키텍처 결정 — 도구 비종속 런타임 홈 `~/.llm-wiki/`

### 문제

하네스 스펙 §3-2/§3-4는 공유 스크립트를 `~/.claude/scripts/resolve-vault.sh`로, 전역 포인터를 `~/.claude/wiki-default-vault`로 **Claude 경로에 하드코딩**한다. 멀티 플랫폼에서는 깨진다 — Codex는 `~/.codex/`·`~/.agents/`, Cursor·Antigravity는 플러그인 루트가 다르고 마켓플레이스도 없다.

### 해법

플랫폼과 무관한 단일 런타임 홈을 둔다:

```
~/.llm-wiki/
  scripts/
    resolve-vault.sh           ← 하네스 스펙 §3-2 resolver
    validate-frontmatter.sh    ← 하네스 스펙 §3-3 validator
    build-link-graph.sh        ← 하네스 스펙 §4-6 링크 그래프
  default-vault                ← 전역 볼트 포인터 (구 ~/.claude/wiki-default-vault)
```

**근거:**
- 4개 도구 모두 bash를 실행하고 `$HOME`을 공유한다. 스킬·훅은 어느 플랫폼에서든 `~/.llm-wiki/scripts/...` **한 경로**만 참조하면 된다 — drift 0.
- **스킬**은 LLM이 실행하는 마크다운이라 플러그인 환경변수를 못 쓴다 → 고정 공유 경로 `~/.llm-wiki/scripts/...` 하나만 참조한다(drift 0). **훅**은 세 플랫폼 모두 `plugin.json`의 `hooks` 키로 자동 등록되며 command가 플러그인 루트를 참조해 **플러그인 설치만으로 등록·동작**한다 — Claude `${CLAUDE_PLUGIN_ROOT}`(무음), Codex `${PLUGIN_ROOT}`(1회 `/hooks` trust + `[features] hooks`), Cursor `./hooks/run-hook.cmd`(로더가 플러그인 루트 기준 spawn → self-locating; 로컬 전용). Claude/Codex의 첫 SessionStart가 플러그인 루트의 `scripts/`를 `~/.llm-wiki/scripts/`로 symlink해 스킬이 쓰는 공유 경로까지 자가치유하므로 install.sh 없이 완결된다. `--fallback`(수동) 경로는 그 플러그인 루트 참조를 실제 설치 절대경로로 render해 동일 등록을 안내한다. (구설계는 `${CLAUDE_PLUGIN_ROOT}` 회피를 택했으나, 그 경우 마켓플레이스가 스크립트를 배치하지 않아 훅이 조용히 no-op 되는 결함이 있어 위 방식으로 정정. **Antigravity만** 훅 스키마 미공개로 이 자동화에서 빠지고 `install.sh`가 `~/.llm-wiki` 부트스트랩을 대신한다.)
- 하네스 스펙 §3-2의 "resolver는 상태를 저장하지 않고 매번 fresh resolve" 원칙은 그대로 유지된다 — 위치만 `~/.claude/` → `~/.llm-wiki/`로 일반화.

### 스펙 동기화

이 결정은 하네스 스펙과 충돌하므로 **하네스 스펙 §3-2·§3-4·§5를 동기화**해야 한다:
- `~/.claude/scripts/` → `~/.llm-wiki/scripts/`
- `~/.claude/wiki-default-vault` → `~/.llm-wiki/default-vault`
- §5 글로벌 훅의 resolver 호출 경로도 동일 변경
- "canonical = 전용 git repo, `~/.claude/`는 설치 타깃" → "canonical = repo, 런타임 공유물은 `~/.llm-wiki/`, 스킬/훅은 플랫폼별 설치 타깃"

구현 계획에 **스펙 동기화 태스크**를 포함한다 (코드 작성 전 선행).

---

## 3. repo 디렉토리 레이아웃

```
llm-wiki-harness/                      ← 새 repo (canonical source)
  README.md                            ← 4-플랫폼 설치 + best-practice + 케이스별 흐름 (§8)
  LICENSE
  install.sh                           ← 하이브리드 설치자 (§7)
  VERSION                              ← repo HEAD 보조 버전 문자열

  AGENTS.md                            ← 공유 운영 규칙 단일 출처. repo/vault 루트 로드 (Cursor·Codex 네이티브). ≤32 KiB (Codex 예산, §6)
  CLAUDE.md                            ← "@AGENTS.md" import 한 줄 (단일 출처 유지)
  # GEMINI.md 제거 — Antigravity는 AGENTS.md를 읽으며 GEMINI.md는 비표준 (§6)

  skills/                              ← canonical 스킬 (단일 출처)
    using-llm-wiki/SKILL.md            ← 부트스트랩 스킬 (§5)
    wiki-setup/SKILL.md
    wiki-ingest/SKILL.md
    ingest-url/SKILL.md
    wiki-capture/SKILL.md
    wiki-query/SKILL.md
    wiki-lint/SKILL.md
    wiki-status/SKILL.md
    wiki-knowledge/SKILL.md
    wiki-project-init/SKILL.md
    wiki-project-design/SKILL.md
    wiki-project-record/SKILL.md

  scripts/                             ← canonical 스크립트 → 설치 시 ~/.llm-wiki/scripts/
    resolve-vault.sh
    validate-frontmatter.sh
    build-link-graph.sh

  hooks/
    run-hook.cmd                       ← 폴리글랏 런처 (Windows .cmd + Unix bash)
    session-start                      ← 부트스트랩 주입 스크립트 (플랫폼별 stdout 분기: Claude/Codex/Cursor)
    wiki-protect-raw.sh                ← 가드: raw/ 쓰기 보호 (하네스 스펙 §5-2). 공유 bash 로직
    wiki-validate-frontmatter.sh       ← 가드: frontmatter 검증 wrapper (§5-3). 공유 bash 로직
    hooks.json                         ← Claude 등록 (PascalCase 이벤트 + hookSpecificOutput)
    hooks-codex.json                   ← Codex 등록 → 설치 시 ~/.codex/hooks.json (NOT .agents/)
    hooks-cursor.json                  ← Cursor 등록 템플릿 → 설치 시 .cursor/hooks.json (camelCase 이벤트)

  .claude-plugin/
    plugin.json                        ← Claude 플러그인 매니페스트
    marketplace.json                   ← Claude 마켓플레이스 (source: "./")
  .codex-plugin/
    plugin.json                        ← Codex 플러그인 매니페스트 (skills/hooks 명시 선언)
    marketplace.json                   ← Codex 마켓플레이스 → 설치 시 ~/.agents/plugins/marketplace.json (§7-2)
  .cursor-plugin/
    plugin.json                        ← Cursor 플러그인 매니페스트 (name 필수 + optional). 공식 마켓플레이스(cursor.com/marketplace/publish)·~/.cursor/plugins/local 로컬 테스트 지원 (cursor.com/docs/plugins)
  # ⚠️ 정정: 직전 설계는 "Cursor는 마켓플레이스 없음"이라 .cursor-plugin/을 제거했으나, 이는 사실이 아니다 —
  #   Cursor는 플러그인 시스템(Rules+Skills+Hooks+MCP 번들)과 공식 마켓플레이스를 가진다. 매니페스트 복원.
  #   Cursor 배포 표면 = 전역(~/.cursor/hooks.json·skills) + 프로젝트(.cursor/) + 플러그인(.cursor-plugin/).

  docs/
    spec.md                            ← 하네스 스펙 이관본 (심볼릭 또는 복사)
    distribution-design.md             ← 이 문서 이관본

  tests/                               ← 스킬 압박 테스트 + 설치 스모크 (§9)
    skills/
    install/
    fixtures/
      codex-hooks/                     ← probe hook으로 확보한 stdin/stdout golden fixture (§9, Codex §12-4)
      cursor-hooks/                    ← Cursor preToolUse/sessionStart stdin/stdout golden fixture (§9)
```

**배치 원칙 (Superpowers v6 + 하네스 스펙 §3-4):**
- `skills/`·`scripts/`·`hooks/`가 단일 출처. 플랫폼별 위치는 install.sh가 symlink로 파생.
- 여러 스킬·훅이 공용하는 스크립트는 repo 루트 `scripts/` (하네스 스펙 §3-4 배치 원칙 유지). 소유자 없는 `lib/`는 두지 않는다.

---

## 4. 스킬·스크립트·훅 플랫폼 매핑

### 4-1. 스킬 위치

`skills/<name>/SKILL.md` 단일 사본을 각 플랫폼이 읽는 위치로 symlink:

| 플랫폼 | 글로벌 스킬 경로 | 프로젝트 스킬 경로 | 비고 |
|---|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` | 마켓플레이스도 가능 |
| Codex CLI | `~/.agents/skills/` | `.agents/skills/` | **hooks/config는 `.codex/` (§4-3)** |
| Cursor | `~/.cursor/skills/` 또는 `~/.agents/skills/` | `.agents/skills/` **및** `.cursor/skills/` 둘 다 discovery | `~/.cursor/skills-cursor/`는 내장 전용 → symlink 타깃 금지 |
| Antigravity | `~/.gemini/config/skills/` (실측 확인) | `.agents/skills/` | 훅 스키마 미공개(404·0 handlers) → 플러그인은 skills+rules만 (§10) |

SKILL.md frontmatter = `name` + `description`만 → 4개 도구 공통이라 한 파일이 그대로 이식된다. (Cursor 전용 `disable-model-invocation: true`는 슬래시 전용 스킬에 한해 선택 적용 — §9 참조.)

**비파괴적 배포 대안 (Antigravity/Cursor):** 개별 스킬 폴더를 일일이 symlink하는 대신 `.agents/skills.json`에 repo `skills/` 경로를 상대 등록하는 방식도 지원 가능. symlink 생성이 제한되는 환경(Windows 비관리자)에 유용.
```json
{ "entries": [ { "path": "../skills" } ] }
```

### 4-2. 스크립트 위치

전부 `~/.llm-wiki/scripts/` (§2). 스킬 본문·훅은 이 절대경로를 참조한다. 플랫폼 무관.

### 4-3. 훅 위치 — Claude·Codex·Cursor 기계적 가드 + Antigravity만 우아한 강등

**정정:** 직전 설계는 Cursor를 강등 대상으로 묶었으나, Cursor는 Claude/Codex와 동급의 네이티브 훅을 지원한다. 세 플랫폼 모두 **플러그인 매니페스트가 훅을 자동 등록**한다(아래 command 메커니즘). **훅(기계적 차단)을 못 싣는 플랫폼은 Antigravity 하나뿐**이고, 이는 우리 사정이 아니라 **플랫폼 한계**다 — 공식 훅 스키마(`antigravity.google/schemas/v1/hooks.json`)가 **404(미공개)**이고, 실측상 `agy`가 `hooks.json`을 파싱은 하나 **`0 handlers`만 등록해 훅이 발화하지 않는다**(agy v1.0.3; superpowers도 Antigravity를 instructions-file(skills+rules)로만 배포). Google이 handler 스키마를 공개하면 `probe-hook.sh` 실측 후 Antigravity 훅을 플러그인에 추가한다. 스킬·rules·플러그인 배포 자체는 Antigravity도 완전 지원되며 강등 대상이 아니다.

| 훅 | Claude | Codex | Cursor | Antigravity |
|---|---|---|---|---|
| `wiki-protect-raw` | ✅ 플러그인 자동등록 `hooks.json` PreToolUse (`${CLAUDE_PLUGIN_ROOT}`) | ✅ 플러그인 자동선언 PreToolUse (`${PLUGIN_ROOT}`) — 최초 1회 `/hooks` trust + `[features] hooks` | ✅ 플러그인 자동등록 `preToolUse`→`permission:deny`+`user_message` (`./hooks/run-hook.cmd`, 로컬) | ⚠️ 훅 스키마 미공개(404·0 handlers) → AGENTS.md 소프트 룰 |
| `wiki-validate-frontmatter` | ✅ PostToolUse | ✅ (trust 필요) | ✅ `postToolUse` | ⚠️ 미공개 → `wiki-lint` 일괄 검증 |
| `session-start` (부트스트랩 주입) | ✅ `SessionStart` `startup\|resume\|clear\|compact` (전역, CWD-in-vault 자가게이팅) | ✅ `SessionStart` (trust) | ✅ `sessionStart`→`additional_context`+`env` (Cloud Agent 미지원) | ⚠️ 미공개 → AGENTS.md 상시 로드 대체 |

- **훅 로직(bash)은 공유**, **등록 JSON만 플랫폼별 3종** (`hooks.json` / `hooks-codex.json` / `hooks-cursor.json`). 셋 다 플러그인 매니페스트(`plugin.json`의 `hooks` 키)가 가리켜 **설치 시 자동 등록**되고, command는 모두 self-locating `run-hook.cmd`를 경유한다. 이벤트명·응답 필드·matcher 문법·플러그인 루트 참조가 다르다:
  - Claude: PascalCase 이벤트 + `hookSpecificOutput.additionalContext`. command `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd` — 설치 즉시 무음 등록.
  - Codex: 동일 페이로드 계열. command `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/run-hook.cmd`(`PLUGIN_ROOT`=Codex 공식 env var; 설치 경로 `~/.codex/plugins/cache/<mkt>/<name>/<version>/`가 버전 스코프라 하드코딩 금지). **non-managed 훅은 `/hooks` trust + `[features] hooks=true`(비Windows) 후 실행** (등록만으로 즉시 차단 아님).
  - Cursor: camelCase 이벤트 + `permission:deny`/`additional_context`/`env`, **matcher는 JavaScript 정규식**(POSIX 아님). command `./hooks/run-hook.cmd` — Cursor는 플러그인 루트 env var가 없고 프로세스 cwd가 워크스페이스로 잡히므로(cwd 버그), 로더가 매니페스트 경로를 플러그인 루트 기준으로 spawn한 뒤 `run-hook.cmd`가 `$0`로 자가위치해 형제 스크립트를 실행한다. `<EXTREMELY_IMPORTANT>` 래핑은 훅이 `additional_context` 문자열에 직접 포함.
- `SessionStart` matcher에 **`compact` 포함** — compact 이후에도 부트스트랩 재주입 (실제 컨텍스트 반영 여부는 §9 스모크로 검증).
- Antigravity만 훅의 *자동 강제력*을 포기하고 부트스트랩 스킬 가드 규칙 + AGENTS.md로 동등한 *지침*을 제공한다. 손실되는 것은 "기계적 차단"뿐 — 사용자가 선택한 우아한 강등.
- Cursor의 raw/ 보호는 **`preToolUse`(Write 도구 레벨)**가 담당해야 한다. shell 전용 `beforeShellExecution`만으로는 Write 도구 경로를 못 막는다.
- 하네스 스펙 §5-0 글로벌/볼트-로컬 배치 원칙은 Claude에 한해 유지. 모든 플랫폼의 글로벌 훅 vault resolution은 §2의 `~/.llm-wiki/scripts/resolve-vault.sh`를 호출한다.

---

## 5. 부트스트랩 스킬 `using-llm-wiki`

"이 볼트에서 일할 때 항상 떠 있어야 하는 진입 규칙"의 단일 스킬. Superpowers의 `using-superpowers`에 대응.

**역할:**
- **Step 0 강제** — 모든 wiki 작업 전 `~/.llm-wiki/scripts/resolve-vault.sh` 호출 (하네스 스펙 §3-2 Config Gate)
- **raw/ 불변** 원칙 (§5-2)
- **쓰기 종료 시퀀스** (하네스 스펙 §3-6: 페이지 → index → log → hot → QMD)
- **11개 스킬 라우팅 맵** — 언제 어떤 스킬을 호출하는지
- **인용·충돌·archive 규칙**의 진입점 (상세는 각 스킬·스펙 인용)

**주입 메커니즘:**
- Claude/Codex/Cursor: `session-start` 훅이 `skills/using-llm-wiki/SKILL.md`를 읽어 세션 컨텍스트로 주입 (`<EXTREMELY_IMPORTANT>` 래핑). 플랫폼별 stdout 필드 분기 — Claude `hookSpecificOutput.additionalContext` / Codex `additional_context` / Cursor `additional_context`+`env`. Cursor엔 `hookSpecificOutput` 래퍼가 없으므로 래핑 문자열을 `additional_context`에 직접 넣는다.
- Antigravity: 훅 스키마 미공개(404·0 handlers) → AGENTS.md가 부트스트랩 핵심 규칙을 상시 로드하여 대체.
- **Cursor Cloud Agent에서는 `sessionStart`·user hooks 미지원** → 로컬 Agent vs Cloud Agent 차이를 README 트러블슈팅에 명시.

**작성 원칙:** 토큰 효율 최우선 (매 세션 로드). best-skill-creator 가이드의 "frequently-loaded skills <200 words" 목표 준수. 상세는 본문에 두지 않고 개별 스킬·스펙을 인용. AGENTS.md에 들어가는 축약판도 Codex 32 KiB 예산(§6)을 넘기지 않는다.

---

## 6. 컨텍스트 파일 — 단일 출처

| 파일 / 위치 | 소비 플랫폼 | 내용 |
|---|---|---|
| **루트 `AGENTS.md`** (canonical) | Cursor (프로젝트 루트), Codex (프로젝트+`~/.codex/`) | 부트스트랩 핵심 규칙 + 스킬 라우팅. **단일 출처** |
| `.agents/AGENTS.md` (symlink→루트) | Antigravity 프로젝트 | install.sh가 루트 AGENTS.md로 symlink |
| `~/.gemini/config/AGENTS.md` (symlink) | Antigravity 글로벌 | install.sh가 생성 |
| `CLAUDE.md` | Claude Code | `@AGENTS.md` import 한 줄 (중복 없음) |
| ~~`GEMINI.md`~~ | — | **제거**. Antigravity는 AGENTS.md를 읽으며 GEMINI.md는 비표준 명칭 (drift 위험) |

**정정:** Cursor·Codex의 네이티브 로드 경로는 **프로젝트 루트 `AGENTS.md`**이지 `.agents/AGENTS.md`가 아니다. 따라서 canonical을 루트 `AGENTS.md`에 두고, `.agents/AGENTS.md`(Antigravity 프로젝트)·`~/.gemini/config/AGENTS.md`(Antigravity 글로벌)는 install.sh가 symlink로 파생한다 → drift 0.

**Codex 32 KiB 예산:** Codex는 global/project `AGENTS.md`를 instruction chain으로 병합하며 기본 `project_doc_max_bytes`=32 KiB. AGENTS.md에는 `using-llm-wiki` 축약판만 둔다 — ① Config Gate(`~/.llm-wiki/scripts/resolve-vault.sh`) ② raw/ 쓰기 금지 ③ 쓰기 종료 시퀀스 ④ 11개 스킬 라우팅 1줄 요약. 상세 절차는 각 `SKILL.md`·스펙으로 위임. 한도 초과 시 `project_doc_max_bytes` 상향 방법을 README 트러블슈팅에 둔다.

---

## 7. 배포 — 하이브리드

### 7-1. install.sh (얇은 부트스트랩 + 폴백)

**정정(플러그인-우선):** install.sh는 더 이상 Cursor의 "주력 배포 표면"이 아니다. 스킬·훅은 각 플러그인 매니페스트가 자동 등록하고(§7-2·§5), install.sh는 다음만 담당하는 얇은 스크립트다.

```
[1] (항상) ~/.llm-wiki/scripts/ 에 scripts/* symlink — 모든 도구 공용 런타임(Config Gate·가드 훅 의존).
    마켓플레이스 설치에선 첫 SessionStart(Claude/Codex 훅)가 대신 부트스트랩하는 안전망.
[2] (항상, ~/.gemini 감지 시) Antigravity 전역 플러그인 번들 — plugin.json + skills/ + rules/llm-wiki.md(=AGENTS.md).
    훅 미포함(스키마 미공개). Antigravity는 훅 자가치유가 불가하므로 이 경로가 ~/.llm-wiki 부트스트랩의 유일 보장.
[3] --fallback: 마켓플레이스 미사용 환경용 — Claude/Codex/Cursor 홈 전역 배치. 플러그인 훅 command의 플러그인
    루트 참조(${CLAUDE_PLUGIN_ROOT}/${PLUGIN_ROOT}/`./hooks/`)를 실제 설치 절대경로로 render(python: 중첩 브레이스 안전):
      - Claude: hooks.json → ~/.claude/llm-wiki-hooks.settings.json (settings.json 머지 안내)
      - Codex : hooks-codex.json → ~/.codex/hooks.json (등록 후 /hooks trust 필요)
      - Cursor: hooks-cursor.json → ~/.cursor/hooks.json (절대경로)
[4] --vault <p>: 프로젝트-로컬 — .agents/skills, 루트 AGENTS.md(+.agents/ symlink),
    .codex/hooks.json·.cursor/hooks.json(render), .cursor/sandbox.json({{VAULT_ABS}} 치환).
```

- **Codex 배포 표면 분리:** 스킬=`.agents/skills/`, 마켓플레이스=`~/.agents/plugins/marketplace.json`, hooks/config=`~/.codex/hooks.json`(또는 프로젝트 `.codex/`). 플러그인 설치 ≠ 스킬 폴더 직접 배치 — 별개 단위로 안내.
- **Cursor sandbox:** 기본 `workspace_readwrite`는 워크스페이스 밖 R/W를 차단 → `~/.llm-wiki/scripts/` 호출이 실패할 수 있음. `.cursor/sandbox.json`의 `additionalReadwritePaths` 템플릿이 필요 (Antigravity §11-5 권한 프롬프트와 유사하나 Cursor는 별도 sandbox 레이어).
- **Windows:** 공유 스크립트는 `.sh`(bash) → Git Bash 또는 WSL bash가 PATH에 있어야 함을 README에 명시. `.ps1`/`.bat` 패리티 버전 + 런처 OS 분기는 향후 보완 항목(§10).
- `--update-path`(전역 볼트 재지정), `--repair` 등 하네스 스펙 §3-1 플래그는 `wiki-setup` 스킬이 담당. install.sh는 *배포*만, 볼트 *설정*은 wiki-setup.
- 멱등(idempotent): 재실행 안전, 기존 symlink 갱신.

### 7-2. 마켓플레이스 (Claude/Codex 병행)

- Claude: `.claude-plugin/marketplace.json` (`source: "./"`) → `/plugin marketplace add <owner/repo>` → `/plugin install`
- Codex: `.codex-plugin/plugin.json`(skills+hooks 명시 선언) + `.codex-plugin/marketplace.json` → `codex plugin marketplace add <repo>` → `/plugins` 설치. 훅은 `${PLUGIN_ROOT}/hooks/run-hook.cmd` 경유로 등록되나 **non-managed라 최초 1회 `/hooks` trust + `[features] hooks=true`(비Windows)** 필요.
- **Cursor: 마켓플레이스 있음(정정).** `.cursor-plugin/plugin.json`이 `skills`+`hooks`(→`hooks-cursor.json`)를 선언해 플러그인 설치만으로 스킬·훅이 자동 등록된다(로컬 데스크톱). 공식 마켓플레이스 또는 `~/.cursor/plugins/local/`로 배포. 직전 설계의 "Cursor 마켓플레이스 없음 → install.sh가 실질 배포 표면"은 **오류였고**, install.sh는 이제 폴백(§7-1 `--fallback`)일 뿐이다.
- 마켓플레이스 설치 시에도 공유 스크립트는 `~/.llm-wiki/`에 있어야 하므로, Claude/Codex 플러그인은 첫 SessionStart 훅이 `~/.llm-wiki/`를 자가-부트스트랩한다. **Antigravity는 훅이 없어 자가치유 불가** → `install.sh`(§7-1 [2]) 1회가 유일 경로.

### 7-3. 업데이트

- 마켓플레이스: 호스트 플러그인 매니저가 처리.
- 수동(symlink): `git pull` (symlink이라 설치본 drift 불가, 하네스 스펙 §3-4).
- 스킬 버전 = repo HEAD + 보조 `VERSION` 파일.

---

## 8. README — best-practice + 케이스별 사용 흐름 (사용자 요구)

README.md는 단순 설치 안내를 넘어 **repo를 잘 활용하기 위한 상세 best-practice**와 **케이스별 시나리오**를 포함한다.

**구성:**
1. **개요** — LLM Wiki가 무엇이고 왜 (하네스 스펙 §1 요약)
2. **설치** — 4개 플랫폼별 (마켓플레이스 / install.sh), `~/.llm-wiki/` 부트스트랩
3. **스킬 카탈로그** — 11개 스킬 + description + 언제 쓰는지 표
4. **케이스별 사용 흐름 (시나리오)** — 실제 명령 시퀀스로:
   - **신규 볼트 시작**: `wiki-setup` → `wiki-ingest` → `wiki-query`
   - **자료 축적**: `wiki-ingest` (raw) / `ingest-url` (URL) / `wiki-capture` (대화)
   - **지식 종합**: summaries 누적 → `wiki-knowledge`
   - **질문·검색**: `wiki-query` (cheap retrieval path)
   - **유지보수**: `wiki-lint` → `--fix` → raw cleanup
   - **프로젝트 운영**: `wiki-project-init` → `wiki-project-design` (change proposal) → `wiki-project-record` (decision)
   - **상태 점검**: `wiki-status`
   - 각 시나리오에 입력/기대 산출물/플랫폼 차이(훅 유무) 명시
5. **best-practice** — raw/ 불변, 인용 규칙, 충돌 처리, QMD 선택 설치, 멀티 볼트 운영, 우아한 강등 플랫폼에서의 주의점
6. **트러블슈팅** — Config Gate 실패 코드(E_*)별 복구, QMD 미설치 fallback, 훅 미등록, Codex `/hooks` trust 미완(차단 안 됨), Codex `project_doc_max_bytes` 상향, Cursor 로컬 vs Cloud Agent 훅 차이, Cursor/Antigravity sandbox·`~/.llm-wiki/` 접근 권한 승인(Allow), Windows Git Bash/WSL 요구

각 시나리오는 하네스 스펙 §4의 해당 스킬 워크플로를 인용하되, README는 *사용자 관점의 흐름*에 집중한다.

---

## 9. 구현 순서 (TDD)

best-skill-creator의 Iron Law(테스트 없는 스킬 금지) 준수. 순서:

1. **하네스 스펙 동기화** — §2의 `~/.llm-wiki/` 변경을 하네스 스펙 §3-2·§3-4·§5에 반영 (코드 선행 조건)
2. **repo 스캐폴딩** — 디렉토리·LICENSE·VERSION·빈 매니페스트
3. **공유 스크립트** (결정론적 → 단위 테스트 가능): resolve-vault.sh → validate-frontmatter.sh → build-link-graph.sh
4. **부트스트랩 스킬** `using-llm-wiki` + session-start 훅
5. **11개 스킬** — 각각 RED(압박 시나리오 baseline) → GREEN(작성) → REFACTOR(루프홀). 우선순위: wiki-setup → wiki-ingest → wiki-query → wiki-lint → wiki-status → ingest-url → wiki-capture → wiki-knowledge → wiki-project-{init,design,record}
6. **훅 페이로드 probe (선행)** — 가드 훅 작성 전, 최소 probe hook으로 각 이벤트의 stdin JSON·stdout 처리를 golden fixture로 확보 (CLI 버전 변화 시 raw/ 보호가 조용히 깨지는 것 방지):
   - `tests/fixtures/codex-hooks/`: PreToolUse·PostToolUse(`apply_patch`/`Edit`/`Write`), SessionStart(`startup`/`resume`/`clear`/`compact`)
   - `tests/fixtures/cursor-hooks/`: `preToolUse`(`tool_name`·파일경로 필드명), `sessionStart`
7. **가드 훅** wiki-protect-raw / wiki-validate-frontmatter (fixture 기반 단위 테스트 통과) + hooks.json / hooks-codex.json / hooks-cursor.json + run-hook.cmd. Cursor `.cursor/sandbox.json` 템플릿 포함. 스킬별 `disable-model-invocation` 적용 여부 결정.
8. **컨텍스트 파일** 루트 AGENTS.md (≤32 KiB) / CLAUDE.md (@import). GEMINI.md 없음.
9. **install.sh + 매니페스트** (하이브리드, §7-1 배포 표면 분리)
10. **README** (§8)
11. **4-플랫폼 스모크 테스트** — 하네스 스펙 §1 Phase 1 end-to-end를 각 플랫폼에서 (가능 범위). 포함: Codex `/hooks` trust 후 raw/ 차단, compact 재주입 컨텍스트 반영, Cursor `preToolUse` raw/ 차단·`sessionStart` 주입·sandbox 경로 R/W.

---

## 10. 미해결·검증 필요 항목

- **Antigravity 훅 = 플랫폼 미지원(우리 사정 아님)** — 글로벌 스킬 경로(`~/.gemini/config/skills/`)·프로젝트(`.agents/skills/`)·AGENTS.md 로드 경로는 실측 확인됨(§4-1). 훅은 **공식 스키마가 아직 없다**: `antigravity.google/schemas/v1/hooks.json` = **404**, 그리고 `agy`(v1.0.3)가 `hooks.json`을 파싱하고도 **`0 handlers`만 등록**해 발화하지 않는 것이 실측됨. 즉 필드명 미검증이 아니라 handler 스키마 자체가 미공개다. Google 공개 시 `probe-hook.sh`로 실측 후 플러그인에 훅 추가. 그전까지 Antigravity는 우아한 강등(부트스트랩 규칙 + AGENTS.md 소프트 룰)으로만 보장.
- **Codex/Cursor 훅 페이로드 스키마** — `.tool_input.file_path` 등 필드명을 §9-6 probe hook으로 golden fixture화하여 확정 (구현 선행 태스크로 승격).
- **compact 재주입 반영** — Codex/Cursor의 `compact`/`preCompact` 이후 `additional_context` 주입이 실제 모델 컨텍스트에 반영되는지 §9-11 스모크로 검증.
- ~~**마켓플레이스 + `~/.llm-wiki/` 부트스트랩 타이밍**~~ — **해결:** Claude/Codex 플러그인의 첫 SessionStart 훅이 `~/.llm-wiki/scripts`를 플러그인 루트에서 자가-부트스트랩(§5-0 session-start ①). Antigravity는 훅이 없어 `install.sh`(§7-1 [1]·[2])가 담당. Cursor 로컬은 sessionStart로 부트스트랩(Cloud Agent는 install.sh 폴백).
- **Windows `.ps1`/`.bat` 패리티 (향후)** — 1차는 Git Bash/WSL 요구로 처리. 네이티브 cmd/PowerShell 에이전트 수요가 확인되면 `resolve-vault`·`validate-frontmatter`의 PowerShell 대응본 + 런처 OS 분기 추가.
