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
- **스킬**은 LLM이 실행하는 마크다운이라 플러그인 환경변수를 못 쓴다 → 고정 공유 경로 `~/.llm-wiki/scripts/...` 하나만 참조한다(drift 0). **훅은 플랫폼마다 다르다 (2026-07-31 실측)** — **Claude**는 `plugin.json`→`hooks.json`이 `${CLAUDE_PLUGIN_ROOT}` 경유로 무음 자동 등록되고, **Codex**도 `${PLUGIN_ROOT}` 경유로 등록되나 non-managed라 **최초 1회 `/hooks` trust**가 필요하며 그전까지는 **경고 없이 조용히 no-op** 한다(비대화형은 `--dangerously-bypass-hook-trust`). **Cursor는 플러그인 경유 훅 등록이 불가능하다** — cursor-agent가 매니페스트의 `hooks`를 파싱은 하나 내부 `getPluginHooks`가 호출되지 않아(번들 전체 등장 1회 = 정의부뿐) 훅 실행 엔진에 도달하지 않는다. `--plugin-dir`·`~/.cursor/plugins/local/` 양쪽 실측 모두 미발화. 따라서 Cursor 훅은 `install.sh`가 `~/.cursor/hooks.json`(또는 `{ws}/.cursor/hooks.json`)을 배치하는 경로만 유효하다. Claude/Codex의 첫 SessionStart가 플러그인 루트의 `scripts/`를 `~/.llm-wiki/scripts/`로 symlink해 공유 경로를 자가치유하므로 그 둘은 install.sh 없이 완결된다. **Antigravity**는 훅 스키마 미공개로 자동화에서 빠지고 `install.sh`가 `~/.llm-wiki` 부트스트랩을 대신한다.
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
  .agents/plugins/
    marketplace.json                   ← Codex 마켓플레이스 (canonical). ⚠️ Codex는 .codex-plugin/marketplace.json을
                                          읽지 않는다 — 탐색 경로는 .agents/plugins/{marketplace,api_marketplace}.json,
                                          .claude-plugin/marketplace.json, .cursor-plugin/marketplace.json 4개뿐 (2026-07-31 실측)
  .codex-plugin/
    plugin.json                        ← Codex 플러그인 매니페스트 (skills/hooks 명시 선언). 이 경로는 정상 인식됨
  .cursor-plugin/
    plugin.json                        ← Cursor 플러그인 매니페스트 (name 필수 + optional). 공식 마켓플레이스(cursor.com/marketplace/publish)·~/.cursor/plugins/local 로컬 테스트 지원 (cursor.com/docs/plugins)
  # ⚠️ 정정(2026-07-31 실측): Cursor 플러그인은 **스킬 전용 표면**이다. 매니페스트의 hooks 키는
  #   cursor-agent가 소비하지 않으므로(§4-3) 훅은 반드시 .cursor/hooks.json 계열로 배치해야 한다.
  #   Cursor 배포 표면 = 훅: 전역 ~/.cursor/hooks.json + 프로젝트 {ws}/.cursor/hooks.json (install.sh 담당)
  #                      스킬: ~/.cursor/skills · .agents/skills · 플러그인(.cursor-plugin/)

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

**정정 (2026-07-31 실측으로 재정정):** Cursor는 네이티브 훅 자체는 Claude/Codex와 동급으로 지원하지만, **플러그인 매니페스트를 통한 자동 등록은 지원하지 않는다**(위 §4-3 참조 — `getPluginHooks` 미호출). 따라서 **플러그인 설치만으로 훅이 도는 플랫폼은 Claude·Codex 둘뿐**이고, Cursor는 설정 파일 배치(=install.sh)가 필수다. **훅을 아예 못 싣는 플랫폼은 Antigravity 하나**이며 이는 플랫폼 한계다 — 공식 훅 스키마(`antigravity.google/schemas/v1/hooks.json`)가 **404(미공개)**이고, 실측상 `agy`가 `hooks.json`을 파싱은 하나 **`0 handlers`만 등록해 훅이 발화하지 않는다**(agy v1.0.3). Google이 handler 스키마를 공개하면 `probe-hook.sh` 실측 후 Antigravity 훅을 추가한다. 스킬·rules 배포는 Cursor·Antigravity 모두 정상 동작한다(`getAllAgentSkills`는 활성).

| 훅 | Claude | Codex | Cursor | Antigravity |
|---|---|---|---|---|
| `wiki-protect-raw` | ✅ 플러그인 자동등록 `hooks.json` PreToolUse (`${CLAUDE_PLUGIN_ROOT}`) — 차단은 stderr+`exit 2` | ✅ 플러그인 자동선언 PreToolUse (`${PLUGIN_ROOT}`) — 최초 1회 `/hooks` trust 필요, 미신뢰 시 **무경고 no-op**. 차단은 stderr+`exit 2` | ⚠️ **플러그인 경유 불가** → `install.sh`가 `~/.cursor/hooks.json` 배치. 차단은 `{"permission":"deny","user_message":…}`+`exit 0` | ⚠️ 훅 스키마 미공개(404·0 handlers) → AGENTS.md 소프트 룰 |
| `wiki-validate-frontmatter` | ✅ PostToolUse | ✅ (trust 필요) | ⚠️ **플러그인 경유 불가** → `install.sh`가 배치한 `.cursor/hooks.json`의 `postToolUse` | ⚠️ 미공개 → `wiki-lint` 일괄 검증 |
| `session-start` (부트스트랩 주입) | ✅ `SessionStart` `startup\|resume\|clear\|compact` (전역, CWD-in-vault 자가게이팅) | ✅ `SessionStart` (trust) | ⚠️ **플러그인 경유 불가** → `install.sh` 배치 후 `sessionStart`→`additional_context`+`env` (Cloud Agent 미지원) | ⚠️ 미공개 → AGENTS.md 상시 로드 대체 |

- **훅 로직(bash)은 공유**, **등록 JSON만 플랫폼별 3종** (`hooks.json` / `hooks-codex.json` / `hooks-cursor.json`). 셋 다 `run-hook.cmd` 런처를 경유하지만 **등록 경로가 갈린다 (2026-07-31 실측):** `hooks.json`·`hooks-codex.json`은 플러그인 매니페스트(`plugin.json`의 `hooks` 키)가 가리켜 **설치 시 자동 등록**되고, **`hooks-cursor.json`은 자동 등록되지 않는다** — cursor-agent가 매니페스트의 `hooks`를 소비하지 않으므로(`getPluginHooks` 미호출) `install.sh`가 배치하는 **설정 파일 템플릿**으로만 쓰인다. 이벤트명·응답 필드·matcher 문법·플러그인 루트 참조도 다르다:
  - Claude: PascalCase 이벤트 + `hookSpecificOutput.additionalContext`. command `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd` — 설치 즉시 무음 등록.
  - Codex: 페이로드 스키마가 Claude와 동일하다(실측). command `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/run-hook.cmd` — 두 env var 모두 동일 값으로 주입되며 command는 `$SHELL -lc`로 실행돼 셸 확장이 동작한다. 설치 경로 `~/.codex/plugins/cache/<mkt>/<name>/<version>/`가 버전 스코프라 하드코딩 금지. **non-managed 훅은 `/hooks` trust 후 실행**(등록만으로 즉시 차단 아님, 그전까지 무경고 no-op). **`[features] hooks=true`는 0.145.0에서 불필요** — `hooks`가 stable·기본 활성으로 승격됨. 마켓플레이스 매니페스트는 `.agents/plugins/marketplace.json`이어야 한다(`.codex-plugin/marketplace.json`은 읽히지 않음).
  - Cursor: camelCase 이벤트 + `permission:deny`/`additional_context`/`env`, **matcher는 JavaScript 정규식**(POSIX 아님). command는 `hooks-cursor.json`의 `{{HOOKS_DIR}}` placeholder를 **`install.sh`가 실제 설치 절대경로로 render**한다. ~~`./hooks/run-hook.cmd` self-locating 상대경로~~는 플러그인 로더가 플러그인 루트 기준으로 spawn해 줄 때만 성립하는 전제였고, 그 경로가 실측으로 폐기된 뒤에는 프로세스 cwd(=워크스페이스) 기준으로 해석돼 깨진다. `<EXTREMELY_IMPORTANT>` 래핑은 훅이 `additional_context` 문자열에 직접 포함.
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
- **Cursor Cloud Agent에서는 `sessionStart`·user hooks 미지원** → 로컬 Agent vs Cloud Agent 차이를 `docs/troubleshooting.md`에 명시.

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

**Codex 32 KiB 예산:** Codex는 global/project `AGENTS.md`를 instruction chain으로 병합하며 기본 `project_doc_max_bytes`=32 KiB. AGENTS.md에는 `using-llm-wiki` 축약판만 둔다 — ① Config Gate(`~/.llm-wiki/scripts/resolve-vault.sh`) ② raw/ 쓰기 금지 ③ 쓰기 종료 시퀀스 ④ 11개 스킬 라우팅 1줄 요약. 상세 절차는 각 `SKILL.md`·스펙으로 위임. 한도 초과 시 `project_doc_max_bytes` 상향 방법을 `docs/troubleshooting.md`에 둔다.

---

## 7. 배포 — 하이브리드

### 7-1. install.sh (얇은 부트스트랩 + 폴백)

**플랫폼별 위치 (2026-07-31 실측 반영):** Claude·Codex는 플러그인 매니페스트가 스킬·훅을 자동 등록하므로(§7-2·§5) install.sh가 선택이고, 아래 [1]~[4]만 담당하는 얇은 스크립트다. **Cursor는 예외로 install.sh가 필수다** — 플러그인은 스킬만 싣고 훅은 `.cursor/hooks.json` 배치 경로만 유효하다(§4-3). Antigravity도 훅 자가치유가 불가해 [2]가 유일 경로다.

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
- Codex: `.codex-plugin/plugin.json`(skills+hooks 명시 선언) + **`.agents/plugins/marketplace.json`** → `codex plugin marketplace add <repo>` → `codex plugin add <plugin>@<marketplace>`. ⚠️ **`.codex-plugin/marketplace.json`은 Codex가 읽지 않는다** — 탐색 경로는 `.agents/plugins/marketplace.json` · `.agents/plugins/api_marketplace.json` · `.claude-plugin/marketplace.json` · `.cursor-plugin/marketplace.json` 4개뿐이다(공식 openai-curated도 `.agents/plugins/` 사용). 훅은 `${PLUGIN_ROOT}/hooks/run-hook.cmd` 경유로 등록되나 **non-managed라 최초 1회 `/hooks` trust** 필요(미신뢰 시 무경고 no-op).
- **Cursor: 마켓플레이스 있음 — 단 스킬 전용 표면이다 (2026-07-31 재정정).** `.cursor-plugin/plugin.json`은 `skills`만 선언하고 `hooks` 키는 두지 않는다 — cursor-agent가 매니페스트의 `hooks`를 소비하지 않아 선언해도 발화하지 않고 "플러그인만 깔면 훅이 돈다"는 오해만 만든다. 배포는 공식 마켓플레이스 또는 `~/.cursor/plugins/local/`(+ 탐색 경로에 포함되는 `.cursor-plugin/marketplace.json`). **훅은 `install.sh`가 `~/.cursor/hooks.json`(전역) 또는 `{ws}/.cursor/hooks.json`(프로젝트)을 배치하는 경로만 유효하므로, Cursor에 한해 install.sh는 폴백이 아니라 필수다.** ~~"install.sh는 이제 폴백일 뿐"~~ 이라는 직전 서술은 Cursor에는 적용되지 않는다.
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
6. **트러블슈팅** (`docs/troubleshooting.md` — README는 링크만) — Config Gate 실패 코드(E_*)별 복구, QMD 미설치 fallback, 훅 미등록, Codex `/hooks` trust 미완(차단 안 됨), Codex `project_doc_max_bytes` 상향, Cursor 로컬 vs Cloud Agent 훅 차이, Cursor/Antigravity sandbox·`~/.llm-wiki/` 접근 권한 승인(Allow), Windows Git Bash/WSL 요구

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

> **2026-08-01 Phase 3 실측 반영** — 근거는 [`docs/reports/2026-08-01-phase3-e2e-smoke.md`](../reports/2026-08-01-phase3-e2e-smoke.md). 해결된 항목은 취소선으로 남긴다(삭제하지 않는다).

- **Antigravity 훅 = 플랫폼 미지원(우리 사정 아님)** — 글로벌 스킬 경로(`~/.gemini/config/skills/`)·프로젝트(`.agents/skills/`)·AGENTS.md 로드 경로는 실측 확인됨(§4-1). 훅은 **공식 스키마가 아직 없다**: `antigravity.google/schemas/v1/hooks.json` = **404**, 그리고 `agy`(v1.0.3)가 `hooks.json`을 파싱하고도 **`0 handlers`만 등록**해 발화하지 않는 것이 실측됨. 즉 필드명 미검증이 아니라 handler 스키마 자체가 미공개다. Google 공개 시 `probe-hook.sh`로 실측 후 플러그인에 훅 추가. 그전까지 Antigravity는 우아한 강등(부트스트랩 규칙 + AGENTS.md 소프트 룰)으로만 보장. **2026-08-01 재확인:** agy **1.1.8**에서도 동일하다(`hooks.json` **부재 = 의도된 상태**). 단 §4-1의 스킬·AGENTS.md 로드 경로는 **파일 배치까지만** 실측됐고, agy가 그걸 실제로 읽어 준수하는지는 **행동으로 미확인**이다(리포트 §5-5) — "로드 경로 실측 확인"을 준수 확인으로 읽지 않는다.
- ~~**Codex/Cursor 훅 페이로드 스키마**~~ — **해결:** §9-6 probe로 golden fixture 확보 — `tests/fixtures/codex-hooks/`(`pretooluse-apply-patch` · `posttooluse-apply-patch` · `sessionstart`) · `tests/fixtures/cursor-hooks/`(`pretooluse-read` · `pretooluse-shell` · `pretooluse-write` · `sessionstart`). **잔여 2건:** ① Codex 쪽 fixture가 `apply_patch`뿐이라 `Edit`/`Write` 변형과 SessionStart source 4종(`startup`/`resume`/`clear`/`compact`) 중 나머지가 비어 있다. ② **PostToolUse 발화**는 Claude에서만 실측됐고 Codex·Cursor는 **등록만** 확인됐다(리포트 §5-2).
- **compact 재주입 반영** — Codex/Cursor의 `compact`/`preCompact` 이후 `additional_context` 주입이 실제 모델 컨텍스트에 반영되는지 §9-11 스모크로 검증. **2026-08-01 상태: 미착수.** Phase 3 4플랫폼 스모크에서 다루지 않았다(리포트에 `compact` 언급 0건). SessionStart는 `startup` 경로만 실측됐다.
- ~~**마켓플레이스 + `~/.llm-wiki/` 부트스트랩 타이밍**~~ — **해결:** Claude/Codex 플러그인의 첫 SessionStart 훅이 `~/.llm-wiki/scripts`를 플러그인 루트에서 자가-부트스트랩(§5-0 session-start ①). Antigravity는 훅이 없어 `install.sh`(§7-1 [1]·[2])가 담당. Cursor 로컬은 sessionStart로 부트스트랩(Cloud Agent는 install.sh 폴백). **2026-08-01 실측 뒷받침:** 설치 전 `~/.llm-wiki/` 미존재 → 설치 후 `scripts/` 생성, symlink 3개가 플러그인 캐시를 가리키고 `cmp` 일치(리포트 §4-1).
- **Windows `.ps1`/`.bat` 패리티 (향후)** — 1차는 Git Bash/WSL 요구로 처리. 네이티브 cmd/PowerShell 에이전트 수요가 확인되면 `resolve-vault`·`validate-frontmatter`의 PowerShell 대응본 + 런처 OS 분기 추가.
  - ~~**`hooks/run-hook.cmd`의 cmd.exe 분기는 정적 검토만 됐다**~~ → **CI 검증으로 전환 (2026-08-04).** `.github/workflows/windows.yml`의 `cmd-launcher` 잡(**required**, `windows-latest`)이 `tests/hooks/test-run-hook-cmd.cmd`로 인자 전달 계약을 돈다 — 인자 0~3개·공백 포함 인자, 그리고 "스크립트명이 인자로 다시 실리지 않는가"(Phase 2 T5 결함의 핵심). 비ASCII 인자는 코드페이지 의존이라 **WARN으로 관측만** 한다(실사용 계약의 인자는 전부 ASCII: `session-start` + `claude|codex|cursor`). 이로써 Phase 2 T5 이래 열려 있던 항목이 닫히고, 이후 런처를 건드릴 때마다 자동 검증된다.
  - **Git Bash 갈래는 정보용으로 시작한다** — `bash-suite` 잡이 `continue-on-error: true`로 기존 `tests/run.sh` 전체를 돈다. 경로 구분자·`realpath`·symlink 동작이 다르고 `session-start`의 `readlink` 루프도 Windows symlink에서 다르게 돌기 때문에, 처음부터 통과하지 않을 가능성이 실재한다 — **통과하지 않으면 그건 발견이지 실패가 아니다.** 첫 CI가 빨간불로 시작하면 신호가 죽으므로 required로 두지 않았다.
  - **승격 조건 (남겨두지 않으면 `continue-on-error`가 영구화되고 "Windows 지원"이 검증 없는 주장으로 남는다):** `bash-suite`가 9스위트 전부 PASS로 **3회 연속** 통과하면 `continue-on-error`를 제거하고 required로 승격한다. 그때까지 실패 항목은 개별 이슈로 분리해 따로 닫는다. 진행 상태는 이 항목에 갱신한다.
  - ~~**`bash-suite`가 드러낸 두 번째 결함 — Windows Python의 기본 인코딩이 cp1252다**~~ → **해결 (0.3.1).** 모든 python3 호출을 `PYTHONUTF8=1`로 실행하는 계약을 **스펙 §3-9**로 신설하고 6개 호출 지점 전부에 적용했다. 회귀는 `LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0`으로 ASCII locale을 만들어 고정했다(macOS/Linux는 C locale에서 UTF-8 모드가 자동 활성화되므로 그 자동화까지 꺼야 Windows와 동일 조건이 된다). RED에서 실측한 증상: resolver가 한글 경로 볼트에 `exit 4` 오진 · 주입 페이로드 소실 · Cursor deny JSON 소실 · 위반 메시지가 `필수…` 이스케이프로 손상 · 한글 파일명이 링크 그래프에서 누락. 아래는 그 당시 진단 기록이다.
  - **(진단 기록) Windows Python의 기본 인코딩이 cp1252다 (2026-08-04).** `UnicodeDecodeError: 'charmap' codec can't decode byte 0x9d` 가 여러 스위트에서 나왔다. 이건 테스트만의 문제가 아니다 — **프로덕션 코드에 두 표면이 있다:**
    - `scripts/resolve-vault.sh:43` `json.load(open(sys.argv[1]))` — **encoding 미지정.** `.wiki-config.json`에 한글이 들어가면(Windows 사용자 이름·볼트 경로가 한글인 흔한 경우) cp1252로 읽어 예외 → `PARSED`가 비어 `E_INVALID_CONFIG` **오진**. `E_NO_RUNTIME`(§3-2)이 닫은 것과 **같은 병의 다른 표면**이다.
    - 훅 3곳의 `json.load(sys.stdin)` (`wiki-protect-raw.sh:29`·`wiki-validate-frontmatter.sh:22`·`session-start:78`) — stdin은 locale 인코딩이라 한글 경로가 든 페이로드에서 예외 → `except`로 흘러 **가드가 조용히 통과**한다.
    - 이미 옳은 곳: `scripts/validate-frontmatter.sh:43`·`scripts/build-link-graph.sh:105`·`session-start`의 SKILL 읽기는 `encoding="utf-8"`을 지정한다 — 규칙이 있는데 세 곳이 빠진 상태다.
    - **수정 순서에 의존이 있다:** 인코딩을 고쳐도 **아래 경로 가정 문제를 먼저 닫지 않으면 Windows에서 검증되지 않는다**(resolver가 그 앞에서 실패한다). 그래서 이 항목은 경로 픽스처 다음이다. 로컬(UTF-8 locale)에서는 증상이 나타나지 않으므로 회귀 테스트는 CI에서만 유효하다.
  - **`bash-suite`의 `test-resolve-vault.sh`가 Windows에서 매달린다 (2026-08-04, 세 번째 발견 · 미해결).** 좁힌 범위와 **기각된 가설**을 남긴다 — 다음 사람이 같은 곳을 다시 파지 않게.
    - **확정:** 매달리는 스위트는 `tests/scripts/test-resolve-vault.sh`다(직전 스위트 `test-build-link-graph.sh`가 `rc=0`으로 끝난 뒤 END 라인이 오지 않는다). macOS/Linux에서는 전부 통과한다.
    - **기각 ①:** "PATH 단독 좁히기(python3 은닉)가 MSYS에서 성립하지 않아서" — 그럴듯했고(그 기법은 이 CI에서 **처음** 실행됐다. PR #15의 CI는 `E_NO_RUNTIME` 머지 전 브랜치였다) MSYS의 `ln -s`가 복사본을 만드는 것도 사실이지만, **MSYS 스킵 가드를 넣어도 여전히 매달렸다.** 가드는 유지한다(그 플랫폼에서 검증 대상이 아닌 것은 맞다).
    - **기각 ②:** "ASCII locale 재현 env(`LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0`) 조합 자체가 원인" — **같은 env를 쓰는 `test-build-link-graph.sh`는 통과한다**(PASS 15).
    - **기각 ③:** "스위트 내용이 아니라 `run.sh` 경유 방식(stdin 상속·버퍼링)" — 스위트를 단독으로 돌린 진단 스텝이 한 번 success로 끝나 이 가설을 세웠으나, 개별 상한을 걸어 재실행하니 다시 매달렸다. 첫 성공은 재현되지 않았다.
    - **남은 후보:** 한글 디렉터리 경로(`$SANDBOX/work/한글볼트`) 생성·접근이 MSYS에서 매달리는 경우, 또는 그 경로와 위 env의 **조합**. `test-session-start.sh`도 한글 볼트를 만들지만 순서상 아직 도달하지 못했다.
    - **다음 단계:** 케이스 단위 이분 탐색(스위트를 케이스별로 쪼개 개별 실행). 지금은 CI 사이클당 10~20분이 들어 비용이 크므로 별도 항목으로 둔다.
    - **진단 도구에서 배운 함정:** `timeout 120 … | tail -40`은 **timeout을 무의미하게 만든다** — 스위트를 죽여도 손자 프로세스가 파이프를 붙잡으면 `tail`이 EOF를 못 받아 거기서 다시 매달린다. 출력은 파일로 받고 끝난 뒤 읽는다.
  - **(이전 관측) `tests/run.sh` 경유의 로그 가시성 문제.** 0.3.1 인코딩 수정으로 이전보다 더 진행되면서 스텝이 끝나지 않았다(12분+ → 강제 취소). **같은 스위트를 단독으로 돌리면 통과한다** — 즉 스위트 내용이 아니라 `run.sh` 경유 방식의 문제다(stdin 상속 또는 출력 버퍼링이 의심). `run.sh`가 각 스위트 출력을 파일로 리다이렉트하는 탓에 로그의 마지막 `PASS` 라인으로 지점을 추론했다가 **틀렸다** — 그 라인은 버퍼 플러시 타이밍일 뿐이었다. 대응: ① 잡·스텝 `timeout-minutes` 도입(정보용 갈래가 매달려 CI 신호를 붙잡는 것은 별개의 위생 문제다), ② 스위트를 `timeout 120 … </dev/null`로 **개별 실행**해 매달리는 스위트를 `rc=124`로 지목하고 나머지는 계속 진행. `run.sh` 자체 수정은 별도 항목이다 — **로컬(macOS/Linux)에서는 문제가 없다.**
  - **첫 실행 결과 (2026-08-04) — `bash-suite` 실패, 나머지 원인은 테스트 하네스의 경로 가정이다.** `test-resolve-vault.sh`가 `mktemp -d`로 만든 **MSYS POSIX 경로**(`/tmp/tmp.XXXX`)를 `.wiki-config.json`의 `vault.path`에 적는데, Git Bash가 아니라 **Windows native python3**가 그 문자열을 받으므로 `os.path.isdir("/tmp/…")`가 false가 되어 `ERR PATH` → `E_INVALID_CONFIG`로 떨어진다(같은 이유로 `E_VERSION`·`E_NOT_A_VAULT` 케이스도 4로 오분류된다 — 경로 검증이 그 앞이다). **resolver 코드의 Windows 결함이 아니다** — 실사용에서 Windows 사용자의 `vault.path`는 `C:\…` 형식이고 native python3가 정상 해석한다. 닫는 방향은 테스트 픽스처가 `cygpath -w` 등으로 플랫폼 경로를 쓰는 것이며, **별도 항목으로 분리**한다(이 CI를 도입한 목적인 cmd.exe 갈래와 무관하다). 다만 남는 진짜 질문 하나: resolver가 POSIX 경로 config를 받았을 때의 진단이 `E_INVALID_CONFIG`인 것은 맞으나 메시지가 "경로 형식이 플랫폼과 어긋난다"를 지목하지 못한다 — Windows 사용자가 실제로 이 상태에 빠질 경로(Git Bash에서 `pwd` 결과를 그대로 붙여넣는 경우)가 있으므로 함께 다룬다.
  - **첫 CI가 잡은 진짜 결함 — `run-hook.cmd`는 LF-only로는 Windows에서 아예 동작하지 않았다 (2026-08-04).** cmd.exe는 **LF-only 배치의 줄 경계를 잡지 못해** 파일을 중간부터 오해석한다. 실측 로그에서 한글 주석 조각("라벨과", "의", "은")과 코드 조각(`"SCRIPT=_dbg.sh"`, `ect_args`, `nul`)이 각각 **별개 명령으로 실행**되며 런처가 exit 1로 죽었다 — 같은 `bash`를 직접 호출하면 정상이었으므로 원인은 런처 파싱이다. 즉 인자 전달 로직(Phase 2 T5)이 맞았어도 Windows 사용자에게 이 런처는 처음부터 깨져 있었다. **정적 검토로는 발견할 수 없는 종류**이고, 이 CI를 도입한 근거가 그 자체로 증명됐다.
  - **해법은 CRLF + `' #'` 한 쌍이다.** `.gitattributes`가 `run-hook.cmd`를 `eol=crlf`로 배포한다(순수 배치 테스트도 동일). 그런데 이 파일은 bash에서도 실행되는 폴리글랏이라 CR이 그냥 들어가면 Unix 분기가 `shift\r` 같은 토큰을 실행하려다 죽으므로, `:;` 실행 줄 끝에 **` #`을 달아 CR을 주석으로 흡수**시킨다. **둘 중 하나만 있으면 한쪽 플랫폼이 조용히 깨진다** — `tests/hooks/test-session-start.sh`가 CR 존재와 `' #'` 누락을 둘 다 검사해 계약을 고정한다. `session-start`·`*.sh`는 bash 전용이라 LF 유지. install.sh는 symlink 배포라 줄바꿈을 변형하지 않는다.
- ~~**Phase 3에서 새로 열린 검증 항목**~~ — **대부분 해결(2026-08-01 Phase 3b, [리포트](../reports/2026-08-01-phase3b-e2e-5skills.md)):**
  - ~~§1 시나리오 나머지 5스킬~~ → **완주.** `wiki-status`·`wiki-knowledge`·`wiki-project-{init,design,record}` 전부. change proposal 전 주기(proposed→승인→병합→`decisions.md` 짝→archive 박제)와 `decisions.md` append-only 불변성까지 확인. 9/12스킬 커버.
  - ~~Claude의 SessionStart 규칙 주입~~ → **확인.** 볼트 안 CWD에서 7961자 주입(포맷·래핑·frontmatter 제거·규칙 포함), 볼트 밖에서 stdout 0바이트.
  - ~~QMD refresh 실행 경로~~ → **확인.** `update`→`embed`→`get` 전 구간. 사용자 레지스트리가 착수 시 컬렉션 0개였으므로 등록·제거로 오염 0을 달성했다.
  - ~~`wiki-query` index-only · `wiki-lint --fix`~~ → **확인.** dry-run→`--yes` 수리 2건, LINT 17필드 라인.
  - **Cursor 전역 경로**(`install.sh --fallback` → `~/.cursor/hooks.json`) — **여전히 열림.** 전역 오염을 피해 프로젝트-로컬(`--vault`)만 검증.
  - **`ingest-url`·`wiki-capture`** — 범위 밖으로 남았다(12스킬 중 3종 미검증).
- **쓰기 종료 시퀀스 순서를 기계적으로 강제하는 것이 없다** (Phase 3b 신규 발견) — 산문 규칙만 있고 훅·테스트가 검사하지 않아 잘못된 순서가 조용히 통과한다. mtime은 판정 근거로 약하고 훅은 stateless라 설계가 필요하다 — `docs/superpowers/specs/2026-08-01-phase2-deferred-design.md` §4로 이관.
