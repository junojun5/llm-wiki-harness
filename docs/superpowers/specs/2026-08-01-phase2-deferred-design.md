# Phase 2 보류 3건 — 설계

**작성:** 2026-08-01 · **상태:** 리뷰 대기 · **선행 조건:** Phase 3 §1 시나리오 나머지 5스킬 E2E 완료 후 착수

Phase 2(스펙↔구현 정합화) 완료 시점에 의도적으로 남긴 3건을 닫는 설계다. 세 항목은 서로 독립이고 성질이 다르다 — 하나는 코드 작업, 하나는 결정, 하나는 자동화다.

| # | 항목 | 성질 | 결론 |
|---|---|---|---|
| 1 | resolver python3 부재 시 오진 + 가드 fail-open | 코드 + 스펙 개정 | **고친다** (§1) |
| 2 | shell `COMMAND` 문자열 내 상대경로 차단 | 스펙 결정 | **폐기** — 현행 유지 (§2) |
| 3 | `run-hook.cmd` Windows 분기 실기 미검증 | 자동화 | **CI로 검증** (§3) |

---

## 1. resolver python3 부재 — 오진 + fail-open

### 1-1. 실측 진단 — 결함은 하나가 아니라 둘

`python3`가 없는 머신에서 두 가지가 따로 일어난다.

**(a) 오진.** `scripts/resolve-vault.sh:40`이 `python3 - "$CONFIG" ... 2>/dev/null`로 stderr를 삼킨다. python3가 없으면 `PARSED`가 빈 값이 되고, 68행이 이를 파싱 실패로 해석해 `E_INVALID_CONFIG: config 파싱에 실패했습니다. wiki-setup 스킬을 --repair로 실행하세요`를 낸다. **실제 원인은 런타임 부재이므로 `--repair`로는 해결되지 않는다.** 사용자는 안내를 따라도 같은 자리를 맴돈다.

**(b) fail-open.** 두 가드 훅이 resolver 실패를 "볼트 밖 세션"으로 해석해 통과한다.

```
hooks/wiki-protect-raw.sh:13         resolve-vault.sh ... || exit 0
hooks/wiki-validate-frontmatter.sh:8  resolve-vault.sh ... || exit 0
```

(b)는 python3보다 넓은 문제다. resolver 실패 **전부**가 이 경로를 탄다 — 볼트 안에서 config가 깨졌거나(`E_INVALID_CONFIG`) 서명이 없어도(`E_NOT_A_VAULT`) `raw/` 보호와 frontmatter 검증이 함께 조용히 풀린다.

**(c) 부수 발견 — `session-start`가 조용히 오작동한다.** `hooks/session-start:11`이 self 경로를 python3 `os.path.realpath`로 구한다. python3가 없으면 `SELF`가 빈 값이 되고, 12행의 `ROOT`가 `dirname ""`=`.` 기준으로 잡혀 **CWD의 부모**를 가리킨다. `set -e`가 없어 그대로 진행하므로 19행의 `[ -e "$ROOT/scripts/$f" ]`가 실패하고 **런타임 부트스트랩 ①이 no-op**한다. 실패도 경고도 없다.

### 1-2. python3 없을 때 죽는 방식이 셋으로 갈린다

| 구성요소 | python3 지점 | 실패 방식 |
|---|---|---|
| wiki 스킬 12종 | Step 0의 `resolve-vault.sh` | **fail-closed** — 중단. AGENTS.md Step 0이 "exit ≠ 0 → 중단"이라 안전하게 멈춘다 |
| `wiki-protect-raw.sh` | 판정 블록(24) · Cursor deny 출력(86) | **fail-open** — 가드 없음 |
| `wiki-validate-frontmatter.sh` | 경로 추출(18) → `validate-frontmatter.sh` | **fail-open** — 검증 없음 |
| `hooks/session-start` | realpath(11) · Cursor 판별(46) · **출력 페이로드(57)** | **조용히 오작동** — 부트스트랩·주입 모두 |
| `build-link-graph.sh` · `validate-frontmatter.sh` | 본체 | 실행 불가 |

**스킬이 fail-closed라는 점이 위험의 크기를 좁힌다.** 스킬이 Step 0에서 멈추므로 스킬을 경유한 wiki 쓰기는 애초에 일어나지 않는다. 가드 공백이 실제로 문제가 되는 건 **스킬 밖에서 에이전트가 손으로 `raw/`를 건드리는 경우**뿐이다.

### 1-3. 왜 가드 훅을 차단으로 바꾸지 않는가

검토했고 기각했다. 근거 둘.

**관할.** 두 훅은 **글로벌**이다(`wiki-protect-raw.sh:3`). 플러그인을 설치한 순간부터 이 머신의 모든 세션·모든 도구 호출에 발화한다. 볼트를 안 쓰는 프로젝트에서 resolver는 **항상** `E_NO_CONFIG`로 실패하므로, 실패를 차단으로 해석하면 **무관한 모든 작업의 쓰기가 막힌다.** 훅 주석 4행이 "무관 프로젝트 오탐 방지"라고 명시한 그대로다. 또한 가드가 차단하는 대상은 `RAW_ABS = VAULT_ROOT/RAW_DIR`(17행)이라는 구체적 절대경로이므로, 볼트를 resolve하지 못하면 **지킬 대상 자체가 정의되지 않는다**.

**판정 불능.** 훅의 경로 판정 블록 자체가 python3다(`wiki-protect-raw.sh:24`, `wiki-validate-frontmatter.sh:18`). python3가 없으면 "이 쓰기가 `raw/`를 향하는가"를 **판정할 수 없다.** 따라서 차단으로 돌린다는 건 `raw/`만 골라 막는 게 아니라 **볼트 안의 모든 쓰기를 막는 것**이 된다. 1인 로컬 볼트에서 조용한 가드 공백보다 작업 전면 중단이 더 아프다.

셸로 경로 판정을 재구현하는 길(jq 없이 JSON 파싱)도 기각한다 — `wiki-protect-raw.sh:19-23`이 명시적으로 피한 방향이고, 두 훅의 추출 규칙 동일성 유지 부담이 늘어난다(한쪽 탐색 범위만 좁으면 그쪽 검증이 조용히 죽는 것이 Codex `apply_patch`에서 실제로 발생했다).

**결론:** python3 부재는 매 쓰기마다의 문제가 아니라 **머신 설정 문제**다. 런타임 가드를 우아하게 강등시키려 애쓰는 대신 **세션 시작에 한 번 크게 알린다.**

### 1-4. 설계 — 순수 셸 전문(preamble)

**핵심 통찰 1: 고정 문자열 경고에는 파서가 필요 없다.** 메시지가 정적이고 이스케이프를 우리가 통제하므로 `printf`로 JSON을 직접 쓸 수 있다.

**핵심 통찰 2: 게이트 위치가 스팸 방지를 공짜로 준다.** `resolve-vault.sh`는 (1) 위치 판정(27~36행: `find_config_upward` + 전역 포인터 + `head` — **전부 순수 셸**) → (2) 파싱(40행: python3) 순서다. 게이트를 **(1) 뒤, (2) 앞**에 두면:

- 볼트가 아예 없는 머신 → 현행대로 `E_NO_CONFIG`. python3를 볼 일도 없다.
- 볼트는 있는데 python3가 없음 → `E_NO_RUNTIME`.

즉 **`E_NO_RUNTIME`이 곧 "이 머신에 볼트가 있다"를 함의**하므로, 이 코드에만 반응하면 무관한 프로젝트에서는 경고가 나가지 않는다. 별도 스팸 방지 로직이 필요 없다.

#### 변경 1 — `scripts/resolve-vault.sh`

위치 판정 직후, 파싱 직전에 게이트를 넣는다.

```bash
# --- 2) 런타임 게이트 — 파싱 전. 위치 판정(1)은 순수 셸이므로 볼트 없는 머신은
#        여기 오지 않고 E_NO_CONFIG로 끝난다. 이 코드는 "볼트는 있다"를 함의한다.
command -v python3 >/dev/null 2>&1 \
  || fail 7 E_NO_RUNTIME "python3가 필요하지만 PATH에 없습니다. wiki 스킬과 가드 훅이 비활성입니다 — --repair로는 해결되지 않습니다"
```

`fail()`은 기존 함수를 그대로 쓴다(stderr 첫 줄 `E_CODE: 메시지` 계약 유지). exit code는 기존 표에서 비어 있는 **7**.

#### 변경 2 — `hooks/session-start`

**(2-a) 11행의 realpath를 순수 셸로.** python3 없이도 `ROOT`가 옳아야 경고까지 살아서 오고, 부트스트랩 ①도 정상 동작한다.

```bash
# python3 비의존 realpath — symlink 1단 해석. 플러그인 캐시·install.sh 배치 모두 1단이다.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _t="$(readlink "$SELF")"
  case "$_t" in /*) SELF="$_t" ;; *) SELF="$(dirname "$SELF")/$_t" ;; esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
```

**(2-b) resolver exit 7을 분기해 고정 경고를 낸다.** 23행의 `|| exit 0`을 exit code 분기로 바꾼다.

```bash
RESOLVED="$(bash "$LLMWIKI/resolve-vault.sh" 2>/dev/null)"; RC=$?
if [ "$RC" -eq 7 ]; then
  read_payload                # stdin 읽기를 이 분기 안에서만 한다 (아래 근거)
  case "$INPUT" in *cursor_version*) PLATFORM="cursor" ;; esac
  emit_runtime_warning        # printf 고정 JSON, python3 불필요
  exit 0
fi
[ "$RC" -eq 0 ] || exit 0     # 그 외 실패는 현행대로 조용히 (부트스트랩만)
```

**⚠️ stdin 읽기 순서가 중요하다.** 현행 스크립트는 stdin을 38~45행에서 읽는데, 이는 resolver 호출(23행)보다 **뒤**다. exit 7 분기를 23행에 두면 그 시점에 `INPUT`이 아직 비어 있어 Cursor 판별이 불가능하다. 그렇다고 stdin 읽기를 스크립트 앞으로 끌어올리면 **볼트 밖 세션도 읽기 비용을 낸다** — 34~37행 주석이 경고하듯 페이로드가 오지 않는 경로에서 줄당 최대 2초를 기다리므로, 무관한 프로젝트의 세션 시작이 매번 느려진다. 따라서 읽기 로직을 `read_payload()` 함수로 추출해 **exit 7 분기 안에서만** 호출한다. 현행 38~45행 위치의 호출은 그대로 둔다(정상 경로).

**(2-c) 플랫폼 판별 폴백.** 46행의 Cursor 판별이 python3다. 경고 경로에서는 순수 셸 부분 일치(`*cursor_version*`)로 대체한다 — 고정 메시지 전달에는 충분하다. 정상 경로는 기존 python3 판별을 유지한다(엄격한 JSON 검사가 필요한 곳이다).

**(2-d) 경고 페이로드.** 57행의 python3 빌더와 **같은 포맷**을 손으로 쓴다. 포맷은 2026-07-31 실측 확정(§5-1)을 따른다 — Claude·Codex는 `hookSpecificOutput.additionalContext`, Cursor는 래퍼 없는 `additional_context`.

```bash
emit_runtime_warning() {
  _m="<EXTREMELY_IMPORTANT>\npython3를 PATH에서 찾을 수 없습니다. LLM Wiki의 스킬 12종과 가드 훅 2종이 모두 비활성입니다 — raw/ 쓰기 보호와 frontmatter 검증이 동작하지 않습니다. python3를 설치한 뒤 세션을 다시 시작하세요. wiki-setup --repair로는 해결되지 않습니다.\n</EXTREMELY_IMPORTANT>"
  case "$PLATFORM" in
    cursor) printf '{"additional_context":"%s"}\n' "$_m" ;;
    *)      printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$_m" ;;
  esac
  printf 'E_NO_RUNTIME: python3 부재 — LLM Wiki 스킬·가드 훅이 비활성입니다\n' >&2
}
```

경고를 **주입 컨텍스트와 stderr 양쪽**에 낸다. 주입은 에이전트가 읽어 사용자에게 설명할 수 있게 하고, stderr는 사용자가 직접 본다. 메시지에 따옴표·개행 리터럴을 넣지 않으므로 JSON 이스케이프 문제가 없다(`\n`은 JSON 이스케이프 시퀀스로 그대로 나간다).

#### 변경 3 — 가드 훅 2종: 무변경

`|| exit 0`을 유지한다. §1-3의 근거대로 차단으로 바꾸지 않는다. 다만 **주석에 근거를 남긴다** — 다음 사람이 "이거 fail-open인데?"로 다시 발견하지 않게.

```bash
# resolver 실패 → 조용히 통과. exit 7(E_NO_RUNTIME) 포함 — 판정 블록 자체가 python3라
# 차단으로 돌리면 raw/만 골라낼 수 없고 볼트 안 전체를 막는다. 고지는 session-start가 1회 담당.
```

#### 변경 4 — 스펙 개정 (코드보다 선행)

`docs/specs/spec.md`:

1. **§3-2 exit code 표에 1행 추가** — `| 7 | E_NO_RUNTIME | python3가 PATH에 없음 (위치 판정은 통과했으므로 볼트는 존재) | "python3를 설치하세요. --repair로는 해결되지 않습니다" |`
2. **§1의 문구 갱신** — 현재 "표준 exit code 6종(OK + `E_*` 5종)"(63행)을 **7종(OK + `E_*` 6종)**으로.
3. **§3-2 본문에 게이트 위치 규정 추가** — "런타임 게이트는 위치 판정 뒤·파싱 앞에 둔다. `E_NO_RUNTIME`은 볼트 존재를 함의하므로 소비자가 스팸 없이 분기할 수 있다."
4. **§5-0/§5-1에 session-start의 exit 7 분기 명시** — 부트스트랩 ①은 python3 비의존이어야 한다는 요구를 포함.
5. **§5-2에 가드 훅의 fail-open 근거 명시** — 현재 "resolver 실패(볼트 없음/무효) → 조용히 통과"만 있고 *왜*가 없다. 관할·판정불능 두 근거를 넣는다.

### 1-5. 테스트

`tests/scripts/test-resolve-vault.sh`와 `tests/hooks/test-session-start.sh`에 추가한다. python3 은닉은 **`PATH`를 화이트리스트 디렉터리 하나로 좁혀** 만든다(실환경 훼손 없음).

**은닉 방법에 함정이 있다.** `PATH="$TMP/nopy:/usr/bin:/bin"`처럼 뒤에 실경로를 붙이면 `/usr/bin/python3`가 그대로 보여 은닉이 실패한다. python3 shim을 앞에 두는 것도 안 된다 — 파일이 존재하면 `command -v python3`가 **성공**하므로 부재를 재현하지 못한다. 따라서 PATH를 `$TMP/nopy` **단독**으로 두고, 스크립트가 실제로 쓰는 외부 명령만 symlink한다:

```bash
mkdir -p "$TMP/nopy"
for c in bash dirname head sed readlink ln mkdir cat env; do
  ln -sf "$(command -v "$c")" "$TMP/nopy/$c"
done
PATH="$TMP/nopy"    # python3 부재
```

목록에서 빠진 명령이 있으면 테스트가 **시끄럽게** 실패한다(조용한 통과가 아니다) — 이 방향의 실패는 안전하다.

| # | 대상 | 단정 |
|---|---|---|
| 1 | resolver, 볼트 있음 + python3 없음 | exit **7**, stderr 첫 줄 `E_NO_RUNTIME:` 접두 |
| 2 | resolver, 볼트 없음 + python3 없음 | exit **2** `E_NO_CONFIG` — 게이트가 위치 판정을 앞지르지 않음 |
| 3 | resolver, 정상 | 기존 17케이스 회귀 무변경 |
| 4 | session-start, python3 없음 + 볼트 안 | exit 0 · stdout에 `additionalContext` + 경고 문구 · stderr에 `E_NO_RUNTIME` |
| 5 | session-start, python3 없음 + Cursor 페이로드 | stdout이 `additional_context`(래퍼 없음) 포맷 |
| 6 | session-start, python3 없음 + 볼트 없음 | **무성** — stdout·stderr 공백, exit 0 |
| 7 | session-start, python3 없음, symlink 경유 실행 | `ROOT`가 옳게 잡혀 부트스트랩 symlink 3개 생성 |
| 8 | 가드 훅 2종, python3 없음 + 볼트 안 | exit 0 통과 (의도된 fail-open 고정) |

7번이 (2-a)의 회귀 방지다 — 마켓플레이스는 플러그인 캐시를, install.sh는 `~/.claude/hooks/`를 symlink로 가리킨다.

### 1-6. 문서

- `README.md` 요구사항 — python3를 **하드 요구**로 명시하고, 없을 때의 동작(세션 시작 경고 + 스킬·가드 비활성)을 1줄 기술.
- `docs/troubleshooting.md` — 현재 경고만 있는 `python3` 항목을 `E_NO_RUNTIME` 기준으로 재작성. "왜 `--repair`가 안 듣는가"를 포함.

---

## 2. shell `COMMAND` 내 상대경로 — 폐기

**결론: 고치지 않는다. 계획서 T1의 해당 검증 항목을 폐기 처리한다.**

`docs/specs/spec.md:2382`가 이미 명시적 비목표로 선언했다.

> **`COMMAND` 내 상대경로는 여전히 탐지하지 못한다.** `TARGET`은 `BASE` 기준으로 절대화하지만, `printf 'x' > raw/a.md` 같은 셸 명령 문자열 안의 상대경로는 파싱하지 않는다(셸 문법 전면 해석은 비목표). accident-prevention 수준의 알려진 구멍이다.

바로 다음 줄(2383)이 `rm` 복합 명령 우회도 같은 근거로 비목표 선언한다 — 이 훅은 **accident-prevention 수준**이고 적대적 우회는 표적이 아니다. 1인 로컬 전제 + Content Trust Boundary(§4-2) + AGENTS.md 규칙 병행이 근거다.

`docs/plans/2026-07-31-spec-implementation-sync.md`의 T1 검증 목록이 이와 충돌했으나, `docs/plans/`는 정본 계층 밖이므로 **스펙이 이긴다**. 현행 통과 동작은 이미 `tests/hooks/test-wiki-protect-raw.sh:115,119`에 `[알려진 한계]` 케이스로 고정돼 있다 — 누가 나중에 "차단해야 하는데?"로 바꾸면 테스트가 잡는다.

**할 일:** 계획서 T1의 해당 항목에 "폐기(스펙 §5-2 비목표)" 주석 1줄. 코드·테스트 변경 없음.

**재개 조건:** 다중 사용자 환경 또는 신뢰 경계 변화. 그때는 §5-2 개정이 선행한다.

---

## 3. Windows `run-hook.cmd` — CI로 검증

**문제:** cmd.exe의 `shift`가 `%*`에 영향을 주지 않는 문제를 `%2`부터 누적하는 루프로 고쳤으나, macOS/Linux에서 cmd.exe를 실행할 수 없어 **정적 검토 + 주석으로만** 확인했다. Phase 2 T5 이래 계속 열려 있다.

**해법:** 환경 확보를 기다리지 않는다. `.github/workflows/`가 **현재 없으므로** 신설한다.

```yaml
# .github/workflows/windows.yml (설계 스케치 — 구현 계획에서 확정)
on: [push, pull_request]
jobs:
  cmd-launcher:                     # required — 보류 3번을 닫는 갈래
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: run-hook.cmd 인자 전달 검증 (cmd.exe)
        shell: cmd
        run: tests\hooks\test-run-hook-cmd.cmd

  bash-suite:                       # 정보용 — 결과를 보며 별도로 닫는다
    runs-on: windows-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      - name: 셸 스위트 (Git Bash)
        shell: bash
        run: bash tests/run.sh
```

두 갈래를 돈다:

1. **cmd.exe 네이티브** — `run-hook.cmd`가 `%1`을 스크립트명으로, `%2`부터를 그대로 전달하는지. 신규 `tests/hooks/test-run-hook-cmd.cmd`가 필요하다(현재 Unix 분기만 회귀 테스트가 있다). 인자 개수 0·1·2·3개, 공백 포함 인자, 한글 인자를 돈다.
2. **Git Bash** — `windows-latest`에 Git Bash가 기본 포함되므로 기존 `tests/run.sh`를 그대로 돌린다. README가 1차 지원 경로로 Git Bash/WSL을 요구하므로 그 요구가 실제로 참인지 검증된다.

**기대 효과:** Phase 2 T5부터 열려 있던 항목이 닫히고, 이후 `run-hook.cmd`를 건드릴 때마다 자동 검증된다. `distribution-design.md` §10의 Windows 항목도 "정적 검토만"에서 "CI 검증"으로 갱신된다.

**필수/선택 경계 — 확정.** cmd.exe 갈래만 **required**로 두고, Git Bash 갈래는 `continue-on-error: true`로 시작한다.

근거: 2번 갈래는 처음부터 통과하지 않을 가능성이 실재한다 — 경로 구분자·`realpath`·symlink 동작이 다르고, 이 설계의 §1-4 (2-a)가 도입하는 `readlink` 루프도 Windows symlink에서 다르게 돈다. **통과하지 않으면 그건 이 설계의 실패가 아니라 발견이다.** 다만 이 레포에 CI가 전무한 상태에서 첫 CI가 빨간불로 시작하면 신호가 죽는다(빨간불에 익숙해지면 CI가 무의미해진다). 그래서:

- **보류 3번은 cmd.exe 갈래 통과로 닫는다** — 그게 정확히 미검증이던 대상이다.
- Git Bash 갈래는 결과를 보며 실패 항목을 별도 이슈로 분리해 따로 닫는다. 전부 통과하면 그때 `continue-on-error`를 제거하고 required로 승격한다.
- **승격 조건을 문서에 남긴다** — 안 그러면 `continue-on-error`가 영구화되고 "Windows 지원"이 검증 없는 주장으로 남는다.

---

## 4. 구현 순서

1. **스펙 개정 먼저** (§1-4 변경 4) — 코드보다 스펙이 선행한다. `E_NO_RUNTIME` 정의·게이트 위치 규정·훅 fail-open 근거.
2. **`resolve-vault.sh` 게이트** + 테스트 1~3 (RED → GREEN)
3. **`session-start` 순수 셸화** (realpath → exit 7 분기 → 경고 페이로드) + 테스트 4~7
4. **가드 훅 주석** + 테스트 8
5. **문서** — README 요구사항 · troubleshooting `E_NO_RUNTIME`
6. **계획서 T1 폐기 주석** (§2)
7. **Windows CI** (§3) — 앞의 것들과 독립이므로 병렬 가능

1~5는 한 덩어리다(스펙↔코드↔테스트가 같은 계약을 공유). 6은 주석 1줄. 7은 별도 PR이 깔끔하다.

## 5. 비목표

- 가드 훅을 차단으로 전환 — §1-3에서 근거와 함께 기각
- 셸만으로 JSON 경로 판정 재구현 — 취약하고 두 훅 동일성 부담
- python3 외 런타임(`jq` 등) 지원 추가 — YAGNI. python3는 이미 4플랫폼에서 하드 요구다
- `.ps1`/PowerShell 대응본 — `distribution-design.md` §10대로 네이티브 수요 확인 후
- `chmod` 기반 파일시스템 강제 — spec §5-2가 Phase 1 비목표로 선언

## 6. 결정 이력

| 결정 | 선택 | 근거 |
|---|---|---|
| 가드 훅을 차단으로 전환할지 | **아니오** — fail-open 유지 | 훅이 글로벌이라 차단 해석이 머신 전체를 막고, 판정 블록 자체가 python3라 `raw/`만 골라낼 수 없다 (§1-3) |
| python3 부재를 어디서 알릴지 | **session-start 1회** | 매 쓰기의 문제가 아니라 머신 설정 문제 (§1-3) |
| 런타임 게이트 위치 | **위치 판정 뒤 · 파싱 앞** | `E_NO_RUNTIME`이 "볼트 존재"를 함의해 스팸 방지가 공짜로 따라온다 (§1-4) |
| shell `COMMAND` 상대경로 | **폐기** | spec §5-2가 비목표로 선언. `docs/plans/`는 정본 계층 밖 (§2) |
| Windows CI 필수 범위 | **cmd.exe만 required** | 보류 3번의 대상은 cmd.exe 갈래다. 첫 CI가 빨간불로 시작하면 신호가 죽는다 (§3) |

미결 항목 없음.
