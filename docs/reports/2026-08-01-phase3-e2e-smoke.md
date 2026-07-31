# Phase 3 E2E·4플랫폼 스모크 검증 리포트

**실시일:** 2026-08-01
**대상:** `origin/master` (검증 중 `9dc9928`까지 진행)
**환경:** macOS 25.3.0 · Claude Code(마켓플레이스) · codex-cli 0.146.0 · cursor-agent 2026.07.23-e383d2b · agy 1.1.8 · qmd 2.5.3 · python3 · bash 3.2

이 문서는 **무엇을 실제로 실행해 확인했고, 무엇을 확인하지 못했는지**를 남긴다. "동작할 것이다"는 서술은 넣지 않는다 — 근거 없는 항목은 [미검증](#5-미검증-항목-정직한-목록)으로 분류했다.

---

## 1. 한 줄 결론

**의도대로 동작한다 — 단 결함 4건을 고친 뒤부터다.** 그중 하나(`hooks-codex.json`의 `_comment`)는 **Codex에서 훅 3종이 전부 죽어 있던** 것으로, 설치는 성공하고 `codex plugin list`도 `installed, enabled`로 보였기 때문에 스모크를 돌리지 않았다면 발견되지 않았다.

| 축 | Claude Code | Codex 0.146.0 | cursor-agent | Antigravity 1.1.8 |
|---|:--:|:--:|:--:|:--:|
| 스킬 로드 | ✅ 12개 (`llm-wiki-harness:` 네임스페이스) | ✅ 규칙 준수로 확인 | ✅ 규칙 준수로 확인 | ➖ 배치만 확인 |
| SessionStart — 런타임 부트스트랩 | ✅ | ✅ | ➖ 미측정 | ✖ 훅 없음 |
| SessionStart — 규칙 주입 | ➖ 미측정 | ✅ | ✅ (AGENTS.md 경유) | ✖ 훅 없음 |
| PreToolUse — `raw/` 차단 | ✅ | ✅ (수정 후) | ✅ | ✖ 훅 없음 |
| PostToolUse — frontmatter 검증 | ✅ | ➖ 미측정 | ➖ 미측정 | ✖ 훅 없음 |

✅ 실행해 확인 · ➖ 미측정 · ✖ 구조적으로 불가

Antigravity는 **훅 스키마가 미공개**라 기계적 차단이 원래 없다 — `raw/` 보호는 `AGENTS.md` 소프트 룰이 담당한다(설계 의도).

---

## 2. 검증 방법 — 왜 이 결과를 신뢰할 수 있나

- **격리:** 볼트는 임시 디렉토리(`$CLAUDE_JOB_DIR/tmp/e2e/vault`). 훅이 `$HOME/.llm-wiki/scripts`를 하드코딩하므로 스크립트 단위 검증은 **가짜 HOME**을 만들어 `HOME=<sandbox>`로 호출했고, 전역 포인터 대신 CWD-upward 탐색으로 resolve해 실환경 오염을 0으로 유지했다.
- **실환경을 쓴 구간**(플랫폼 스모크)은 착수 전 상태를 파일로 스냅샷하고 종료 후 6개 지점을 대조·원복했다.
- **단정하지 않고 계측했다.** Codex 결함을 처음 만났을 때 "sandbox가 `~/.llm-wiki` 읽기를 막았을 것"이라는 그럴듯한 가설이 있었으나, 훅에 경계별 로그(B0 진입 → B1 resolver → B2/B3 payload → B4 판정 → B5 종료)를 심어 **B0조차 도달하지 않음**을 먼저 확인했다. 가설은 틀렸고 원인은 상위 레이어였다.
- 픽스처를 남긴 뒤에는 볼트 해시를 재대조해 잔여물 0을 확인했다.

---

## 3. 스킬이 내용대로 처리되는가

### 3-1. §1 시나리오 — `wiki-setup` → `wiki-ingest` → `wiki-query` → `wiki-lint`

| 검증 | 기대(스펙) | 실측 |
|---|---|---|
| `wiki-setup` 산출물 | config 5키 · 고정 서브디렉토리 · index/log/hot · manifest · example | 11개 전부 생성 |
| Config Gate | exit 0 + `VAULT_PATH`/`WIKI_DIR`/`RAW_DIR` | 일치 |
| 입력 경로 하드 가드 | `realpath` 정규화로 `../` 탈출 차단 | `raw/../wiki`·`raw/../../../etc` 둘 다 차단 |
| `wiki-ingest` 산출물 | summaries 1:1 미러 + concepts, manifest 동형 스키마, index 표, INGEST 라인, hot | 페이지 3개 · manifest 8필드(`sha256:`+64hex) · index 표 · log 1줄 · hot 갱신 |
| 링크 품질 | 신규 페이지마다 `[[link]]` ≥2, 고아 0 | `orphans=0 broken=0 rel_broken=0 rel_self=0` |
| **쓰기 종료 시퀀스 순서** | 페이지 → index → log → hot (원본 먼저) | mtime 오름차순 **7/7 정확히 일치** |
| `wiki-query` 답변 포맷 | `> 위키 기반:` / `참고 페이지:` / `공백:` (한국어) | 준수 + `section grep`/`found in summary` 단계 라벨 |
| `wiki-query` read-only 경계 | `log.md`만 변경 | 파일 10개 해시 대조 → `wiki/log.md` **단독** 변경 |
| `wiki-lint` 계수 | 17항목 전부 | T=1(`unverified`만), 나머지 16개 0 |
| `wiki-lint` LINT 라인 | 17필드 + `source_drift`(구 `stale` 아님) | 17/17, `stale` 키 부재 |
| `wiki-lint` report-only | log만, hot·QMD 무수정 | `log.md` 단독 변경 |
| **4자 일관성** | 디스크 ↔ `index.md` ↔ `.manifest.json` ↔ `log.md` | 4/4 일치 |

### 3-2. 스킬 규칙이 각 에이전트에서 실제로 지켜지는가

행동으로 확인된 것만 적는다.

- **Claude** — 스킬 12개가 `llm-wiki-harness:wiki-setup` 형태로 로드됐다. 이 세션의 에이전트가 스킬 워크플로를 그대로 수행해 위 3-1 표를 산출했다.
- **Codex** — SessionStart 주입 후 `raw/` 쓰기를 지시했을 때 **에이전트가 스스로 거부**하며 근거를 인용했다: "`raw/` 아래 파일은 wiki 규칙상 불변 소스 영역이라 생성·수정·삭제할 수 없습니다." 주입된 `using-llm-wiki`가 읽히고 준수됐다는 뜻이고, 동시에 **T4의 Codex 출력 포맷 수정(`hookSpecificOutput.additionalContext`)이 실제로 동작함**을 증명한다(구 `additional_context`는 `SessionStart Failed`로 주입 무효였다).
- **cursor-agent** — 같은 지시에 `AGENTS.md`를 원문 인용하며 거부했다: "`raw/` 는 불변. raw/ 아래를 생성·수정·삭제하지 않는다 — 사용자가 명시적으로 요청해도." 비-Claude 도구용 미러가 의도대로 로드된다.
- **Antigravity** — 파일 배치만 확인했다(아래 4-4). 실제 로드·준수는 **미검증**.

> 소프트 룰이 잘 듣는 것은 좋은 신호지만, 그 때문에 기계 가드가 시험되지 않는다. Codex·Cursor의 PreToolUse는 **소프트 룰을 일부러 걷어내고**(AGENTS.md 이동 + sessionStart 비활성화) 격리해 확인했다.

---

## 4. 훅이 의도대로 처리되는가

### 4-1. Claude Code — 마켓플레이스

- **PreToolUse:** 이 세션의 에이전트가 `{vault}/raw/articles/ai-ml/should-be-blocked.md` 쓰기를 시도해 **실제로 차단당했다.**
  ```
  PreToolUse:Write hook error: [${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd wiki-protect-raw.sh claude]:
    raw/는 읽기 전용입니다 (수정 금지). 삭제는 wiki-lint --fix를 경유하세요.
  ```
  파일 미생성을 확인했다(차단이 실효적).
- **PostToolUse:** 필수 키 4개를 뺀 페이지를 쓰자 `필수 키 누락: tags / sources / status / base_confidence`를 보고했고, 채워 다시 쓰자 무소음 통과했다. 설계 의도(파일은 쓰이고 훅이 즉시 피드백 → 에이전트가 고침)대로다.
- **SessionStart ① 부트스트랩:** 설치 전 `~/.llm-wiki/` 미존재 → 설치 후 `scripts/` 생성. symlink 3개가 플러그인 캐시를 가리키고 `cmp` 일치.
- **등록 메커니즘 — 문서와 다르다.** 설치본 `.claude-plugin/plugin.json`에 **`hooks` 키가 없고**(PR #3에서 "중복 선언"으로 제거) `~/.claude/settings.json`에도 훅 이벤트가 없는데, 차단 메시지의 command가 `hooks/hooks.json`의 문자열 그대로였다. 즉 **Claude Code는 플러그인 루트의 `hooks/hooks.json`을 관례로 탐색한다.** `docs/specs/hooks-and-scripts.md`의 "plugin.json이 이 파일을 가리켜 등록"이라는 서술은 정정 대상이다. PR #3의 판단(선언과 관례 파일이 둘 다 있으면 중복)은 옳았다.

### 4-2. Codex CLI 0.146.0 — 마켓플레이스

**착수 시 훅 3종이 전부 죽어 있었다.** `codex plugin add`는 성공하고 `plugin list`는 `installed, enabled`, `features`에 `CodexHooks`도 있는데 `raw/` 쓰기가 그냥 통과했다. 원인:

```
warning: failed to parse plugin hooks config .../hooks/hooks-codex.json:
         unknown field `_comment`, expected `description` or `hooks` at line 2 column 12
```

`_comment`를 제거한 뒤 전 구간이 통과했다. 경계 로그:

```
B0 ENTER  argv=[codex]  PWD={vault}
          PLUGIN_ROOT=~/.codex/plugins/cache/llm-wiki-harness/llm-wiki-harness/0.1.0
B1 resolver exit=0  VAULT_PATH={vault} WIKI_DIR=wiki RAW_DIR=raw
B3 payload  hook_event_name=PreToolUse  tool_name=apply_patch
            tool_input.command="*** Begin Patch\n*** Add File: raw/articles/ai-ml/codex-probe.md\n…"
B4 DECISION=[block]
B5 BLOCKING platform=codex        →  hook: PreToolUse Blocked  →  파일 미생성
```

이 한 번의 통과로 T2·T3(cwd 상대경로 해석 + `apply_patch` 패치 본문에서 대상 추출)·T6(`${PLUGIN_ROOT}` 절대참조)·§5-4 payload 계약이 동시에 확인됐다.

부수 실측 2건:
- **trust 미완 시 무경고 no-op 재현** — trust 없이 실행하면 `raw/` 쓰기가 경고 없이 성공한다. 파싱 실패와 **증상이 완전히 동일**해 구분 수단이 `grep 'failed to parse'` 뿐이다.
- **이중 발화** — 플러그인 훅과 프로젝트-로컬 `{vault}/.codex/hooks.json`을 병합한다. 설정 파일을 빼고/넣어 SessionStart **1회 → 2회**를 확인했다.

### 4-3. cursor-agent 2026.07.23

프로젝트-로컬 경로(`install.sh --vault`)로 검증했다. `preToolUse`가 발화하고 payload가 §5-4 계약과 일치했다:

```
B0 ENTER  argv=[cursor]  PLUGIN_ROOT=unset
B3 payload  hook_event_name=preToolUse  tool_name=Write  cursor_version=2026.07.23-e38…
            tool_input.file_path={vault}/raw/articles/ai-ml/cursor-probe.md   ← 절대경로
B4 DECISION=[block]        →  에이전트: "생성·수정이 금지되어 있어 파일을 만들 수 없었습니다"
```

같은 세션의 두 번째 발화는 `tool_name=Shell`, `command="bash ~/.llm-wiki/scripts/resolve-vault.sh"` → `DECISION=[allow]`. **raw/ 무관 호출은 통과**한다(오탐 없음).

`cursor_version` 키가 payload에 실제로 있음이 확인돼, T4가 "argv가 아니라 `cursor_version`으로 플랫폼을 판정한다"고 넣은 방어가 유효하다.

### 4-4. Antigravity 1.1.8

훅 스키마 미공개로 기계적 차단이 **구조적으로 없다.** `install.sh`가 배치한 것만 확인했다:

| 항목 | 결과 |
|---|---|
| `~/.gemini/config/plugins/llm-wiki-harness/plugin.json` | 존재 · 레포 소스와 `cmp` 일치 → **T8(heredoc → 레포 소스 승격) 검증** |
| `skills/` symlink | 12개 |
| `rules/llm-wiki.md` | → `AGENTS.md` |
| `hooks.json` | **부재(의도)** |
| `~/.gemini/config/AGENTS.md` | 생성됨 |

### 4-5. `install.sh` 비파괴 정책 (T7)

기존 `{vault}/.codex/hooks.json`이 있는 상태로 재실행하니 원본을 보존하고 `hooks.llm-wiki.json` 사본을 옆에 두고 머지를 안내했다 — T7 정책이 실제로 동작한다. 부작용도 확인했다: **하네스가 갱신돼도 기존 설정 파일은 자동으로 안 바뀐다**(사용자가 사본과 수동 머지해야 한다).

---

## 5. 미검증 항목 (정직한 목록)

| # | 항목 | 왜 못 했나 |
|---|---|---|
| 1 | **§1 시나리오 나머지 5스킬** — `wiki-status`·`wiki-knowledge`·`wiki-project-init`·`wiki-project-design`·`wiki-project-record` | 요청 범위 밖. project 3종은 인터뷰·승인이 정의상 필수 |
| 2 | **Codex·Cursor의 PostToolUse**(frontmatter 검증) | PreToolUse 차단만 시험했다. 등록은 확인됐으나 발화는 미측정 |
| 3 | **Claude의 SessionStart 규칙 주입** | 세션 CWD가 볼트 밖이라 게이트가 의도대로 no-op 했다(부트스트랩 ①만 확인) |
| 4 | **Cursor 전역 경로**(`install.sh --fallback` → `~/.cursor/hooks.json`) | 전역 오염을 피해 프로젝트-로컬(`--vault`)만 검증 |
| 5 | **Antigravity의 실제 로드·준수** | 파일 배치만 확인. agy가 skills·rules를 읽는지는 행동으로 미확인 |
| 6 | **QMD refresh 실행 경로** | 컬렉션을 등록하지 않아(사용자 레지스트리 오염 회피) 게이트 ② 실패 → Grep fallback 경로만 확인 |
| 7 | **Windows**(`run-hook.cmd` cmd.exe 분기) | macOS에서 cmd.exe 실행 불가. 정적 검토만 (Phase 2 T5 이래 계속 열림) |
| 8 | **`wiki-query` index-only 모드** · **`wiki-lint --fix`** | normal 모드·report-only만 실행 |

---

## 6. 발견해 고친 결함 4건

| # | 결함 | 심각도 | 조치 |
|---|---|:--:|---|
| 1 | **`hooks-codex.json`의 `_comment`가 Codex strict 스키마를 위반**해 훅 3종이 전부 no-op | 🔴 | `description`으로 교체 + `tests/hooks/test-hook-config-schema.sh` 신설 (PR #6) |
| 2 | **인라인 flow 시퀀스 `relationships: [{…}]`가 표기 가드와 `type` enum 검사를 동시 우회** — 파서의 `[ ]` 분기가 문자열 리스트를 돌려주므로 `isinstance(list)`를 통과하고, 그 상태에서 `isinstance(r, dict)` 게이트가 무발화한다. 2026-07-31에 `provenance`만 닫히고 남아 있던 케이스 | 🔴 | 원소가 전부 매핑인지까지 검사 (PR #5) |
| 3 | **클래스② 판정이 경로의 아무 세그먼트나 매칭** — 스펙이 허용하는 `knowledge/api/changes/`를 오판해 정상 페이지를 거부 | 🟡 | `projects` 손자 위치 인접성으로 한정 (PR #5) |
| 4 | **`wiki/meetings/` 폐지(2026-07-31) 미반영 3곳** — `wiki-setup`이 여전히 생성했다. `category` enum에 대응 값이 없어 훅이 무조건 차단하는 빈 폴더가 매 setup마다 생기는 상태 | 🟡 | `wiki-setup` 2곳·`wiki-ingest` 1곳 정정 (PR #5) |

회귀 테스트는 141 → **161 assertion**으로 늘었다.

## 7. 문서에 반영한 실측 3건

전부 "조용히 무방비가 되는" 부류라 증상만으로 원인을 구분할 수 없어 `docs/troubleshooting.md`에 기록했다: 훅 설정 파싱 실패(trust 미완과 증상 동일) · Codex 이중 발화 · `~/.llm-wiki/scripts` 소유권 경합(마켓플레이스 부트스트랩은 플러그인 캐시, `install.sh`는 자기 체크아웃 — 나중 실행이 이긴다. 임시 클론에서 돌리면 지울 때 가드가 fail-open으로 사라진다).

## 8. 남은 정정 대상

- ~~`docs/specs/hooks-and-scripts.md` — Claude 훅 등록 메커니즘 서술~~ → **이 리포트와 같은 커밋에서 정정 완료**(관례 탐색임을 명문화 + `hooks` 키를 두지 않는 이유 기재).
- `README.md`·`resolve-vault.sh`의 `E_*` 안내가 스킬을 `/wiki-setup`처럼 **접두어 없이** 표기(약 10곳). 플러그인 설치 시엔 `/llm-wiki-harness:wiki-setup`이라 틀리고, `install.sh` 폴백 설치 시엔 맞다 — 어느 쪽으로 통일해도 반쪽이 틀어져 판단이 필요하다.

## 9. 재현 방법

```bash
# 스크립트·훅 단위 (실환경 무오염)
bash tests/run.sh                                    # 161 assertion

# 격리 볼트 E2E — 가짜 HOME + CWD-upward resolve
#   1) $TMP/vault 에 .wiki-config.json·wiki/{index,log,hot}.md 생성
#   2) $TMP/fakehome/.llm-wiki/scripts/ 에 scripts/*.sh 배치
#   3) HOME=$TMP/fakehome 로 훅 호출, cwd 는 볼트 안

# 플랫폼 스모크 — master 에 머지된 뒤에만 가능(마켓플레이스가 기본 브랜치를 클론)
/plugin marketplace add junojun5/llm-wiki-harness && /plugin install llm-wiki-harness
codex plugin marketplace add junojun5/llm-wiki-harness
codex plugin add llm-wiki-harness@llm-wiki-harness    # + /hooks 에서 trust
bash install.sh --vault <vault>                        # Cursor 필수
bash install.sh                                        # Antigravity

# Codex 훅 진단 (가드가 안 도는데 원인을 모를 때)
RUST_LOG=warn codex exec … 2>&1 | grep -E 'hook:|failed to parse'
```
