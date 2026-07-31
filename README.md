# LLM Wiki Harness

Claude Code · Codex · Cursor · Antigravity 위에서 동작하는, 에이전트가 스스로 채우고 연결하고 유지하는 개인 마크다운 지식 베이스.

## Quickstart

플랫폼별 설치로 바로 이동: [Claude Code](#claude-code) · [Codex](#codex) · [Cursor](#cursor) · [Antigravity](#antigravity)

## 동작 방식

Andrej Karpathy의 **LLM Wiki 패턴**을 하네스로 구현한 것이다. RAG처럼 청크를 임베딩하고 끝내는 게 아니라, 에이전트가 대화하면서 영속적인 마크다운 wiki를 점진적으로 쓰고, 서로 링크하고, 오래된 내용을 정리한다. 사람은 어떤 자료를 넣을지, 어떤 질문을 던질지로 방향을 잡는다.

세션이 시작되면 에이전트는 곧바로 페이지를 쓰지 않는다. 먼저 **Step 0 Config Gate**(`resolve-vault.sh`)로 실제 볼트가 어디 있는지 확인하고, 의도에 맞는 스킬로 라우팅한다. 모든 쓰기는 같은 순서를 지킨다: 페이지 → `index.md` → `log.md` → `hot.md` → QMD refresh. 원본이 먼저, 파생물이 나중이다.

`raw/`는 절대 건드리지 않는다. 훅이 기계적으로 쓰기를 막고, 모든 사실 주장에는 `(출처: [[page]])` 또는 `⚠️ unverified`가 붙는다. 훅을 못 쓰는 플랫폼(Antigravity)에서는 같은 규칙이 `AGENTS.md` 소프트 룰로 강등되어 적용된다.

## 기본 워크플로우

1. **wiki-setup** — 볼트 초기화. 다른 모든 스킬보다 먼저 실행한다.
2. **wiki-ingest / ingest-url / wiki-capture** — 자료를 채운다. 로컬 파일, URL, 현재 대화 세 가지 입구.
3. **wiki-query** — 쌓인 wiki를 근거로 질문에 답한다.
4. **wiki-knowledge** — 흩어진 summaries를 하나의 깊이 있는 `knowledge/` 페이지로 종합하고 충돌을 정리한다.
5. **wiki-lint** — 볼트를 감사하고(report) 기계적으로 고친다(`--fix`).
6. **wiki-status** — 지금 볼트에 뭐가 쌓여 있고 뭐가 남았는지 확인한다.
7. **wiki-project-init / wiki-project-design / wiki-project-record** — 프로젝트를 운영할 때: 시작 → 설계 변경(proposal) → 결정/이슈/미팅 기록.

**에이전트는 작업 전 항상 관련 스킬을 먼저 확인한다.** 제안이 아니라 강제되는 흐름이다. 케이스별 상세 흐름(그린필드·대량 적재·질문 우선·캡처·유지보수·프로젝트·멀티플랫폼)은 [docs/best-practices.md](docs/best-practices.md) 참조.

## 설치

지원 플랫폼은 4개. 어느 쪽이든 ① 스킬·훅 배치 → ② 볼트에서 `/wiki-setup` 1회 → ③ 스킬 사용 흐름은 같다. 다른 건 **설치 위치**와 **훅이 자동으로 등록되는 정도**뿐이다.

| 플랫폼 | 플러그인 설치만으로 스킬+훅 | `install.sh` | 비고 |
|---|---|---|---|
| **Claude Code** | ✅ 스킬+훅 완전 자동 | 선택 (`--fallback`) | 첫 SessionStart가 `~/.llm-wiki`를 자가치유 |
| **Codex** | ✅ 스킬+훅 자동 선언, 단 최초 1회 `/hooks` trust | 선택 (`--fallback`) | trust 미완 시 **무경고 no-op** |
| **Cursor** | ⚠️ **스킬만** — 훅은 등록되지 않는다 | **필수** | 훅은 `.cursor/hooks.json` 배치 경로만 유효 |
| **Antigravity** | ⚠️ 스킬 + AGENTS.md만 | **필수** | 공식 훅 스키마 미공개 — 아래 참고 |

> **Cursor에서 `install.sh`는 폴백이 아니라 필수다.** cursor-agent가 플러그인 매니페스트의 `hooks` 키를 소비하지 않으므로(2026-07-31 실측), 플러그인만 설치하면 스킬은 로드되지만 **raw/ 가드와 frontmatter 검증이 아예 돌지 않는다.**

### Claude Code

```bash
/plugin marketplace add junojun5/llm-wiki-harness
/plugin install llm-wiki-harness
```

마켓플레이스 미사용 시: `./install.sh --fallback` (skills+hooks → `~/.claude/` + settings.json 머지 안내)

`plugin.json` → `hooks/hooks.json`이 SessionStart·PreToolUse·PostToolUse를 자동 등록하고, 첫 SessionStart가 `~/.llm-wiki/scripts`를 자가치유한다. `install.sh` 없이 훅·스킬·가드가 모두 동작한다.

### Codex

```bash
codex plugin marketplace add junojun5/llm-wiki-harness
# → /plugins 설치 후 /hooks 에서 trust (비대화형은 --dangerously-bypass-hook-trust)
```

마켓플레이스 미사용 시: `./install.sh --fallback` (skills → `~/.agents/`, hooks → `~/.codex/hooks.json`)

플러그인 번들 훅은 non-managed라 설치만으로 활성화되지 않는다 — **최초 1회 `/hooks`에서 trust**가 필요하다. 이후엔 부트스트랩·주입·가드가 모두 동작한다. `config.toml [features] hooks=true`는 0.145.0에서 **불필요**하다(stable·기본 활성으로 승격). 마켓플레이스 매니페스트는 `.agents/plugins/marketplace.json`이 canonical이다.

### Cursor

```bash
# 1) 스킬: .cursor-plugin/plugin.json → 공식 마켓플레이스 또는 ~/.cursor/plugins/local/
# 2) 훅: install.sh 필수 (플러그인으로는 등록되지 않는다)
./install.sh --fallback          # 전역(User) → ~/.cursor/hooks.json
./install.sh --vault <path>      # 프로젝트-로컬 → {vault}/.cursor/hooks.json + sandbox.json
```

⚠️ **훅은 `install.sh`로만 등록된다.** `.cursor-plugin/`은 스킬 전용 표면이다 — 매니페스트의 `hooks`를 cursor-agent가 파싱은 하나 훅 실행 엔진에 도달하지 않는다(실측).

⚠️ Cloud Agent는 `sessionStart`/user hooks를 지원하지 않는다 — 로컬 데스크톱 Agent를 사용한다.

⚠️ 기본 sandbox(`workspace_readwrite`)는 워크스페이스 밖 R/W를 막아 `~/.llm-wiki/scripts` 호출이 실패할 수 있다. `--vault`가 배치하는 `.cursor/sandbox.json`이 그 경로를 허용한다.

### Antigravity

```bash
./install.sh                    # ~/.gemini 감지 시 전역 플러그인 배치
./install.sh --vault <path>     # 워크스페이스 로컬
```

Antigravity 공식 플러그인 스펙은 `hooks.json`을 구조적으로 지원하지만, 실측(`agy` CLI)상 훅 핸들러가 등록되지 않아(`0 handlers`) 발화하지 않는다 — 공식 훅 스키마 문서도 아직 404다. `install.sh`가 스킬 + `AGENTS.md` 배치와 `~/.llm-wiki` 부트스트랩을 대신하고, raw/ 가드는 AGENTS.md 소프트 룰로 강등된다. `agy`가 훅을 공식 지원하면 실측 후 훅도 추가한다.

### 볼트 설정

설치 후 볼트에서 `/wiki-setup` 실행 → `.wiki-config.json` · `~/.llm-wiki/default-vault` · wiki 디렉토리 · QMD 컬렉션 등록.

## 스킬 카탈로그

| 카테고리 | 스킬 | 언제 쓰나 | 하는 일 |
|---|---|---|---|
| 부트스트랩 | `using-llm-wiki` | 모든 세션 시작 시 자동 | Config Gate 실행 안내, 불변 규칙 상기, 의도에 맞는 스킬로 라우팅 |
| 부트스트랩 | `wiki-setup` | 새 볼트를 만들거나 설정이 깨졌을 때 | `.wiki-config.json`·전역 포인터·wiki 디렉토리·QMD 컬렉션을 초기화/복구. 다른 스킬보다 항상 먼저 |
| 수집 | `wiki-ingest` | `raw/`에 파일을 넣고 처리를 요청할 때("ingest this") | `raw/`의 로컬 파일(md/txt/pdf/이미지)을 읽어 출처를 남기며 `summaries/`로 변환 |
| 수집 | `ingest-url` | URL을 wiki에 저장하고 싶을 때("이 링크 저장해줘") | 웹 페이지를 가져와 `summaries/web/`에 저장 |
| 수집 | `wiki-capture` | 현재 대화의 지식을 남기고 싶을 때("capture this") | 진행 중인 대화를 요약해 `summaries/sessions/`에 보존 |
| 조회·종합 | `wiki-query` | wiki에 쌓인 내용에 대해 질문할 때 | 저비용 index 검색부터 계층 검색까지, 근거를 인용하며 답변 |
| 조회·종합 | `wiki-knowledge` | 흩어진 summaries/concepts/sessions를 정리하고 싶을 때 | 여러 소스를 종합해 `knowledge/` 페이지를 생성·갱신하고 충돌을 표면화 |
| 유지보수 | `wiki-lint` | 볼트 상태를 점검/정리하고 싶을 때 | orphan 페이지·깨진 링크·포맷 오류·충돌·소스 변경 미반영(`source_drift`)·PII·정리 가능한 raw 파일을 감사(report) 또는 수정(`--fix`) |
| 유지보수 | `wiki-status` | "뭐가 남았지?"가 궁금할 때 | ingest 대기 중인 raw, 최근 처리 내역, 볼트 전반 상태를 요약 |
| 프로젝트 | `wiki-project-init` | 프로젝트를 새로 시작/재정의할 때 | 인터뷰 방식으로 `projects/{name}/`에 overview·context·goals 생성 |
| 프로젝트 | `wiki-project-design` | 설계가 바뀌거나 발전할 때 | `projects/{name}/`의 architecture·도메인 모델·conventions를 change proposal 방식으로 갱신 |
| 프로젝트 | `wiki-project-record` | 결정·이슈·미팅·백로그를 남길 때 | 이벤트 종류를 판단해 라우팅하고 승인 후 `projects/{name}/`에 기록 |

## 저장소 구조

```
llm-wiki-harness/
├── AGENTS.md                        # 단일 출처 규칙 파일 — Codex/Cursor/Antigravity가 그대로 로드
├── CLAUDE.md                        # `@AGENTS.md` 한 줄 — Claude Code가 같은 내용을 임포트
├── install.sh                       # 멱등 부트스트랩/폴백 설치자. 볼트 *설정*은 wiki-setup 스킬 몫
├── LICENSE / VERSION
│
├── .claude-plugin/
│   ├── plugin.json                  # skills·hooks 경로 선언 → 마켓플레이스 설치 시 자동 등록
│   └── marketplace.json             # `/plugin marketplace add`가 읽는 카탈로그
├── .codex-plugin/plugin.json        # Codex 플러그인 매니페스트 (hooks-codex.json 참조)
├── .cursor-plugin/plugin.json       # Cursor 플러그인 매니페스트 (hooks-cursor.json 참조)
│
├── skills/                          # 12개 스킬 — 각 `<name>/SKILL.md` (위 스킬 카탈로그 참조)
│
├── scripts/                         # 결정론적 검증 로직. 4개 플랫폼이 ~/.llm-wiki/scripts로 공유
│   ├── resolve-vault.sh             #   Config Gate — 볼트 탐색·검증, VAULT_PATH/WIKI_DIR/RAW_DIR 출력
│   ├── validate-frontmatter.sh      #   frontmatter 필수 키·enum·날짜 형식 등 기계 검증
│   └── build-link-graph.sh          #   O(N) 1회 스캔으로 고아 페이지·깨진 링크·개념 갭 탐지
│
├── hooks/                           # 이벤트 스크립트 + 플랫폼별 등록
│   ├── session-start                #   SessionStart: ~/.llm-wiki 자가부트스트랩 + 볼트 안일 때만 컨텍스트 주입
│   ├── wiki-protect-raw.sh          #   PreToolUse: raw/ 쓰기 차단(삭제는 허용)
│   ├── wiki-validate-frontmatter.sh #   PostToolUse: wiki/*.md 쓰기 직후 frontmatter 검증
│   ├── run-hook.cmd                 #   폴리글랏 런처(Unix=bash / Windows=cmd.exe)
│   ├── probe-hook.sh                #   (개발용) 훅 payload 캡처 도구 — 평시 미등록
│   ├── hooks.json / hooks-codex.json / hooks-cursor.json  # 플랫폼별 이벤트 등록
│   └── cursor-sandbox.template.json #   Cursor sandbox 허용 경로 템플릿
│
├── tests/
│   ├── run.sh                       # 스크립트 단위 테스트 러너
│   ├── scripts/                     # resolve-vault·validate-frontmatter·build-link-graph 테스트
│   ├── hooks/                       # 3개 훅 스크립트 테스트
│   ├── fixtures/                    # Codex/Cursor 훅 stdin/stdout 골든 픽스처(수집 중)
│   └── install/smoke.sh             # install.sh 스모크 테스트
│
└── docs/
    ├── specs/spec.md                # 하네스 스펙 — wiki 구조·문서 클래스·훅 계약의 단일 출처
    ├── specs/distribution-design.md # 멀티플랫폼 배포 설계(근거·트레이드오프)
    ├── specs/hooks-and-scripts.md   # hooks/·scripts/ 파일별 상세 레퍼런스
    ├── plans/                       # 실행 계획(작업 단위 스냅샷)
    └── best-practices.md            # 케이스별 사용 시나리오
```

## 트러블슈팅

### Config Gate 실패 (`E_*` 코드)

모든 wiki 작업은 `bash ~/.llm-wiki/scripts/resolve-vault.sh`를 먼저 통과한다. 실패하면 stderr 첫 줄이 `E_CODE: 메시지` 형태로 복구 경로를 알려준다.

| exit | 코드 | 뜻 | 복구 |
|---|---|---|---|
| 2 | `E_NO_CONFIG` | 볼트 설정이 없다 | `/wiki-setup` |
| 3 | `E_BAD_POINTER` | 전역 포인터가 없는 경로를 가리킨다 | `/wiki-setup --update-path` |
| 4 | `E_INVALID_CONFIG` | `.wiki-config.json`이 깨졌다 | `/wiki-setup --repair` |
| 5 | `E_VERSION` | 설정 버전이 하네스보다 새롭다 | 하네스 `git pull` |
| 6 | `E_NOT_A_VAULT` | 볼트 구조(`wiki/`)가 없다 | `/wiki-setup --repair` |

스크립트 **파일 자체가 없으면** `./install.sh`를 재실행한다 — `~/.llm-wiki/scripts` 부트스트랩이 안 된 상태다.

### QMD 미설치·미등록 → Grep fallback

QMD는 **선택적** 검색 인덱스다(markdown이 source of truth). 없어도 하네스는 동작하며, 스킬이 Grep으로 대체하고 상태 문자열을 남긴다.

- `QMD skipped: qmd CLI unavailable` — `qmd`가 PATH에 없다. 설치하거나 그대로 Grep으로 쓴다.
- `QMD skipped: collection not registered` — 볼트가 컬렉션으로 등록되지 않았다 → `/wiki-setup --update-qmd`
- `QMD partial: …` / `QMD failed: …` — **단발이면 액션 불필요**하다. `qmd update`가 매번 전체 해시 스캔이라 다음 쓰기가 누락분을 흡수한다(self-healing). **2회 연속 실패**나 검색 결과가 stale하게 느껴질 때만 `/wiki-setup --update-qmd`.

### 훅이 발화하지 않는다

먼저 어느 플랫폼인지에 따라 원인이 다르다.

1. **등록 자체를 확인한다** — Claude는 `settings.json`의 `hooks` 블록(플러그인 설치면 자동), Codex는 `~/.codex/hooks.json`, Cursor는 `~/.cursor/hooks.json` 또는 `{vault}/.cursor/hooks.json`.
2. **훅은 볼트 안에서만 주입한다** — `session-start`는 CWD가 볼트 밖이면 의도적으로 아무것도 하지 않는다(전역 등록 스팸 방지). raw/ 가드·frontmatter 검증은 볼트가 resolve되지 않으면 조용히 통과한다.
3. **`bash`가 PATH에 있어야 한다** — 훅은 모두 bash 스크립트다(아래 Windows 항목).

### Codex — `/hooks` trust 미완 시 **무경고 no-op**

가장 헷갈리는 케이스다. 플러그인 번들 훅은 non-managed라서 **trust 하기 전까지 경고도 오류도 없이 조용히 아무 일도 하지 않는다.** "훅이 등록됐는데 raw/ 쓰기가 차단되지 않는다"면 먼저 이걸 확인한다.

```
/hooks          → 비관리 훅을 리뷰하고 trust (최초 1회)
```

비대화형 실행은 `codex exec --dangerously-bypass-hook-trust …`. `config.toml [features] hooks=true`는 0.145.0에서 **불필요**하다(stable·기본 활성).

### Codex — `AGENTS.md`가 잘려 로드된다 (`project_doc_max_bytes`)

Codex는 global/project `AGENTS.md`를 instruction chain으로 병합하며 기본 한도가 **32 KiB**다. 초과하면 규칙이 조용히 잘린다.

```toml
# ~/.codex/config.toml
project_doc_max_bytes = 65536
```

이 저장소의 `AGENTS.md`는 축약판만 유지해 한도 안에 들어간다 — 상세는 각 `SKILL.md`로 위임한다.

### Cursor — 로컬 Agent vs Cloud Agent

- **훅은 플러그인으로 등록되지 않는다.** `install.sh`가 필수다(위 설치 매트릭스).
- **Cloud Agent는 `sessionStart`·user hooks를 지원하지 않는다** — 부트스트랩 주입이 없으므로 로컬 데스크톱 Agent를 쓴다. Cloud에서 작업해야 하면 `AGENTS.md`가 규칙을 대신 로드한다.
- Cursor는 훅 설정을 **7개 소스에서 병합**하며 `~/.claude/settings.json`·`{ws}/.claude/settings.json`도 실행한다 — 같은 훅을 Claude 설정과 중복 등록하면 **2회 발화**한다. 경로를 분리해 유지한다.

### Cursor·Antigravity — sandbox 권한 승인

기본 sandbox(`workspace_readwrite`)는 워크스페이스 밖 R/W를 차단하므로 `~/.llm-wiki/scripts/resolve-vault.sh` 호출이 실패할 수 있다. `install.sh --vault <path>`가 배치하는 `.cursor/sandbox.json`이 `~/.llm-wiki`와 볼트 경로를 허용 목록에 넣는다. Antigravity는 권한 프롬프트에서 해당 경로 접근을 **Allow** 한다.

### Windows — Git Bash 또는 WSL bash가 PATH에 필요

공유 스크립트와 훅은 전부 `.sh`(bash)다. `hooks/run-hook.cmd`가 cmd.exe에서 bash로 위임하는 폴리글랏 런처이지만, **bash 자체는 PATH에 있어야 한다.**

```
run-hook.cmd: bash를 찾을 수 없습니다. Git Bash 또는 WSL bash를 PATH에 추가하세요.
```

이 메시지가 보이면 Git for Windows 또는 WSL을 설치한다. Codex의 플러그인 훅은 비Windows 전제다. `.ps1`/`.bat` 패리티 버전은 향후 보완 항목이다.

## 철학

- **RAG가 아니라 영속 마크다운** — 벡터 인덱스는 선택적 검색 캐시일 뿐, source of truth는 항상 파일 본문이다.
- **사람이 방향타를 쥔다** — 에이전트는 채우고 연결하지만, 무엇을 넣을지·어떤 질문을 던질지는 사람이 정한다.
- **출처 없는 주장은 없다** — 모든 사실은 `(출처: [[page]])` 아니면 `⚠️ unverified`. 충돌은 임의로 해소하지 않고 `## Conflicts`로 표면화한다.
- **raw/는 불변** — 소스를 고치고 싶으면 볼트 밖에서 고쳐 재-ingest한다.
- **우아한 강등** — 훅이 없는 플랫폼(Antigravity)에서도 규칙 자체는 AGENTS.md로 계속 적용된다.

## 개발

```bash
bash tests/run.sh          # 스크립트 단위 테스트
for t in tests/hooks/test-*.sh; do bash "$t"; done   # 훅 테스트
```

## 업데이트

`install.sh`는 멱등이며 symlink 기반이라 설치본이 drift하지 않는다. `git pull` 후 재실행하면 최신 상태가 반영된다.

## 라이선스

MIT License — [LICENSE](LICENSE) 참조.
