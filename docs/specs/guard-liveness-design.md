# 가드 생존 점검 설계 — `check-guards.sh` + `wiki-status` 통합

**작성일:** 2026-08-04
**상태:** 설계 (구현 대기)
**계기:** Windows CI(run `30875915051`)에서 `install.sh`의 `render()`가 cp1252로 죽어 훅 등록 파일이 **0바이트로 남는** 결함이 나왔다. 설치는 성공한 것처럼 보이고 가드만 조용히 죽는다. 그 상태를 **아무도 검증하지 않는다**는 것이 이 설계의 출발점이다.
**관련:** 스펙 §5-0·§5-2·§5-3·§5-4·§3-9 · 배포 설계 §10

---

## 1. 문제

AGENTS.md는 단언한다 — "훅이 raw/ 쓰기를 기계적으로 차단한다." 이 단언을 뒷받침하는 **런타임 점검이 레포에 없다.**

확인한 현황:

| 경로 | 훅 생존을 보는가 | 근거 |
|---|---|---|
| `wiki-status` | ❌ 훅을 한 글자도 언급하지 않음 | SKILL.md grep 0건 |
| `wiki-setup --repair` | ❌ 책임 범위가 "config 재검증 + `index.md`·`log.md`·`hot.md` 복구"까지 | SKILL.md:98·148 |
| Step 0 Config Gate | ❌ 볼트 config만 본다 | `resolve-vault.sh`는 훅을 모른다 |

### 1-1. 왜 이게 특히 위험한가 — 상관된 실패

`wiki-protect-raw.sh:13`은 resolver 실패 시 **의도적으로 통과**시킨다(fail-open). 이 결정 자체는 옳다 — resolver가 죽으면 `RAW_ABS`가 정의되지 않아 "이 쓰기가 raw/를 향하는가"를 가릴 수 없고, 그때 fail-closed로 돌리면 raw/만 골라 막는 게 아니라 **볼트 안 모든 쓰기를 막게** 된다.

문제는 fail-open이 아니라 **그것이 침묵한다는 사실을 알아챌 방법**이다. 현재 설계는 보상 장치를 `session-start`의 세션 1회 고지에 두는데(§5-2 "강등 지점과 고지 지점을 분리"), 그 고지 역시 **같은 훅 시스템 위에 산다**:

```
가드 침묵  ←  훅 미등록 / 등록 파일 0바이트 / resolver 실패
   ↓ 누가 알려주나?
session-start 고지  ←  같은 원인으로 함께 죽는다
```

Windows 건이 정확히 이 모양이었다. `hooks.json`이 0바이트가 되면 가드도 고지도 동시에 사라지고, 사용자는 무신호 상태에서 "보호되고 있다"고 믿는다. **독립적이어야 할 두 방어선이 실패 원인을 공유한다.**

따라서 세 번째 방어선은 **훅 시스템 밖**에 있어야 한다. 스킬은 에이전트가 직접 실행하므로 훅 등록과 무관하게 돈다 — 그래서 `wiki-status`다.

---

## 2. 설계 원칙

### 2-1. 검증 가능한 것과 불가능한 것을 먼저 가른다

훅이 "살아 있다"는 말은 세 층으로 나뉜다:

| 층 | 의미 | 스킬이 검증 가능한가 |
|---|---|---|
| **배치** | 훅 스크립트가 디스크에 있는가 | ✅ |
| **등록** | 에이전트가 읽는 설정에 command가 적혀 있는가 | ✅ |
| **발화** | 에이전트 런타임이 실제로 그것을 호출하는가 | ❌ **불가능** |

발화는 에이전트 소관이다. 실례로 **Codex의 `/hooks` trust 미완**은 등록은 정상이면서 발화하지 않는 상태이고(무경고 no-op), 이 점검으로는 절대 검출되지 않는다.

> **이 경계를 리포트에 반드시 명시한다.** 안 그러면 "초록불인데 여전히 안 막힌다"가 되고, 점검 자체가 새로운 거짓 안심이 된다.

### 2-2. 두 층으로 나눠 본다 — L1과 L2는 서로를 대체하지 못한다

| | L1 등록 건강 | L2 판정 정확성 |
|---|---|---|
| **묻는 것** | 등록이 살아 있는가 | 훅 본체가 옳게 판정하는가 |
| **잡는 결함** | 0바이트 파일 · 미등록 · 끊긴 참조 | 플랫폼별 로직 결함(Windows 미검증 영역) |
| **놓치는 것** | 파일은 멀쩡한데 로직이 깨진 경우 | 본체는 옳은데 등록이 안 된 경우 |

둘 다 필요하다. L2가 초록불이어도 등록이 없으면 실사용에서 안 돌고, L1이 초록불이어도 본체가 깨졌으면 통과시킨다.

---

## 3. L2 — 합성 페이로드 프로브 (핵심)

훅 본체에 **가짜 페이로드를 직접 먹여** 판정 결과를 확인한다. 에이전트 런타임을 거치지 않으므로 스킬에서 실행 가능하다.

### 3-1. 실증 (2026-08-04, macOS에서 확인)

```bash
P="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT/raw/__guard_probe__.md\"}}"
printf '%s' "$P" | (cd "$VAULT" && bash <훅경로>/wiki-protect-raw.sh claude)
```

| 프로브 | 기대 | 실측 |
|---|---|---|
| `raw/` 대상 쓰기 | exit 2 + stderr 안내 | ✅ `exit=2`, `raw/는 읽기 전용입니다…` |
| `wiki/` 대상 쓰기 | exit 0 (오탐 없음) | ✅ `exit=0` |
| **볼트 부작용** | 0건 | ✅ `raw/`에 생긴 파일 **0개** |

**음성 대조군(`wiki/` 프로브)이 반드시 함께 가야 한다.** 양성만 보면 "무조건 차단"하는 고장 난 훅도 초록불로 통과한다.

### 3-2. read-only 경계 준수

AGENTS.md의 read-only 경계는 "지식 콘텐츠를 바꾸지 않는다"이다. L2 프로브는:

- 훅에 **경로 문자열만** 넘긴다. 훅은 판정만 하고 파일을 만들지 않는다(실측 확인).
- 프로브 경로는 **실재하지 않는 파일**(`raw/__guard_probe__.md`)을 가리킨다.
- `raw/` 불변 규칙과 무관하다 — 쓰기 시도가 아니라 판정 요청이다.

### 3-3. 기각 — frontmatter 가드는 L2 대상에서 뺀다

`wiki-validate-frontmatter.sh`는 페이로드 경로의 **파일 내용을 실제로 읽어** 검증한다. 프로브하려면 `wiki/` 안에 임시 페이지를 써야 하고, 그 순간 read-only 경계를 넘는다. 볼트 밖 `mktemp`에 쓰면 "`wiki/` 안 경로"라는 발화 조건을 못 맞춘다.

→ **frontmatter 가드는 L1(배치·등록)만 본다.** 비대칭이지만 경계를 넘는 것보다 낫다.

---

## 4. L1 — 등록 건강

### 4-1. "없음"의 세 가지 의미를 구분한다 (오탐 방지의 핵심)

가장 중요한 설계 지점이다. 등록 파일이 없다고 전부 경고면 이 점검은 **한 달 안에 무시된다.**

| 상태 | 판정 | 표시 |
|---|---|---|
| 도구 경로 자체가 없음 (`~/.cursor` 없음) | 그 도구를 안 쓴다 | `➖ 미설치` (정상) |
| 도구는 있는데 등록 파일 없음 | 설치 누락 | `⚠️ 미등록` |
| 등록 파일 있는데 **0바이트 / JSON 파싱 실패** | **이번 결함** | `❌ 손상` |
| 등록됐는데 command 경로가 실재하지 않음 | stale symlink · 버전 이동 | `❌ 끊긴 참조` |
| 등록 + 참조 실재 | 정상 | `✅` |

### 4-2. 플랫폼 매트릭스

install.sh 실측 기준. **`~/.claude/llm-wiki-hooks.settings.json`의 존재는 등록이 아니다** — 그건 수동 머지 *안내* 파일이다. 이 함정을 놓치면 이번 결함이 그대로 거짓 초록불이 된다.

| 플랫폼 | 등록 파일 | 훅 본체 | 주의 |
|---|---|---|---|
| Claude (마켓플레이스) | 플러그인 캐시의 `hooks.json` | 플러그인 캐시 | 경로가 **버전 스코프** — 하드코딩 금지, glob으로 찾는다 |
| Claude (`--fallback`) | `~/.claude/settings.json`의 hooks 블록 | `~/.claude/hooks/` | 스니펫 파일이 아니라 **settings.json 본체**를 봐야 한다 |
| Codex | `~/.codex/hooks.json` | `~/.agents/hooks/` | 등록돼도 `/hooks` trust 전엔 발화 안 함 → §2-1 경계 |
| Cursor (전역) | `~/.cursor/hooks.json` | `~/.cursor/hooks/` | Cursor는 이 경로가 훅의 **유일한** 등록 수단 |
| Cursor (볼트) | `$VAULT/.cursor/hooks.json` | `$VAULT/.cursor/hooks/` | |
| Antigravity | — | — | 훅 스키마 미공개 → 항상 `➖ 해당 없음` |

### 4-3. 플랫폼 판별

스크립트는 자기를 호출한 도구를 모른다. 두 갈래로 처리한다:

- **기본 = auto.** 존재하는 등록 경로를 **전부** 스캔한다. 사용자가 여러 도구를 쓸 수 있고, "지금 이 도구는 멀쩡한데 Cursor는 죽어 있다"도 알 가치가 있다.
- `--platform claude|codex|cursor|antigravity` — SKILL.md가 **실행 중인 자신**을 넣는다. 해당 플랫폼을 강조 표시할 뿐, 다른 플랫폼을 숨기지 않는다.

---

## 5. 구현

### 5-1. 코드 위치 — `scripts/check-guards.sh` 신설

`scripts/`가 4개 플랫폼 공용 런타임의 단일 출처이고 `~/.llm-wiki/scripts/`로 부트스트랩된다(배포 설계 §2). 결정론적 로직은 스킬 산문이 아니라 스크립트에 둔다 — `resolve-vault.sh`·`validate-frontmatter.sh`·`build-link-graph.sh` 3개가 그 선례다.

**동반 변경:**
- `install.sh:109` 부트스트랩 목록에 추가
- `hooks/session-start`의 자가-부트스트랩 목록에 추가 (마켓플레이스 경로)
- `tests/install/smoke.sh` [1]에 symlink 단언 추가

### 5-2. 출력 계약 — 기계 판독 라인

`build-link-graph.sh`의 `SUMMARY` 라인 관례를 따른다.

```
GUARD <platform> <layer> <status> <detail>
GUARD claude  L1 ok        ~/.claude/settings.json hooks 블록 3건
GUARD claude  L2 ok        raw/ 차단 · wiki/ 통과
GUARD cursor  L1 corrupt   ~/.cursor/hooks.json 0바이트
GUARD codex   L1 absent    ~/.codex 있음 · hooks.json 없음
GUARD antigravity - n/a    훅 스키마 미공개
SUMMARY guards=5 ok=2 degraded=2 skipped=1
```

`PYTHONUTF8=1`은 §3-9 계약대로 모든 python3 호출에 부여한다.

### 5-3. 종료 코드

| 코드 | 의미 |
|---|---|
| 0 | 전부 ok 또는 해당 없음 |
| 1 | degraded 1건 이상 (`corrupt`·`absent`·`broken-ref`·L2 실패) |
| 2 | 점검 자체 불가 (resolver 실패 등) — **degraded와 구분한다** |

### 5-4. `wiki-status` 리포트 통합

`### 개요` 다음에 5줄 이내로 넣는다. 정상일 때 길면 안 읽는다.

```markdown
### 가드 생존
✅ Claude — 등록 정상 · raw/ 차단 확인
❌ Cursor — ~/.cursor/hooks.json 0바이트 → **raw/ 보호가 꺼져 있습니다**
   복구: ./install.sh --fallback 재실행
➖ Codex · Antigravity — 미설치 / 해당 없음
ⓘ 발화 여부는 검증 대상이 아닙니다 (Codex는 /hooks trust 별도 필요)
```

전부 정상이면 **한 줄로 접는다**: `✅ 가드 생존 — Claude 등록·판정 정상 (발화는 미검증)`

### 5-5. read-only 스킬 경계

`wiki-status`는 read-only다. 이 점검은 페이지·index·hot·QMD를 건드리지 않고, `log.md` append만 한다(AGENTS.md 관찰 기록 허용 범위). L2 프로브의 무부작용은 §3-2에서 확인.

---

## 6. 테스트 계획 (RED→GREEN)

`tests/scripts/test-check-guards.sh` 신설.

| # | 케이스 | 기대 |
|---|---|---|
| 1 | 등록 파일 **0바이트** | `corrupt` · exit 1 ← **이번 결함 회귀 고정** |
| 2 | 등록 파일 JSON 파싱 실패 | `corrupt` |
| 3 | 도구 경로 없음 + 등록 없음 | `n/a` · exit 0 (**오탐 금지**) |
| 4 | 도구 경로 있음 + 등록 없음 | `absent` · exit 1 |
| 5 | 등록 command가 실재하지 않는 경로 | `broken-ref` |
| 6 | Claude 스니펫만 있고 settings.json에 없음 | `absent` ← **거짓 초록불 방지** |
| 7 | L2 `raw/` 프로브 | 차단 판정 |
| 8 | L2 `wiki/` 음성 대조군 | 통과 판정 |
| 9 | L2 프로브 후 볼트 파일 변화 | **0건** (read-only 계약) |
| 10 | ASCII locale(`LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0`) | 위 전부 동일 (§3-9) |
| 11 | resolver 실패 | exit 2 (degraded 아님) |

---

## 7. 기각한 대안

| 대안 | 기각 이유 |
|---|---|
| 훅이 자기 생존을 `log.md`에 기록 | **순환.** 훅이 안 도는 것이 문제인데 훅에 의존한다 |
| `session-start`가 매 세션 등록 상태 검사 | **같은 상관 실패.** session-start 자체가 미등록이면 침묵한다 (§1-1) |
| `wiki-setup --repair`가 훅까지 복구 | 책임 범위 확대 — SKILL.md:148이 경계를 명시해 뒀다. **진단과 복구를 분리**하고 복구는 `install.sh` 재실행 안내로 |
| 실제 `raw/` 파일에 써 보고 막히는지 확인 | read-only 경계 + `raw/` 불변 규칙 **이중 위반.** 절대 안 된다 |
| 가드 실패 시 fail-closed로 전환 | raw/만 골라 막을 수 없어 볼트 전체가 막힌다 (§1-1). fail-open은 유지하고 **가시성**으로 푼다 |

---

## 8. 작업 단계

| 단계 | 내용 | 검증 | 추정 |
|---|---|---|---|
| 1 | `tests/scripts/test-check-guards.sh` 11케이스 (RED) | 전부 실패 확인 | 2h |
| 2 | `scripts/check-guards.sh` 구현 (GREEN) | 11/11 통과 | 3h |
| 3 | `install.sh`·`session-start` 부트스트랩 + smoke 단언 | smoke 통과 | 1h |
| 4 | `wiki-status` SKILL.md 통합 | 리포트 형식 확인 | 1h |
| 5 | 스펙 **§5-5 신설** + AGENTS.md 요약 갱신 | 문서 정합 | 1h |

총 **1일**. 단계 1~2가 본체이고 3~5는 배선이다.

---

## 9. 열린 질문

1. **Claude 마켓플레이스 캐시 경로 탐색** — 버전 스코프라 glob이 필요한데, 여러 버전이 남아 있으면 어느 것이 활성인지 스크립트가 알 수 없다. 후보: 최신 semver 선택 vs 전부 보고. **미결.**
2. **Windows** — 이 점검 자체가 Windows에서 도는지는 별도 검증이 필요하다. MSYS symlink 시맨틱 탓에 `broken-ref` 오탐이 날 소지가 있다(배포 설계 §10의 `ln -s` 항목과 같은 부류).
3. **주기** — `wiki-status` 호출 시에만 볼 것인가, 아니면 쓰기 스킬의 종료 시퀀스에도 넣을 것인가. 후자는 비용이 붙는다. 1차는 `wiki-status` 전용을 권한다.
