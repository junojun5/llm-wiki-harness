# 트러블슈팅

증상 → 원인 → 복구. 설치·카탈로그는 [README](../README.md), 규칙의 근거는 [spec.md](specs/spec.md)·[distribution-design.md](specs/distribution-design.md), 파일별 상세는 [hooks-and-scripts.md](specs/hooks-and-scripts.md)를 본다.

> **이 문서를 먼저 읽어야 하는 이유:** 이 하네스의 보호 장치(raw/ 가드·frontmatter 검증)는 **fail-open**이다 — 볼트를 resolve하지 못하면 조용히 통과한다. 무관한 프로젝트에서 오탐을 내지 않기 위한 설계지만, 그래서 고장이 "에러"가 아니라 **침묵**으로 나타난다. 아래 항목 중 절반이 "조용히 무방비가 되는" 경우다.

## 증상별 빠른 색인

| 증상 | 항목 |
|---|---|
| 스킬이 `E_*` 코드로 중단된다 | [Config Gate 실패](#config-gate-실패-e_-코드) |
| `E_NO_RUNTIME` · 세션 시작에 python3 경고가 뜬다 | [python3가 없다](#e_no_runtime--python3가-없다) |
| config는 정상인데 `E_INVALID_CONFIG`가 반복된다 | [구버전의 오진](#e_no_runtime--python3가-없다) |
| 검색이 키워드만 잡는다 · `QMD skipped/partial/failed` | [QMD 미설치·미등록](#qmd-미설치미등록--grep-fallback) |
| `raw/` 쓰기가 차단되지 않는다 | [훅이 발화하지 않는다](#훅이-발화하지-않는다) → 플랫폼별 아래 항목 |
| Codex에서 가드가 없다 | [trust 미완](#codex--hooks-trust-미완-시-무경고-no-op) · [설정 파싱 실패](#codex--훅-설정-파싱-실패도-같은-증상을-낸다-경고-1줄--훅-0개) |
| 차단 메시지가 2번 뜬다 | [Codex 중복 등록](#codex--훅이-2번-발화한다-플러그인--볼트-로컬-중복-등록) · [Cursor 7개 소스 병합](#cursor--로컬-agent-vs-cloud-agent) |
| 규칙 일부가 무시된다 | [`project_doc_max_bytes`](#codex--agentsmd가-잘려-로드된다-project_doc_max_bytes) |
| Cloud 환경에서 부트스트랩이 안 된다 | [Cursor 로컬 vs Cloud](#cursor--로컬-agent-vs-cloud-agent) |
| 워크스페이스 밖 접근이 막힌다 | [sandbox 권한 승인](#cursorantigravity--sandbox-권한-승인) |
| Windows에서 훅이 전부 죽는다 | [Git for Windows](#windows--git-for-windows가-필요하다) |
| 고친 걸 머지했는데 설치본이 그대로다 | [버전 bump 없이는 배포되지 않는다](#버전-bump-없이는-배포되지-않는다) |

## Config Gate 실패 (`E_*` 코드)

모든 wiki 작업은 `bash ~/.llm-wiki/scripts/resolve-vault.sh`를 먼저 통과한다. 실패하면 stderr 첫 줄이 `E_CODE: 메시지` 형태로 복구 경로를 알려준다.

| exit | 코드 | 뜻 | 복구 |
|---|---|---|---|
| 2 | `E_NO_CONFIG` | 볼트 설정이 없다 | `wiki-setup` |
| 3 | `E_BAD_POINTER` | 전역 포인터가 없는 경로를 가리킨다 | `wiki-setup --update-path` |
| 4 | `E_INVALID_CONFIG` | `.wiki-config.json`이 깨졌다 | `wiki-setup --repair` |
| 5 | `E_VERSION` | 설정 버전이 하네스보다 새롭다 | 하네스 `git pull` |
| 6 | `E_NOT_A_VAULT` | 볼트 구조(`wiki/`)가 없다 | `wiki-setup --repair` |
| 7 | `E_NO_RUNTIME` | python3이 PATH에 없다 | python3 설치 후 **세션 재시작** ([아래](#e_no_runtime--python3가-없다)) |

스크립트 **파일 자체가 없으면** `./install.sh`를 재실행한다 — `~/.llm-wiki/scripts` 부트스트랩이 안 된 상태다.

## `E_NO_RUNTIME` → python3가 없다

```bash
python3 --version     # 없으면 설치 후 세션 재시작
```

**증상.** 볼트가 설정된 머신에서 python3가 없으면 세션 시작에 경고가 1회 주입되고(stderr에도 `E_NO_RUNTIME: python3 부재 …`), 모든 wiki 스킬이 Step 0에서 중단된다.

**무엇이 함께 죽는가.** python3는 Config Gate·frontmatter validator·훅의 경로 판정 블록 **전부**가 쓴다. 따라서:

| 구성요소 | 없을 때 |
|---|---|
| wiki 스킬 12종 | **중단** (Step 0 fail-closed — 스킬 경유 쓰기는 애초에 일어나지 않는다) |
| `wiki-protect-raw` (raw/ 보호) | **통과** — 가드 없음 |
| `wiki-validate-frontmatter` | **통과** — 검증 없음 |
| `session-start` | 부트스트랩·경고는 동작한다(순수 셸), 규칙 주입은 없음 |

즉 스킬을 우회해 손으로 `raw/`를 편집하면 아무것도 막지 않는다. 볼트 쓰기는 python3를 복구한 뒤에 한다.

**왜 가드가 차단이 아니라 통과인가 (의도된 설계).** 두 가드 훅은 **글로벌**이라 볼트를 쓰지 않는 프로젝트에서도 매 도구 호출에 발화한다 — resolver 실패를 차단으로 해석하면 무관한 모든 작업의 쓰기가 막힌다. 게다가 "이 쓰기가 `raw/`를 향하는가"를 가리는 판정 블록 자체가 python3다. 차단으로 돌리는 것은 `raw/`만 골라 막는 게 아니라 **볼트 안 전체를 막는 것**이 된다. 그래서 강등은 조용히 하고 **고지는 세션 시작 1회**로 분리했다 ([spec](specs/spec.md) §5-2·§5-1).

**python3가 있는데도 `E_INVALID_CONFIG`가 반복되면 — 인코딩이다 (0.3.1에서 수정).** python3의 I/O·`open()` 기본 인코딩은 **locale이 결정**한다. Windows의 기본은 cp1252여서, 볼트 경로나 사용자 이름에 한글이 있으면 `.wiki-config.json` 읽기가 `UnicodeDecodeError`로 죽고 그게 파싱 실패로 흘러 같은 오진이 된다. 같은 원인으로 세션 시작 **주입이 빈 출력으로 죽고**, `raw/` 차단의 Cursor deny 메시지가 사라지고, 위반 메시지가 `\uXXXX`로 손상된다. 0.3.1부터 모든 python3 호출이 `PYTHONUTF8=1`로 실행되므로(스펙 §3-9) **하네스를 0.3.1 이상으로 올리면 해결된다** — 구버전이면 [버전 bump](#버전-bump-없이는-배포되지-않는다) 항목대로 갱신한다.

**`--repair`는 듣지 않는다.** 원인이 config가 아니기 때문이다. 예전 버전은 python3 부재를 `E_INVALID_CONFIG: config 파싱에 실패했습니다`로 **오진**해 사용자가 `wiki-setup --repair`를 반복하게 만들었다 — 그 메시지가 보이고 `.wiki-config.json`이 정상이라면 하네스가 구버전이므로 `git pull` 후 세션을 재시작한다(플러그인 설치본은 [버전 bump](#버전-bump-없이는-배포되지-않는다) 항목 참조).

## QMD 미설치·미등록 → Grep fallback

QMD는 **선택적** 검색 인덱스다(markdown이 source of truth). 없어도 하네스는 동작하며, 스킬이 Grep으로 대체하고 상태 문자열을 남긴다.

- `QMD skipped: qmd CLI unavailable` — `qmd`가 PATH에 없다. [요구사항](../README.md#선택--qmd-검색-인덱스)의 `npm install -g @tobilu/qmd`로 설치하거나, 그대로 Grep으로 쓴다.
- `QMD skipped: collection not registered` — 볼트가 컬렉션으로 등록되지 않았다 → `wiki-setup --update-qmd`
- `QMD partial: …` / `QMD failed: …` — **단발이면 액션 불필요**하다. `qmd update`가 매번 전체 해시 스캔이라 다음 쓰기가 누락분을 흡수한다(self-healing). **2회 연속 실패**나 검색 결과가 stale하게 느껴질 때만 `wiki-setup --update-qmd`.

진단 순서:

```bash
qmd doctor                  # 설치·SQLite·모델 캐시 (help에는 안 나오지만 동작한다)
qmd status                  # 인덱스 + 컬렉션 health
qmd collection list         # 볼트 wiki/ 경로가 목록에 있는지
```

`qmd doctor`가 `model cache: missing N/3`을 보고하면 안내대로 `qmd pull`로 미리 받는다. 단 우리가 쓰는 `embed`에는 임베딩 모델만 필요하므로, 나머지 2개가 없어도 하네스의 QMD refresh는 정상 동작한다.

> ⚠️ **`qmd collection add`는 경로를 생략하면 현재 디렉토리를 등록한다.** 수동으로 정리할 때 `qmd collection add`만 치면 엉뚱한 cwd가 컬렉션이 된다 — 경로를 항상 명시하고, 잘못 만들었으면 `qmd collection remove <name>`으로 지운다. `wiki-setup`은 항상 볼트 경로를 명시하므로 이 함정에 걸리지 않는다.

> 첫 QMD 사용 시 **GGUF 모델 ~2GB 다운로드**로 오래 멈춘 것처럼 보일 수 있다. 실패가 아니라 초기 1회 비용이다.

## 훅이 발화하지 않는다

먼저 어느 플랫폼인지에 따라 원인이 다르다.

1. **등록 자체를 확인한다** — Claude는 `settings.json`의 `hooks` 블록(플러그인 설치면 자동), Codex는 `~/.codex/hooks.json`, Cursor는 `~/.cursor/hooks.json` 또는 `{vault}/.cursor/hooks.json`.
2. **훅은 볼트 안에서만 주입한다** — `session-start`는 CWD가 볼트 밖이면 의도적으로 아무것도 하지 않는다(전역 등록 스팸 방지). raw/ 가드·frontmatter 검증은 볼트가 resolve되지 않으면 조용히 통과한다.
3. **`bash`가 PATH에 있어야 한다** — 훅은 모두 bash 스크립트다(아래 Windows 항목).

## Codex — `/hooks` trust 미완 시 **무경고 no-op**

가장 헷갈리는 케이스다. 플러그인 번들 훅은 non-managed라서 **trust 하기 전까지 경고도 오류도 없이 조용히 아무 일도 하지 않는다.** "훅이 등록됐는데 raw/ 쓰기가 차단되지 않는다"면 먼저 이걸 확인한다.

```
/hooks          → 비관리 훅을 리뷰하고 trust (최초 1회)
```

비대화형 실행은 `codex exec --dangerously-bypass-hook-trust …`. `config.toml [features] hooks=true`는 0.145.0에서 **불필요**하다(stable·기본 활성).

## Codex — 훅 설정 파싱 실패도 같은 증상을 낸다 (경고 1줄 + 훅 0개)

trust와 **증상이 똑같아서** 헷갈린다. Codex는 훅 설정을 strict하게 읽으므로 최상위에 `description`·`hooks` 외의 키가 있으면 파일 전체를 버린다. 설치는 성공하고 `codex plugin list`도 `installed, enabled`로 보이는데 가드만 사라진다. 구분법은 경고를 보는 것이다:

```
codex exec ... 2>&1 | grep 'failed to parse'
# warning: failed to parse hooks config …/hooks.json: unknown field `_comment`,
#          expected `description` or `hooks`
```

하네스 배포본은 이 제약을 지키며 `tests/hooks/test-hook-config-schema.sh`가 회귀를 막는다. **직접 손으로 만든 `~/.codex/hooks.json`이나 낡은 `{vault}/.codex/hooks.json`이 원인일 수 있다** — `install.sh`는 기존 파일을 덮지 않으므로(비파괴 정책) 하네스가 갱신돼도 옆에 `hooks.llm-wiki.json` 사본만 생긴다. 그 사본과 비교해 수동 머지한다.

## Codex — 훅이 2번 발화한다 (플러그인 + 볼트-로컬 중복 등록)

Codex는 플러그인 훅과 프로젝트-로컬 `{vault}/.codex/hooks.json`을 **병합**한다. 둘 다 있으면 같은 훅이 2회 발화한다(실측: SessionStart 1회 → 2회). Cursor의 경로 분리 원칙과 같은 이유로 **한쪽만 남긴다** — 마켓플레이스로 설치했다면 Codex 목적의 `install.sh --vault`/`--fallback`은 실행하지 않는다.

> `install.sh`는 `~/.llm-wiki/scripts/`를 **자기 체크아웃 경로로 재지정**한다(하네스 소유 파일이라 비파괴 정책의 예외). 마켓플레이스 부트스트랩은 플러그인 캐시를 가리키므로, 임시 클론·워크트리에서 `install.sh`를 돌리면 공용 런타임이 그 경로에 묶인다. 그 디렉토리를 지우면 링크가 깨진다 — 안정된 클론에서 실행하거나, 링크를 지우고 다음 SessionStart의 자가-부트스트랩에 맡긴다.

## Codex — `AGENTS.md`가 잘려 로드된다 (`project_doc_max_bytes`)

Codex는 global/project `AGENTS.md`를 instruction chain으로 병합하며 기본 한도가 **32 KiB**다. 초과하면 규칙이 조용히 잘린다.

```toml
# ~/.codex/config.toml
project_doc_max_bytes = 65536
```

이 저장소의 `AGENTS.md`는 축약판만 유지해 한도 안에 들어간다 — 상세는 각 `SKILL.md`로 위임한다.

## Cursor — 로컬 Agent vs Cloud Agent

- **훅은 플러그인으로 등록되지 않는다.** `install.sh`가 필수다([설치 매트릭스](../README.md#설치)).
- **Cloud Agent는 `sessionStart`·user hooks를 지원하지 않는다** — 부트스트랩 주입이 없으므로 로컬 데스크톱 Agent를 쓴다. Cloud에서 작업해야 하면 `AGENTS.md`가 규칙을 대신 로드한다.
- Cursor는 훅 설정을 **7개 소스에서 병합**하며 `~/.claude/settings.json`·`{ws}/.claude/settings.json`도 실행한다 — 같은 훅을 Claude 설정과 중복 등록하면 **2회 발화**한다. 경로를 분리해 유지한다.

## Cursor·Antigravity — sandbox 권한 승인

기본 sandbox(`workspace_readwrite`)는 워크스페이스 밖 R/W를 차단하므로 `~/.llm-wiki/scripts/resolve-vault.sh` 호출이 실패할 수 있다. `install.sh --vault <path>`가 배치하는 `.cursor/sandbox.json`이 `~/.llm-wiki`와 볼트 경로를 허용 목록에 넣는다. Antigravity는 권한 프롬프트에서 해당 경로 접근을 **Allow** 한다.

## Windows — Git for Windows가 필요하다

공유 스크립트와 훅은 전부 `.sh`(bash)다. `hooks/run-hook.cmd`가 cmd.exe에서 bash로 위임하는 폴리글랏 런처이지만, **bash 자체는 있어야 한다.**

```
[llm-wiki] bash not found - wiki guard hooks are DISABLED. Install Git for Windows, or add bash to PATH.
```

이 경고는 **세션 시작에 1회만** 나온다(SessionStart 훅). 그 세션에서는 `raw/` 보호와 frontmatter 검증이 **비활성**이고, 가드 훅 쪽은 조용히 통과한다 — PreToolUse matcher가 `Write|Edit|MultiEdit|NotebookEdit|Bash`로 전역이라, 여기서 차단하면 볼트와 무관한 모든 편집이 막히고 매 호출마다 에러를 내면 알림이 도배된다. 그래서 "세션 시작에 한 번 크게 알리고, 이후엔 통과"로 설계했다.

**해법은 [Git for Windows](https://git-scm.com/download/win) 설치다.** 런처는 `%ProgramFiles%\Git\bin\bash.exe` → `%ProgramFiles(x86)%\...` → `%LOCALAPPDATA%\Programs\Git\bin\bash.exe` 순으로 실제 설치 위치를 먼저 확인하고, 못 찾으면 마지막에 `where bash`로 PATH를 본다.

> ⚠️ **WSL의 bash로는 동작하지 않는다.** WSL 기능이 켜진 시스템에는 `C:\Windows\System32\bash.exe`(레거시 런처)가 있고 System32는 PATH 앞쪽에 거의 항상 있다. 그 bash는 런처가 넘기는 `C:\...` 형식 Windows 경로를 WSL 안에서 해석할 수 없어 훅이 죽는다. 런처가 Git 설치 경로를 먼저 뒤지는 이유이며, 이전 문서의 "Git Bash 또는 WSL bash" 표기는 2026-08-05에 정정됐다(WSL 갈래는 실기 검증된 적이 없었다).

Claude Code에서는 훅 항목의 `shell` 필드가 실행 셸을 정하고 기본값이 `bash`이므로, **Git Bash가 있으면 이 `.cmd`의 cmd.exe 분기를 아예 타지 않는다** — Claude가 런처를 bash로 직접 실행한다. cmd.exe 분기는 Git Bash 없는 Claude(→PowerShell→`.cmd`)와 Codex·Cursor 경로에서 쓰인다. `.ps1`/`.bat` 패리티 버전은 향후 보완 항목이다.

## 버전 bump 없이는 배포되지 않는다

**증상.** master에 수정을 머지했는데 `claude plugin update`가 `already at the latest version (X.Y.Z)`라고 하고, 설치된 스킬·스크립트가 **옛 내용 그대로**다.

**원인.** `claude plugin update`는 **`plugin.json`의 `version` 문자열로만** 갱신 여부를 판정한다. 커밋 sha는 보지 않는다. 2026-08-01 실측:

```
마켓플레이스 클론  → 1e31d51 (머지 커밋까지 갱신됨)
설치 기록 sha      → b1d1593 (구버전)
version            → 0.1.0 → 0.1.0 (변화 없음)
결과               → "already at the latest version" · 캐시 refresh 안 됨
```

`claude plugin marketplace update`로 마켓플레이스 메타를 갱신해도 마찬가지다 — 그건 카탈로그만 새로 받는다.

**확인.** 설치본과 레포를 직접 대조한다.

```bash
CACHE=~/.claude/plugins/cache/llm-wiki-harness/llm-wiki-harness/<버전>
cmp -s "$CACHE/scripts/build-link-graph.sh" ./scripts/build-link-graph.sh \
  && echo same || echo STALE
```

**해결.** 릴리스마다 **5곳을 함께** 올린다 — `VERSION` · `.claude-plugin/plugin.json` · `.codex-plugin/plugin.json` · `.cursor-plugin/plugin.json` · `.antigravity-plugin/plugin.json`. 일부만 올리면 플랫폼마다 다른 버전이 배포되므로, `tests/install/test-version-consistency.sh`가 5곳 일치를 강제한다(`tests/run.sh`에 포함).

올린 뒤:

```bash
claude plugin marketplace update llm-wiki-harness
claude plugin update llm-wiki-harness@llm-wiki-harness   # 정규화된 이름 필요
```

`claude plugin update llm-wiki-harness`(마켓플레이스 접미어 없이)는 `Plugin "llm-wiki-harness" not found`로 실패한다 — `claude plugin list`가 출력하는 `<플러그인>@<마켓플레이스>` 형태를 그대로 쓴다.

### 캐시는 새 버전인데 런타임이 옛 버전이다

`plugin update`가 성공했는데도 동작이 그대로면 **런타임 홈이 구버전을 가리키는지** 본다. `~/.llm-wiki/scripts/*`는 버전별 캐시 디렉토리를 가리키므로, 구버전 캐시가 남아 있으면 stale해질 수 있다.

```bash
ls -l ~/.llm-wiki/scripts/          # 어느 버전을 가리키나
```

0.2.1부터는 새 버전의 `session-start`가 **형제 버전을 가리키는 링크를 자동 재지정**한다(사용자 클론을 가리키는 링크는 비파괴 정책대로 보존한다). **0.2.0 이하에서 올라올 때만 1회 수동 복구가 필요하다** — 구 훅은 이 로직이 없어 스스로 고치지 못한다.

```bash
rm -f ~/.llm-wiki/scripts/{resolve-vault,validate-frontmatter,build-link-graph}.sh
bash ~/.claude/plugins/cache/llm-wiki-harness/llm-wiki-harness/<새버전>/hooks/session-start claude </dev/null
```

**적용은 재시작 후다.** `update`는 캐시를 교체하지만 실행 중인 세션은 옛 스킬을 들고 있다. 런타임 홈(`~/.llm-wiki/scripts/`)은 캐시를 symlink하므로 **스크립트는 즉시 새 버전이 되고 스킬 문서만 재시작을 기다린다**(Windows/MSYS는 복사이므로 스크립트도 다음 SessionStart의 재지정을 기다린다 — 배포 설계 §7-1b) — 이 비대칭이 "스크립트는 고쳐졌는데 스킬이 옛 절차를 따르는" 상태를 만들 수 있으니 릴리스 검증은 재시작 후에 한다.
