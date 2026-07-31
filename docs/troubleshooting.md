# 트러블슈팅

증상 → 원인 → 복구. 설치·카탈로그는 [README](../README.md), 규칙의 근거는 [spec.md](specs/spec.md)·[distribution-design.md](specs/distribution-design.md), 파일별 상세는 [hooks-and-scripts.md](specs/hooks-and-scripts.md)를 본다.

> **이 문서를 먼저 읽어야 하는 이유:** 이 하네스의 보호 장치(raw/ 가드·frontmatter 검증)는 **fail-open**이다 — 볼트를 resolve하지 못하면 조용히 통과한다. 무관한 프로젝트에서 오탐을 내지 않기 위한 설계지만, 그래서 고장이 "에러"가 아니라 **침묵**으로 나타난다. 아래 항목 중 절반이 "조용히 무방비가 되는" 경우다.

## 증상별 빠른 색인

| 증상 | 항목 |
|---|---|
| 스킬이 `E_*` 코드로 중단된다 | [Config Gate 실패](#config-gate-실패-e_-코드) |
| config는 정상인데 `E_INVALID_CONFIG`가 반복된다 | [python3 확인](#e_invalid_config인데---repair가-듣지-않는다--python3-확인) |
| 검색이 키워드만 잡는다 · `QMD skipped/partial/failed` | [QMD 미설치·미등록](#qmd-미설치미등록--grep-fallback) |
| `raw/` 쓰기가 차단되지 않는다 | [훅이 발화하지 않는다](#훅이-발화하지-않는다) → 플랫폼별 아래 항목 |
| Codex에서 가드가 없다 | [trust 미완](#codex--hooks-trust-미완-시-무경고-no-op) · [설정 파싱 실패](#codex--훅-설정-파싱-실패도-같은-증상을-낸다-경고-1줄--훅-0개) |
| 차단 메시지가 2번 뜬다 | [Codex 중복 등록](#codex--훅이-2번-발화한다-플러그인--볼트-로컬-중복-등록) · [Cursor 7개 소스 병합](#cursor--로컬-agent-vs-cloud-agent) |
| 규칙 일부가 무시된다 | [`project_doc_max_bytes`](#codex--agentsmd가-잘려-로드된다-project_doc_max_bytes) |
| Cloud 환경에서 부트스트랩이 안 된다 | [Cursor 로컬 vs Cloud](#cursor--로컬-agent-vs-cloud-agent) |
| 워크스페이스 밖 접근이 막힌다 | [sandbox 권한 승인](#cursorantigravity--sandbox-권한-승인) |
| Windows에서 훅이 전부 죽는다 | [Git Bash / WSL](#windows--git-bash-또는-wsl-bash가-path에-필요) |

## Config Gate 실패 (`E_*` 코드)

모든 wiki 작업은 `bash ~/.llm-wiki/scripts/resolve-vault.sh`를 먼저 통과한다. 실패하면 stderr 첫 줄이 `E_CODE: 메시지` 형태로 복구 경로를 알려준다.

| exit | 코드 | 뜻 | 복구 |
|---|---|---|---|
| 2 | `E_NO_CONFIG` | 볼트 설정이 없다 | `wiki-setup` |
| 3 | `E_BAD_POINTER` | 전역 포인터가 없는 경로를 가리킨다 | `wiki-setup --update-path` |
| 4 | `E_INVALID_CONFIG` | `.wiki-config.json`이 깨졌다 | `wiki-setup --repair` |
| 5 | `E_VERSION` | 설정 버전이 하네스보다 새롭다 | 하네스 `git pull` |
| 6 | `E_NOT_A_VAULT` | 볼트 구조(`wiki/`)가 없다 | `wiki-setup --repair` |

스크립트 **파일 자체가 없으면** `./install.sh`를 재실행한다 — `~/.llm-wiki/scripts` 부트스트랩이 안 된 상태다.

## `E_INVALID_CONFIG`인데 `--repair`가 듣지 않는다 → python3 확인

`.wiki-config.json`이 정상인데도 `E_INVALID_CONFIG: config 파싱에 실패했습니다`가 반복되면 **원인은 config가 아니라 python3 부재**다. resolver가 파싱에 python3를 쓰기 때문에 없으면 파싱 실패로 보고된다.

```bash
python3 --version     # 없으면 설치 후 재시도
```

이 상태에서는 **raw/ 가드와 frontmatter 검증도 함께 발화하지 않는다** — 두 훅이 resolver 실패를 "볼트 밖 세션"으로 해석해 통과시키기 때문이다(비볼트 오탐 방지 설계). 즉 python3 하나가 없으면 보호 장치 전체가 조용히 풀리므로, 진단이 이상하면 가장 먼저 확인한다.

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

## Windows — Git Bash 또는 WSL bash가 PATH에 필요

공유 스크립트와 훅은 전부 `.sh`(bash)다. `hooks/run-hook.cmd`가 cmd.exe에서 bash로 위임하는 폴리글랏 런처이지만, **bash 자체는 PATH에 있어야 한다.**

```
run-hook.cmd: bash를 찾을 수 없습니다. Git Bash 또는 WSL bash를 PATH에 추가하세요.
```

이 메시지가 보이면 Git for Windows 또는 WSL을 설치한다. Codex의 플러그인 훅은 비Windows 전제다. `.ps1`/`.bat` 패리티 버전은 향후 보완 항목이다.
