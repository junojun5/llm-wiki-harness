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
| **`run-hook.cmd`** | **폴리글랏 런처** — Unix(bash)·Windows(cmd.exe) 양쪽에서 동작. `run-hook.cmd <script> [platform]` → `bash <hookdir>/<script> [platform]`로 위임(자기 위치를 `$0`로 찾음). 세 플러그인이 모두 이걸 경유해 훅 스크립트를 부른다 — Claude `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd`, Codex `${PLUGIN_ROOT}/hooks/run-hook.cmd`, Cursor `./hooks/run-hook.cmd`(self-locating으로 cwd 버그 회피). Windows 네이티브 에이전트가 `.sh`를 직접 못 돌릴 때 Git Bash/WSL bash로 넘긴다. |
| **`probe-hook.sh`** | **픽스처 캡처 도구**(개발용). 훅 이벤트의 raw stdin 페이로드·argv를 파일로 저장하고 항상 통과(exit 0). Codex/Cursor의 실제 stdin/stdout 스키마를 실측해 골든 픽스처로 확보하기 위한 것. 평상시 훅 등록에는 쓰지 않는다. (배포 설계 §9-6) |

### 플랫폼별 등록 JSON (같은 bash 로직을 각 플랫폼 형식으로 등록)

| 파일 | 대상 | 내용 |
|---|---|---|
| **`hooks.json`** | Claude (플러그인) | `.claude-plugin/plugin.json`이 이 파일을 가리켜 마켓플레이스 설치 시 자동 등록. SessionStart·PreToolUse·PostToolUse 3종을 `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd` 경유로 등록 → **install.sh 없이 동작**. `--fallback`(수동)은 `${CLAUDE_PLUGIN_ROOT}`를 `~/.claude`로 치환한 스니펫을 만들어 `~/.claude/settings.json` 머지를 안내. |
| **`hooks-codex.json`** | Codex (플러그인) | `.codex-plugin/plugin.json`의 `hooks` 키가 가리켜 `/plugins` 설치 시 등록. SessionStart·PreToolUse(`apply_patch` 포함)·PostToolUse를 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/hooks/run-hook.cmd` 경유로 등록. **플러그인 번들 훅은 non-managed** → 최초 1회 `/hooks` **trust** + `config.toml [features] hooks=true`(비Windows) 필요. `--fallback`/`--vault`는 `${PLUGIN_ROOT..}`를 실제 절대경로로 render해 `~/.codex/hooks.json`·`{vault}/.codex/hooks.json` 생성. |
| **`hooks-cursor.json`** | Cursor (플러그인) | `.cursor-plugin/plugin.json`의 `skills`·`hooks` 키가 가리켜 플러그인 설치 시 자동 등록. camelCase 이벤트(`sessionStart`/`preToolUse`/`postToolUse`) + JS 정규식 matcher. command는 `./hooks/run-hook.cmd`(self-locating) — Cursor 플러그인 훅의 cwd=워크스페이스 버그를 `$0` 자가위치로 회피(플러그인 루트 env var 없음·하드코딩 금지). 차단 출력 `{"permission":"deny","user_message":…}`. `--fallback`/`--vault`는 `./hooks/run-hook.cmd`를 절대경로로 render해 `~/.cursor/hooks.json`·`.cursor/hooks.json` 생성. Cloud Agent는 sessionStart 미지원(로컬 전용). |

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
                    — 모두 플러그인 매니페스트가 가리켜 설치 시 자동 등록(Antigravity는 훅 스키마 미공개로 제외)
                    + cursor-sandbox.template.json(Cursor sandbox 권한)
```

**게이팅 요약:** 주입(session-start)은 **CWD가 볼트 안일 때만**, 보호(가드 훅)는 **경로가 볼트 `raw/`·`wiki/` 안일 때만**, 부트스트랩(session-start ①)은 **항상**(멱등). 볼트 미설정 머신에선 resolve-vault 실패로 전부 조용한 no-op.

> ⚠️ **미검증:** Codex/Cursor의 훅 stdin/stdout 스키마와 Antigravity 훅 포맷은 실제 CLI 실측(`probe-hook.sh` 골든 픽스처)이 필요하다. 가드 훅은 다중 키 탐색으로 보수적으로 대응하나, trust·실측 전까지 Codex/Cursor의 기계적 차단은 그 확인 뒤 보장된다.
