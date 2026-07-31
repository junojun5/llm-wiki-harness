# hooks/ · scripts/ 파일 레퍼런스

`hooks/`와 `scripts/`에 있는 각 파일이 **무엇을 하는지**에 대한 인벤토리다.
*왜* 그렇게 설계했는지(근거·트레이드오프)는 `docs/spec.md`(하네스 스펙 §3·§5)·`docs/distribution-design.md`(멀티플랫폼 배포)가 단일 출처다.

---

## `scripts/` — 결정론적 검증 로직

도구 비종속. install.sh가 `~/.llm-wiki/scripts/`로 symlink(마켓플레이스는 첫 SessionStart가 부트스트랩)하며, 4개 플랫폼이 이 한 경로만 참조한다. 마크다운 프롬프트로는 exit code·정밀 검증 같은 기계적 보장이 불가능해 코드로 뺀 부분이다.

| 파일 | 역할 | 호출 주체 |
|---|---|---|
| **`resolve-vault.sh`** | **Config Gate.** CWD에서 위로 `.wiki-config.json` 탐색 → 없으면 `~/.llm-wiki/default-vault` 포인터 → 파싱·검증·볼트 서명(`wiki/index.md`·`log.md`) 확인 → `VAULT_PATH`/`WIKI_DIR`/`RAW_DIR`를 stdout에 출력. 실패는 exit code 6종(`E_NO_CONFIG`=2·`E_BAD_POINTER`=3·`E_INVALID_CONFIG`=4·`E_VERSION`=5·`E_NOT_A_VAULT`=6) + stderr 첫 줄 `E_CODE: 메시지`. **상태 미저장 — 매 호출 fresh resolve.** (스펙 §3-2) | 모든 스킬 Step 0 + 모든 훅 |
| **`validate-frontmatter.sh`** | frontmatter **기계 규칙** 검증. 파일 경로/category로 문서 클래스 ①②③를 판정한 뒤 클래스별 필수 키·enum(category/status/tier/relationship type)·날짜 형식·`summary`≤400자·`base_confidence` 0–1·provenance 합≈1을 검사. 클래스 ③(index/log/hot·decisions·backlog)은 통과. 의미적 품질은 검사하지 않음(LLM+wiki-lint 몫). (스펙 §3-3) | PostToolUse 훅 + `wiki-lint` |
| **`build-link-graph.sh`** | wiki 전체를 **1회 O(N) 패스**로 스캔해 링크 그래프 산출 — 고아 페이지(inbound 0)·깨진 `[[링크]]`·개념 갭·typed relationship 타깃 부재/자기참조를 한 번에 낸다. 파일당 grep(O(N×M)) 금지. index/log/hot은 스캔·inbound에서 제외. (스펙 §4-6) | `wiki-lint`(체크 1·2·9·12) |

---

## `hooks/` — 이벤트 스크립트 + 플랫폼별 등록

### 실행되는 훅 (bash — 로직은 3개 파일이 공유, 등록만 플랫폼별)

| 파일 | 이벤트 | 하는 일 |
|---|---|---|
| **`session-start`** | SessionStart | **① 부트스트랩(자가치유):** `~/.llm-wiki/scripts`가 없으면 배포본(플러그인 루트/repo)의 `scripts/`에서 symlink 생성 → 마켓플레이스만으로도 공유 경로가 채워진다. **② 주입:** CWD가 **볼트 안일 때만** `using-llm-wiki/SKILL.md`를 `<EXTREMELY_IMPORTANT>` 래핑해 컨텍스트로 주입(볼트 밖 세션엔 주입 안 함 = 스팸 방지). 플랫폼 인자(claude/codex/cursor)별 stdout JSON. (스펙 §5-1) |
| **`wiki-protect-raw.sh`** | PreToolUse | raw/ **수정 차단**(삭제 `rm`은 허용 — cleanup 정책용). resolve-vault로 진짜 볼트를 판정하고, 대상 경로가 볼트 `raw/` 밖이면 통과(비볼트·타 프로젝트 오탐 0). 차단 신호는 플랫폼별: claude/codex=stderr+exit 2, cursor=`{"permission":"deny"}`+exit 0. accident-prevention 수준(적대적 우회는 비목표). (스펙 §5-2) |
| **`wiki-validate-frontmatter.sh`** | PostToolUse | 볼트 `wiki/*.md` 쓰기면 `validate-frontmatter.sh`에 위임하는 **얇은 wrapper**. 위반 시 stderr + exit 2(에이전트가 피드백 받아 수정). 위반 0이면 무출력. (스펙 §5-3) |

### 런처·개발 도구

| 파일 | 역할 |
|---|---|
| **`run-hook.cmd`** | **폴리글랏 런처** — Unix(bash)·Windows(cmd.exe) 양쪽에서 동작. `run-hook.cmd <script> [platform]` → `bash <hookdir>/<script> [platform]`로 위임(자기 위치를 `$0`로 찾음). 세 플랫폼이 모두 이걸 경유해 훅 스크립트를 부르되 command 표기가 갈린다 — Claude `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd`, Codex `${PLUGIN_ROOT}/hooks/run-hook.cmd`(둘 다 플러그인 매니페스트가 자동 등록), Cursor는 `install.sh`가 `{{HOOKS_DIR}}`를 실제 설치 절대경로로 render한다(플러그인 자동 등록이 불가하므로 self-locating 상대경로 전제가 성립하지 않는다 — 2026-07-31 실측). Windows 네이티브 에이전트가 `.sh`를 직접 못 돌릴 때 Git Bash/WSL bash로 넘긴다. |
| **`probe-hook.sh`** | **픽스처 캡처 도구**(개발용). 훅 이벤트의 raw stdin 페이로드·argv를 파일로 저장하고 항상 통과(exit 0). Codex/Cursor의 실제 stdin/stdout 스키마를 실측해 골든 픽스처로 확보하기 위한 것. 평상시 훅 등록에는 쓰지 않는다. (배포 설계 §9-6) |

### 플랫폼별 등록 JSON (같은 bash 로직을 각 플랫폼 형식으로 등록)

| 파일 | 대상 | 내용 |
|---|---|---|
| **`hooks.json`** | Claude (플러그인) | `.claude-plugin/plugin.json`이 이 파일을 가리켜 마켓플레이스 설치 시 자동 등록. SessionStart·PreToolUse·PostToolUse 3종을 `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd` 경유로 등록 → **install.sh 없이 동작**. `--fallback`(수동)은 `${CLAUDE_PLUGIN_ROOT}`를 `~/.claude`로 치환한 스니펫을 만들어 `~/.claude/settings.json` 머지를 안내. |
| **`hooks-codex.json`** | Codex (플러그인) | `.codex-plugin/plugin.json`의 `hooks` 키가 가리켜 `/plugins` 설치 시 등록. SessionStart·PreToolUse(`apply_patch` 포함)·PostToolUse를 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/run-hook.cmd` 경유로 등록. **플러그인 번들 훅은 non-managed** → 최초 1회 `/hooks` **trust** 필요(비Windows). trust 미완 시 **무경고 no-op**. `config.toml [features] hooks=true`는 0.145.0에서 **불필요**하다(stable·기본 활성으로 승격). `--fallback`/`--vault`는 `${PLUGIN_ROOT..}`를 실제 절대경로로 render해 `~/.codex/hooks.json`·`{vault}/.codex/hooks.json` 생성. ⚠️ **최상위 키는 `description`·`hooks` 둘만 허용된다** — Codex는 이 파일을 strict 역직렬화하므로 `_comment` 같은 추가 키가 있으면 파일 **전체 파싱이 실패**하고 경고 한 줄만 남긴 뒤 **훅 0개로 진행**한다(2026-08-01 실측, 0.146.0). 설치는 성공하고 `codex plugin list`도 `installed, enabled`로 보이므로 조용히 무방비가 된다. Claude·Cursor는 `_comment`를 관용하지만 이 파일에는 넣지 않는다 — `tests/hooks/test-hook-config-schema.sh`가 강제. |
| **`hooks-cursor.json`** | Cursor (설정 파일 배치) | ⚠️ **플러그인 경유 자동 등록은 불가**(cursor-agent가 매니페스트 `hooks`를 소비하지 않음 — 2026-07-31 실측). `install.sh --fallback`이 `~/.cursor/hooks.json`, `--vault`가 `{vault}/.cursor/hooks.json`으로 절대경로 render해 배치한다. camelCase 이벤트(`sessionStart`/`preToolUse`/`postToolUse`) + JS 정규식 matcher. 도구명은 `Write`·`Edit`·`Shell`(대문자 S). 차단 출력 `{"permission":"deny","user_message":…}` + `exit 0`. sessionStart 주입은 `{"additional_context":…,"env":{…}}`. ⚠️ Cursor는 훅 설정을 7개 소스에서 **병합**하며 `~/.claude/settings.json`·`{ws}/.claude/settings.json`도 실행하므로, 같은 훅을 Claude 설정과 중복 등록하면 **2회 발화**한다 — 경로를 분리해 유지한다. Cloud Agent는 sessionStart 미지원. |

### 설정 템플릿

| 파일 | 역할 |
|---|---|
| **`cursor-sandbox.template.json`** | Cursor sandbox 권한. 기본 `workspace_readwrite`는 워크스페이스 밖 R/W를 막아 `~/.llm-wiki/scripts/` 호출이 실패할 수 있으므로 `~/.llm-wiki`·볼트 경로를 `additionalReadwritePaths`에 추가. `{{VAULT_ABS}}`는 install.sh가 실제 볼트 절대경로로 치환. (배포 설계 §13-6) |

---

## 한눈에 보는 관계

```
scripts/  = "무엇이 참인가"를 결정론적으로 판정 (resolve / validate / graph)
            → 4개 플랫폼이 ~/.llm-wiki/scripts 한 경로로 공유
hooks/    = 그 판정을 이벤트에 물려 자동 실행
   ├─ 로직(bash 3): session-start · wiki-protect-raw · wiki-validate-frontmatter
   ├─ 런처·도구:    run-hook.cmd(OS 위임) · probe-hook.sh(픽스처 캡처)
   └─ 등록 JSON 3:  hooks.json(Claude) · hooks-codex.json(Codex) · hooks-cursor.json(Cursor)
                    — Claude·Codex는 플러그인 매니페스트가 가리켜 설치 시 자동 등록,
                      Cursor는 install.sh가 설정 파일로 배치(매니페스트 hooks 미소비 — 필수)
                      Antigravity는 훅 스키마 미공개로 제외
                    + cursor-sandbox.template.json(Cursor sandbox 권한)
```

**게이팅 요약:** 주입(session-start)은 **CWD가 볼트 안일 때만**, 보호(가드 훅)는 **경로가 볼트 `raw/`·`wiki/` 안일 때만**, 부트스트랩(session-start ①)은 **항상**(멱등). 볼트 미설정 머신에선 resolve-vault 실패로 전부 조용한 no-op.

**실기 검증 상태 (2026-08-01, Phase 3 E2E):**

| 플랫폼 | 설치 경로 | 기계적 차단 실측 |
|---|---|---|
| Claude Code | 마켓플레이스 (`/plugin install`) | ✅ `raw/` 쓰기 `exit 2` 차단 · PostToolUse가 누락 키 4건 보고 · SessionStart가 `~/.llm-wiki/scripts` 부트스트랩 |
| Codex CLI 0.146.0 | 마켓플레이스 (`codex plugin add`) | ✅ `apply_patch` 상대경로 차단(`PreToolUse Blocked`) — **단 `/hooks` trust 필요**. trust 미완 시 무경고 통과를 실측 재현 |
| cursor-agent 2026.07.23 | `install.sh --vault` / `--fallback` | ✅ `Write` 절대경로 차단(`permission:deny`) · `Shell`/resolver 호출은 통과 · payload에 `cursor_version` 확인 |
| Antigravity 1.1.8 | `install.sh` | ➖ 훅 없음(스키마 미공개). skills 12개 + `rules/llm-wiki.md` 배치 확인 — `raw/` 보호는 AGENTS.md 소프트 룰 |

> Windows(`run-hook.cmd` cmd.exe 분기)는 여전히 정적 검토만 됐다 — 실기 검증은 Windows 환경 확보 시.
