# Phase 2 — 스펙↔구현 정합화 실행 계획

**작성일:** 2026-07-31
**선행:** Phase 0(플랫폼 실측) 완료 · Phase 1(스펙 전량 개정) 완료
**목표:** 개정된 스펙과 실제 구현 사이의 확인된 갭 14건을 닫는다.

---

## 0. 이 문서를 읽는 사람에게

이 계획은 **자족적**이다. 앞선 대화 맥락 없이 이 문서 + 스펙만으로 실행할 수 있다.

**정본 계층 (불일치 시 위가 이긴다):**
```
docs/specs/spec.md
  → skills/using-llm-wiki/SKILL.md (+ references/)
    → AGENTS.md  (비-Claude 도구용 축약 미러)
      → 개별 skills/*/SKILL.md
```
배포 레이어만 `docs/specs/distribution-design.md`가 정본이고, Phase 1 범위의 단일 출처는 그 문서 **§9**다.

**배경 — 왜 이 갭이 생겼나.** 스펙이 틀린 상태에서 스킬 12개를 "스펙 기반"으로 재작성했다. 커밋 메시지는 정합화를 주장하지만 실제로는 반영되지 않은 항목이 남았다(아래 T10·T11이 그 예 — 커밋 제목이 각각 "답변 라벨 한국어화", "STATUS 로그 라인"인데 둘 다 미반영). **대조 기준이 여러 곳이라 매번 달랐던 것**이 원인이므로, 이번에는 각 작업에 **기계 검증 명령**을 붙였다.

**전제:** 하네스는 현재 어떤 머신에도 설치돼 있지 않다. 따라서 아래 결함들은 지금 누구도 해치고 있지 않으며, 순서를 지킬 여유가 있다.

---

## 1. 전역 제약

- **동작 변경 금지.** 스펙에 없는 새 기능·의무를 추가하지 않는다. 이 계획은 스펙에 이미 확정된 것을 코드·문서에 반영할 뿐이다.
- **상수는 §3-8을 인용한다.** 새 매직 넘버를 코드에 직접 박지 않는다.
- **링크 표기:** 본문·인용·`Related pages`·`Conflicts`·frontmatter 전부 `[[slug]]` 파일명만. 유일 예외는 `decisions.md`의 `변경 기록: [[changes/archive/YYYY-MM-DD-{slug}]]`.
- **각 태스크 완료 시 `bash tests/run.sh` 전체 통과**를 확인한다.
- 커밋은 태스크 단위로 끊는다. 커밋 트레일러: `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

## 2. 실행 순서

의존성이 있다. **A → B → C → D** 순서를 지킨다.

| 그룹 | 태스크 | 이유 |
|---|---|---|
| **A. 공유 스크립트** | T1 | 훅이 이 스크립트에 위임하므로 먼저 |
| **B. 훅·런처** | T2 T3 T4 T5 | 페이로드 처리 로직. T6의 등록 대상 |
| **C. 배포** | T6 T7 T8 | 매니페스트·install.sh — 훅이 확정된 뒤 |
| **D. 문서** | T9 T10 T11 T12 T13 T14 | 스킬·README. 코드와 독립이라 마지막 |

---

## 3. 태스크

### T1 — `scripts/validate-frontmatter.sh` fail-loud 가드

**결함 (실측 확인).** `provenance`/`relationships`가 인라인 flow mapping(`{ a: 1, b: 2 }`)으로 오면 자체 YAML 서브셋 파서가 **문자열로 읽고**, `isinstance(prov, dict)` 게이트에 걸려 검사 블록 전체가 조용히 건너뛰어진다. 합계가 틀려도 통과한다.

실측:
```
블록 표기, 합=0.4 → "provenance 합이 1.0에서 벗어남: 0.400"  exit 1  ✅
인라인 표기, 합=0.3 → (무출력)                                exit 0  ❌
```

**작업**
- `provenance` 키가 존재하는데 dict로 파싱되지 않으면 에러: `provenance가 블록 표기가 아닙니다 (인라인 { } 표기는 검사를 무력화합니다)`
- `relationships` 키가 존재하는데 list로 파싱되지 않으면 에러: `relationships가 블록 리스트 표기가 아닙니다`
- provenance 합 허용오차를 **±0.05**로 명시 (§3-8 `PROVENANCE_TOLERANCE`, 현행 구현값과 동일 — 상수 출처만 주석으로 연결)

**검증**
```bash
# 인라인 표기 + 틀린 합 → exit 1 이어야 한다
bash scripts/validate-frontmatter.sh <인라인 fixture>; echo $?   # 1
bash tests/run.sh
```
`tests/scripts/test-validate-frontmatter.sh`에 인라인 표기 케이스 2건(provenance·relationships) 추가.

---

### T2 — `hooks/wiki-protect-raw.sh` 경로 해석

**결함 (실측 확인).** 가드가 "절대경로가 온다"고 전제하는데 실제로는 대부분 cwd 상대경로다.
- Codex `shell`: `printf 'x' > blocked.txt`
- Codex `apply_patch`: `tool_input`에 `file_path`가 **없고** `command`의 패치 본문에 `*** Add File: blocked.txt`
- 결과: `TARGET`이 비고 `COMMAND`에서 `$RAW_ABS`(절대경로) 매치도 실패 → **통과**

**작업** — 참조 구현은 spec §5-2. 요지:
- `tool_name` 추출
- 기준 디렉토리: `.cwd // .tool_input.cwd // .workspace_roots[0] // ""`, 없으면 `$PWD`
- 타깃 후보: `file_path // path // filePath // file`
- 비었고 `tool_name == "apply_patch"`면 `command`에서 `^\*\*\* (Add File|Update File|Delete File|Move to): ` 추출
- 상대경로면 기준 디렉토리로 절대화
- 차단: `cursor` → `{"permission":"deny","user_message":…}` + exit 0 / 그 외 → stderr + **exit 2**

**검증** — `tests/hooks/test-wiki-protect-raw.sh`에 추가:
```bash
# apply_patch 상대경로가 raw/ 를 가리키면 차단(exit 2)
# shell 상대경로가 raw/ 를 가리키면 차단   ← 폐기(스펙 §5-2 비목표), 아래 참조
# wiki/ 를 가리키는 상대경로는 통과(exit 0)
```

> **폐기 (2026-08-04):** "shell 상대경로가 raw/ 를 가리키면 차단"은 이행하지 않는다. `spec.md` §5-2가 `COMMAND` 문자열 안의 상대경로를 **명시적 비목표**로 선언한다("셸 문법 전면 해석은 비목표", accident-prevention 수준 유지) — 이 계획서와 스펙이 충돌하고 `docs/plans/`는 정본 계층 밖이므로 스펙을 따랐다. 현행 통과 동작은 `tests/hooks/test-wiki-protect-raw.sh`의 `[알려진 한계]` 케이스로 고정돼 있어, 누가 차단으로 바꾸면 테스트가 잡는다. 재개 조건은 다중 사용자 환경 또는 신뢰 경계 변화이고 그때는 §5-2 개정이 선행한다. 근거: [보류 3건 설계](../superpowers/specs/2026-08-01-phase2-deferred-design.md) §2.

---

### T3 — `hooks/wiki-validate-frontmatter.sh` 추출 규칙 통일

**결함.** T2와 같은 문제 + 키 탐색 범위가 **더 좁다**(`tool_input|input` × `file_path|path|filePath`). 필드명이 어긋나면 **raw 가드는 살고 frontmatter 검증만 조용히 죽는다** — 실제로 Codex `apply_patch`에서 그 사고가 났다.

**작업.** T2와 **완전히 동일한 추출 규칙**을 쓴다. 두 훅이 갈리지 않도록 로직을 함수로 뽑거나(같은 파일에 중복 서술 시 주석으로 상호 참조) spec §5-3의 참조 구현을 그대로 따른다.

**검증** — `tests/hooks/test-wiki-validate-frontmatter.sh`에 apply_patch 페이로드로 검증이 실제 발화하는지 케이스 추가. 골든 픽스처 `tests/fixtures/codex-hooks/posttooluse-apply-patch.json` 사용.

---

### T4 — `hooks/session-start` Codex 출력 포맷

**결함 (실측 확인).** Codex에 `{"additional_context": …}`를 내보내면 `hook: SessionStart Failed`로 끝나고 **주입이 무효**가 된다. 모델은 규칙을 받지 못한다.

**작업**
- `codex` 분기를 **Claude와 동일**하게: `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":<wrapped>}}`
- `cursor` 분기는 `additional_context` 유지(실측 확인). 단 `env.LLM_WIKI_RESOLVER`의 `~`는 **확장되지 않으므로 절대경로**로 출력한다
- 페이로드에 `cursor_version` 키가 있으면 플랫폼을 cursor로 판정하는 방어 추가 (Cursor가 Claude 포맷 등록도 실행하므로 argv가 `claude`인 채 Cursor에서 발화할 수 있다)

**검증** — `tests/hooks/test-session-start.sh`의 codex 케이스를 `hookSpecificOutput.additionalContext` 기대로 교체. `additional_context` 기대 assertion은 cursor에만 남긴다.

---

### T5 — `hooks/run-hook.cmd` Windows 분기

**결함.** cmd.exe의 `shift`는 `%*`에 영향이 없다. 따라서 `run-hook.cmd session-start claude` → `bash …/session-start session-start claude` → `PLATFORM="session-start"` → `unknown platform` exit 2. **Windows에서 세 훅 전부 죽는다.**

**작업.** `%*` 대신 `%2 %3 %4 …`를 넘기거나 인자 누적 루프를 쓴다. Unix 분기(`:;` 프리픽스)는 정상이므로 건드리지 않는다.

**검증.** macOS에서 cmd.exe를 돌릴 수 없으므로 **정적 검토 + 주석**으로 남기고, README 트러블슈팅(T14)에 "Windows는 Git Bash/WSL bash가 PATH에 필요"를 명시한다. 실기 검증은 Windows 환경 확보 시 수행.

---

### T6 — 훅 등록 JSON·매니페스트

**작업**
- `hooks/hooks.json`: PreToolUse matcher `Write|Edit|Bash` → **`Write|Edit|MultiEdit|NotebookEdit|Bash`**, PostToolUse도 `MultiEdit|NotebookEdit` 추가 (현행은 MultiEdit으로 raw/에 쓰면 가드 미발화)
- `hooks/hooks-codex.json`: `_pending_probe` 마커 제거, `_comment`에서 `[features] hooks=true` 요구 삭제 + trust 미완 시 무경고 no-op 명시
- **`.agents/plugins/marketplace.json` 신설** (Codex canonical), `.codex-plugin/marketplace.json` **삭제** — Codex가 읽지 않는 죽은 파일이다
- `hooks/hooks-cursor.json`·`.cursor-plugin/plugin.json`: 플러그인 훅 자동등록 전제 제거. `.cursor-plugin/`은 `skills`만 선언하고 `hooks` 키를 뺀다(소비되지 않으므로 오해 유발). `hooks-cursor.json`은 `install.sh`가 배치하는 설정 파일로만 쓴다 — command를 `./hooks/run-hook.cmd` self-locating에서 **install.sh가 render하는 절대경로**로 전환
- `.cursor-plugin/marketplace.json` 추가 (Cursor 마켓플레이스 탐색 경로에 포함됨)

**검증**
```bash
for f in hooks/*.json .claude-plugin/*.json .codex-plugin/*.json .cursor-plugin/*.json .agents/plugins/*.json; do python3 -m json.tool "$f" >/dev/null || echo "INVALID $f"; done
grep -q 'MultiEdit' hooks/hooks.json && echo ok
[ ! -f .codex-plugin/marketplace.json ] && echo "죽은 파일 제거됨"
```

---

### T7 — `install.sh` 덮어쓰기 정책

**결함.** 헤더 L4가 "파괴적 변경은 하지 않고 안내만"이라 선언하는데 실제로는 4곳을 무조건 덮어쓴다 — `~/.gemini/config/AGENTS.md`(기존 일반 파일을 symlink로 교체) · `~/.codex/hooks.json` · `$VAULT/.cursor/hooks.json` · `$VAULT/.cursor/sandbox.json`. 게다가 가드(`[ ! -f ]`)가 6곳 중 2곳에만 있어 정책이 반반으로 갈린다.

**작업**
- **모든 대상에 `[ ! -f ]` 가드**를 붙인다
- 파일이 이미 있으면 render 결과를 `<원본명>.llm-wiki.json`으로 **옆에 두고** 머지 안내를 출력한다 (Claude 경로가 이미 쓰는 방식과 통일)
- `hooks/cursor-sandbox.template.json`의 `_comment`에서 "병합" 표현 삭제 — 실제로 병합 로직이 없다
- `--help`의 `sed -n '2,30p'` → 실제 주석 블록 끝(L22)까지로 축소. 현재 `set -euo pipefail`·변수 선언·while 루프가 도움말로 출력된다
- Cursor는 플러그인으로 훅을 못 싣으므로 **Cursor 경로에서 install.sh는 필수**임을 헤더·출력 문구에 명시

**검증** — `tests/install/smoke.sh`에 추가: 대상 파일을 미리 만들어 두고 install 실행 → **원본이 보존**되고 `.llm-wiki.json` 사본이 생기는지.

---

### T8 — Antigravity 플러그인 소스 승격

**결함.** `install.sh`가 Antigravity `plugin.json`을 **heredoc 리터럴로 생성**한다. 레포에 소스 파일이 없어 다른 3개 플랫폼과 비대칭이고, 매니페스트 변경 이력이 추적되지 않는다.

**작업.** `.antigravity-plugin/plugin.json`을 레포에 추가하고 `install.sh`는 그것을 복사하도록 바꾼다. (훅은 여전히 미포함 — 스키마 미공개)

---

### T9 — 링크·provenance 표기 정합 (스킬 문서)

**결함.** Phase 1 계획의 전역 스윕이 실패한 채 남았다.

```bash
grep -rnE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' skills/
```
현재 4건이 걸린다 — 그중 하나가 **`skills/using-llm-wiki/references/page-format.md:64`**로, "파일명만 쓴다"는 규칙을 정의하는 문서가 자기 규칙을 위반하고 있다. 나머지는 `wiki-knowledge/SKILL.md:28,30`, `wiki-ingest/SKILL.md:119`.

**작업**
- 위 4건을 `[[slug]]`로 교체
- `wiki-capture/SKILL.md`의 provenance 인라인 표기를 **블록 표기**로 교체 (T1의 가드에 걸리게 된다)
- `page-format.md`의 provenance 예시에 "인라인 표기 금지" 주의 추가

**검증**
```bash
grep -rnE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' skills/ || echo "통과"
grep -rn 'provenance: *{' skills/ || echo "인라인 표기 없음"
```

---

### T10 — `wiki-query/SKILL.md` 답변 블록 한국어화

**결함.** 스펙 §4-5는 한국어(`> 위키 기반:` / `참고 페이지:` / `공백:`)인데 SKILL.md L82-85는 **아직 영어**다. 커밋 `860571b`의 제목이 "답변 라벨 한국어화"인데 반영되지 않았다.

**작업.** 답변 포맷 블록을 스펙 §4-5와 일치시킨다. 그리고 index-only 경로가 Step 5(답변 합성)를 **거치도록** 수정한다(현행은 Step 2 → Step 6 점프라 답변 포맷·stale/proposed 라벨이 통째로 우회된다).

**검증**
```bash
grep -q 'Based on the wiki' skills/wiki-query/SKILL.md && echo FAIL || echo 통과
grep -q '위키 기반' skills/wiki-query/SKILL.md && echo 통과
```

---

### T11 — `wiki-status/SKILL.md` STATUS 로그 라인

**결함.** 스펙 §4-7 Step 7이 요구하는 로그 라인이 **아예 없다**. 워크플로가 Step 6에서 끝난다. 커밋 `6149e13` 제목이 "STATUS 로그 라인"인데 반영되지 않았다.

**작업**
- Step 7 추가: `[YYYY-MM-DD] STATUS unprocessed=N recent_ingest="{경로}" token_estimate=K`
- read-only 예외임을 명시(§3-6 — log append만 허용, 실패해도 스킬 실패 아님)
- "What to Do Next 최대 5개" → **4개** (§3-8 `NEXT_ACTIONS_MAX`, 실제 정의된 항목이 4개다)

**검증** `grep -q 'STATUS unprocessed' skills/wiki-status/SKILL.md`

---

### T12 — `wiki-lint/SKILL.md` 정합

**작업**
- **종료 시퀀스에 `hot.md` 추가.** `--fix`는 페이지·index를 쓰는 명백한 쓰기 스킬인데 현행은 log.md + QMD만 있다. 12개 쓰기 스킬 중 유일한 이탈이며 품질 체크에도 빠져 있다
- 항목 10 키를 `stale` → **`source_drift`**로 개명하고 판정을 manifest `content_hash` 기반으로 교체(mtime 제거). LINT 로그 라인의 `stale=J`도 `source_drift=J`로
- 항목 12를 서브케이스로 분리 — `type` 오타→`related_to`는 자동 수정 가능, 깨진 target·자기참조는 불가
- 리포트 heading 계층 정정(`##` 아래 `#` → `###`/`####`), placeholder 문자 충돌 해소, `concept_gaps` 이중 계상 금지 명시
- **워크플로우 번호화** — 유일하게 `Step 0…N`이 없어 Config Gate조차 산문에 묻혀 있다

**검증** `grep -q 'hot.md' skills/wiki-lint/SKILL.md` (종료 절 안에서) · `grep -q 'source_drift' skills/wiki-lint/SKILL.md`

---

### T13 — 허브 문서(`references/`) 정합

**작업**
- `derived-files.md`: log ACTION 어휘를 스펙 §3-6 표(12종)와 일치시킨다. 현재 7종만 있고 `INIT`·`QMD-RECONCILE`·`PROJECT-DESIGN`·`PROJECT-RECORD`가 빠져 있다. `hot.md` 템플릿의 `[TIMESTAMP]` → `[YYYY-MM-DD]`. Recent Activity "10개 읽고 3개 보관" 구분 명시
- `page-format.md`: `base_confidence` 표에 `project=0.8` 추가, `unknown` 0.4→**0.35**
- `project-docs.md`: 공통 원칙 8의 종료 시퀀스에 **페이지 쓰기 단계 복원**(현행 4단계 — 원본 먼저 규칙이 빠져 있다). `wiki-lint --fix` 설명을 실제 권한에 맞게 정정(현행 "frontmatter·링크 메타만 수리"인데 실제로는 index.md 등록과 **불가역 raw 삭제**도 한다)
- **`references/manifest.md` 신설** — 스펙 §3-7의 동형 스키마를 허브 레이어에 미러링. 4개 스킬이 인용한다
- `using-llm-wiki/SKILL.md`: QMD 상태 문자열 **7종**으로(embed 실패 신설), embed 조건을 실측 문자열로, verify는 stdout 판정임을 명시

**검증** `bash tests/run.sh` + 스펙 §3-6·§3-7·§3-8과 수동 대조

---

### T14 — README·best-practices

**작업**
- **문서 경로 5곳 수정** — 커밋 `b745933`에서 스펙을 `docs/specs/`로 옮기고 참조를 안 고쳤다. 두 종류다:
  - `README.md` L141-143 **저장소 트리 다이어그램** — `docs/` 아래 `spec.md`·`distribution-design.md`·`hooks-and-scripts.md`로 그려져 있으나 실제는 `docs/specs/` 하위다. 링크가 아니라 그림이라 링크 체커로는 안 잡힌다
  - `docs/best-practices.md:6` **실제 깨진 마크다운 링크 2개** — `[spec.md](spec.md)`·`[distribution-design.md](distribution-design.md)` → `specs/` 추가 필요
- **트러블슈팅 섹션 신설** (`distribution-design.md` §8 필수 8항목):
  `E_*` 코드별 복구 · QMD 미설치 Grep fallback · 훅 미등록 · **Codex `/hooks` trust 미완 시 무경고 no-op** · Codex `project_doc_max_bytes` · Cursor 로컬 vs Cloud Agent · Cursor sandbox 승인 · **Windows Git Bash/WSL 필요**
- `AGENTS.md:56`·`best-practices.md:315`가 이 섹션을 링크로 참조하고 있으므로 **끊긴 참조가 함께 해소**된다
- 설치 매트릭스에 **"Cursor는 install.sh 필수"** 반영
- 스킬 카탈로그 개수 표기 확인(12개)

**검증**
```bash
# 마크다운 링크를 소스 파일 기준 상대경로로 해석해 검사 (단순 grep은 트리 다이어그램·placeholder를 오탐/누락한다)
python3 - <<'PY'
import re,os
bad=0
for f in ["README.md","docs/best-practices.md"]:
    d=os.path.dirname(f) or "."
    for m in re.finditer(r'\[[^\]]+\]\(([^)#]+\.md)[^)]*\)', open(f).read()):
        t=m.group(1)
        if t.startswith(("http","mailto")): continue
        p=os.path.normpath(os.path.join(d,t))
        if not os.path.exists(p): print(f"BROKEN {f} -> {t}"); bad+=1
print("OK" if bad==0 else f"{bad}건 남음")
PY
# 트리 다이어그램은 링크가 아니므로 별도 확인
grep -nE '^[[:space:]│]*[├└]── (spec|distribution-design|hooks-and-scripts)\.md' README.md \
  && echo "트리 미수정" || echo "트리 OK"
grep -qi '트러블슈팅' README.md && echo "트러블슈팅 섹션 있음"
```
**착수 전 기준선:** 링크 2건 BROKEN(`docs/best-practices.md`), 트리 3줄 미수정, 트러블슈팅 섹션 없음.
> `AGENTS.md`의 `[표시명](상대경로.md)`는 index.md 엔트리 **형식 예시**이지 실제 링크가 아니다 — 검사 대상에서 제외한다.

---

## 4. 완료 판정

전부 끝나면:
```bash
bash tests/run.sh                                    # 전체 통과
grep -rnE '\[\[(wiki|summaries|concepts|knowledge|entities|projects|meetings)/' skills/   # 무출력
grep -rn 'Based on the wiki' skills/                 # 무출력
grep -rn 'provenance: *{' skills/                    # 무출력
```
그리고 스펙 §4의 스킬별 의무를 12개 SKILL.md와 1:1 수동 대조한다.

**그 다음이 Phase 3**(E2E) — 격리 샘플 볼트에서 §1 시나리오 + frontmatter 스모크 + 4플랫폼 스모크. QMD 스모크는 2026-07-31에 소진 완료라 재실행 불필요(§1).

---

## 5. 참고 — 이번에 확정된 사실의 위치

| 알고 싶은 것 | 어디 |
|---|---|
| 훅 페이로드 실측 계약 (Codex/Cursor) | spec §5-4 + `tests/fixtures/*/README.md` |
| 골든 픽스처 7건 | `tests/fixtures/{codex,cursor}-hooks/` |
| 상수 26종 | spec §3-8 |
| `.manifest.json` 스키마 | spec §3-7 |
| QMD embed/verify 판정 문자열 | spec §3-5 |
| 왜 이렇게 정했나 (결정 11건 + 실측 7건) | spec §7 결정 이력 (2026-07-31 행) |
