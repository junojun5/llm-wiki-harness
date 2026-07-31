# Phase 3b — 나머지 5스킬 E2E + 미검증 항목 소진

**환경:** macOS 25.3.0 · Claude Code · qmd 2.5.3 · python3 · bash 3.2
**범위:** `wiki-status` · `wiki-knowledge` · `wiki-project-init` · `wiki-project-design` · `wiki-project-record` + [Phase 3 리포트](2026-08-01-phase3-e2e-smoke.md) §5의 미검증 항목 4건

---

## 1. 한 줄 결론

**9스킬 전부 의도대로 동작한다 — 결함 5건을 고친 뒤부터다.** 그중 하나(`build-link-graph.sh`가 인라인 코드 스팬 안의 `[[링크]]`를 실제 링크로 계수)는 **스킬 문서의 표기 관행 자체가 유발**하는 것으로, 스킬을 정확히 따를수록 깨진 링크가 생기는 구조였다.

| 스킬 | 결과 | 핵심 확인 |
|---|---|---|
| `wiki-status` | ✅ | 미처리 1건 정확 탐지(`content_hash` 기준, mtime 미사용) · read-only 경계 **변경 파일 1개 = `log.md` 단독** · QMD 무접촉 |
| `wiki-knowledge` | ✅ | 재료 4건 종합 · Step 2.5 합성 계획 게이트 발화 · `provenance` 재계산 검산(마커가 진실) · 종료 시퀀스 순서 정확 |
| `wiki-project-init` | ✅ | 인터뷰 · `[NEEDS CLARIFICATION]` 2개(상한 5) → `status: unverified` 자동 적용 · `goals.md`는 트리거 미도달로 **의도적 미생성** |
| `wiki-project-design` | ✅ | change proposal 전 주기(proposed → 승인 → 병합 → `decisions.md` 짝 → `archive/` applied 박제) · **승인 전 AS-IS 본문 재확인** · 클래스 ② 축소셋 판정 |
| `wiki-project-record` | ✅ | 라우팅 4건(직행 결정·트러블슈팅·백로그 + design으로 넘긴 1건) · `decisions.md` append-only 불변성 · 두 출처가 `변경 기록:` 유무로 구분 |

`log.md`에 9종 라인이 전부 남았다 — `INIT INGEST STATUS KNOWLEDGE LINT QUERY PROJECT-INIT PROJECT-DESIGN PROJECT-RECORD`.

---

## 2. 소진한 미검증 항목

Phase 3 리포트 §5에서 열려 있던 항목 중 4건을 닫았다.

| 항목 | 방법 | 결과 |
|---|---|---|
| §5-1 **나머지 5스킬** | 격리 볼트에서 완주 | 위 표 |
| §5-3 **Claude SessionStart 규칙 주입** | 볼트 안 CWD로 훅 직접 호출 | 7961자 주입 — `hookSpecificOutput.additionalContext` · `<EXTREMELY_IMPORTANT>` 래핑 · frontmatter 제거 · Config Gate·`raw/` 규칙 포함. **볼트 밖 CWD에서는 stdout 0바이트** (스팸 방지 게이트 정상) |
| §5-6 **QMD refresh 실행 경로** | 샌드박스 컬렉션 등록 → 시퀀스 → 제거 | `update` → `embed`(8문서 9청크) → `get` 검증 전 구간 통과. 상태 문자열 **`QMD refreshed: update + embed + verified`**. 제거 후 레지스트리가 발견 당시(컬렉션 0개)로 원복 — **오염 0** |
| §5-8 **`wiki-query` index-only · `wiki-lint --fix`** | 각 모드 실행 | index-only는 본문 미읽고 frontmatter+`index.md`만으로 답변, `mode=index_only` 로그. `--fix`는 dry-run → `--yes`로 2건 수리, LINT 17필드 라인 기록 |

**QMD 오염 0의 근거:** 착수 시점에 사용자 레지스트리의 컬렉션이 **0개**였다(`No collections found`). 샌드박스 컬렉션을 등록해 경로를 검증하고 제거하니 "8 documents 삭제 · 8 orphaned content hashes 정리" 후 다시 0개가 됐다. Phase 3에서 이 항목을 미룬 이유(레지스트리 오염 회피)가 사라진 상태였다.

---

## 3. 발견 5건

| # | 결함 | 심각도 | 조치 |
|---|---|---|---|
| 1 | **`build-link-graph.sh`가 인라인 코드 스팬·코드 블록 안의 `[[링크]]`를 실제 링크로 계수** — 스킬 문서가 `` `[[knowledge]]` `` 표기를 산문에 쓰므로 에이전트가 그 문구를 따라 쓰면 존재하지 않는 페이지를 가리키는 `BROKEN`이 생긴다 | 🔴 | 코드 스팬·펜스 제거 후 추출 + 회귀 테스트 4건 신설 |
| 2 | **`wiki-lint --fix` 절의 자기 모순** — "relationship `type` 오타 → `related_to` 자동 적용"(2곳)과 "frontmatter 값 변경은 자동 수정 대상이 아니다"가 정면 충돌. `type` 교체는 값 변경이다 | 🔴 | append-only 규칙에 예외 1건을 명시하고 `base_confidence`·`status`·`summary`는 어떤 경우에도 자동 변경하지 않음을 못 박았다 |
| 3 | **신규 페이지가 태생적 고아가 된다** — `wiki-knowledge`·project 3종에 역링크 단계가 없다. `index.md` 등록은 마크다운 링크라 그래프가 인바운드로 세지 않고 `hot.md`는 파생물이라 계수 제외(§4-6). 스킬을 정확히 따랐는데 직후 lint가 `orphans`를 보고한다 | 🟡 | `wiki-knowledge`에 Step 5.5 역링크 + 품질 체크·안티패턴, `project-docs.md`에 공통 원칙 9(상호 링크) 신설 |
| 4 | **lint 항목 3 vs 12 소유권 불명** — `validate-frontmatter.sh`의 relationship `type` enum 위반이 `format_errors`인지 `relationship_issues`인지 미정. 항목 9에는 중복 계상 금지 노트가 있으나 이쪽은 없어 `T`와 항목별 계수가 갈릴 수 있다 | 🟡 | relationship 관련 위반은 **항목 12 소유**로 명시 |
| 5 | **쓰기 종료 시퀀스 순서를 기계적으로 강제하는 것이 없다** | ℹ️ | **미수정 — 설계로 이관.** 아래 참조 |

### 발견 5의 상세

이 세션에서 `wiki-lint --fix`를 실행할 때 `index.md`를 페이지보다 **먼저** 썼다(정본 순서는 페이지 → `index.md` → `log.md` → `hot.md`). **아무것도 잡지 않았다.** Phase 3은 mtime 오름차순으로 사후 확인했지만 훅도 테스트도 이 순서를 검사하지 않는다. 산문 규칙만 존재하므로 잘못된 순서는 조용히 통과하고, 규칙이 보호하려던 것("기록은 있는데 문서가 없는 거짓 기록")이 실제로 발생할 수 있다.

수정에는 설계가 필요하다 — mtime은 파일시스템 해상도·복사·git checkout에 취약해 판정 근거로 쓰기 어렵고, 훅은 개별 쓰기만 보고 시퀀스를 모른다. `2026-08-01-phase2-deferred-design.md`에 항목으로 이관했다.

---

## 4. 수정 내역

| 파일 | 변경 |
|---|---|
| `scripts/build-link-graph.sh` | `strip_code()` 신설 — 펜스 블록·인라인 스팬 제거 후 본문 링크 추출. frontmatter `target: "[[...]]"`는 YAML 인용이라 미경유 |
| `tests/scripts/test-build-link-graph.sh` | 코드 스팬·펜스·실제 링크·`broken=0` 4케이스 (PASS 9 → 13) |
| `skills/wiki-lint/SKILL.md` | `--fix` append-only 예외 명시 · 항목 3 vs 12 소유권 노트 |
| `skills/wiki-knowledge/SKILL.md` | Step 5.5 역링크 · 품질 체크 1항 · 안티패턴 1행 |
| `skills/using-llm-wiki/references/project-docs.md` | 공통 원칙 9(상호 링크) 신설, 기존 9 → 10 |
| `skills/wiki-project-{init,design,record}/SKILL.md` | "공통 원칙 9개" → "10개" 참조 갱신 |

**검증:** `tests/run.sh` 8스위트 **PASS 165 FAIL 0** (신규 4건 포함).

---

## 5. 격리 방법 (재사용)

```
$CLAUDE_JOB_DIR/tmp/e2e-5skills/
  home/.llm-wiki/scripts/   ← repo scripts symlink 3개 + default-vault
  vault/                    ← .wiki-config.json · raw/ · wiki/
```

훅·스크립트가 `$HOME/.llm-wiki/scripts`를 하드코딩하므로 **가짜 HOME**을 만들어 그쪽에 두고 `HOME=<sandbox>`로 호출한다. 실환경 오염 0을 두 번 확인했다 — 실홈에 `default-vault`가 생기지 않았고(착수 전에도 없었다), qmd 레지스트리도 원복됐다.

**재현:**

```bash
bash $CLAUDE_JOB_DIR/tmp/setup-sandbox.sh      # 볼트 + 가짜 HOME
bash $CLAUDE_JOB_DIR/tmp/seed-fixture.sh       # ingest 2건 + 미처리 1건
cd <vault> && HOME=<sandbox>/home bash <sandbox>/home/.llm-wiki/scripts/resolve-vault.sh
```

발견 1의 최소 재현:

```bash
mkdir -p /tmp/w && printf 'x\n\n`[[nope]]` 는 코드 스팬이다.\n' > /tmp/w/a.md
bash scripts/build-link-graph.sh /tmp/w    # 수정 전: BROKEN a.md nope / 수정 후: broken=0
```

---

## 6. 여전히 미검증

| # | 항목 | 왜 못 했나 |
|---|---|---|
| 1 | **Codex·Cursor의 PostToolUse 발화** | 등록은 확인됐으나 발화 미측정 (Phase 3 §5-2 그대로) |
| 2 | **Cursor 전역 경로**(`install.sh --fallback`) | 전역 오염 회피 |
| 3 | **Antigravity의 실제 로드·준수** | 파일 배치만 확인. agy가 읽는지는 행동으로 미확인 |
| 4 | **compact 재주입 반영** | SessionStart는 `startup` 경로만 실측 |
| 5 | **Windows**(`run-hook.cmd`) | macOS에서 cmd.exe 실행 불가 → `windows-latest` CI로 처리 예정 |
| 6 | **`ingest-url`·`wiki-capture`** | 이번 범위 밖. 9/12스킬 커버 |

앞선 4건은 [Phase 3 리포트](2026-08-01-phase3-e2e-smoke.md) §5와 `distribution-design.md` §10에서 계속 추적한다.

---

## 7. 머지 후 마켓플레이스 스모크 — 결함 1건 추가 발견

PR #11을 master에 머지(`1e31d51`)한 뒤 설치본을 검증했다.

### 발견 6 — 버전 bump 없이는 배포되지 않는다 🔴

`claude plugin update`는 **`plugin.json`의 `version` 문자열로만** 갱신 여부를 판정하고 커밋 sha는 보지 않는다.

```
마켓플레이스 클론  → 1e31d51  (머지 커밋까지 갱신됨)
설치 기록 sha      → b1d1593  (구버전)
version            → 0.1.0 → 0.1.0
결과               → "already at the latest version (0.1.0)" · 캐시 refresh 안 됨
```

**설치본으로 발견 1이 그대로 재현됐다** — 이게 배포가 안 됐다는 결정적 증거다.

```
설치본: BROKEN  a.md  nope     ← 코드 스팬을 링크로 계수 (수정 전 동작)
master : broken=0               ← 수정 반영
```

`claude plugin marketplace update`를 먼저 돌려도 결과는 같다 — 그건 카탈로그만 새로 받는다.

**이 결함의 성질은 Codex `_comment`와 같다.** 설치는 성공하고 `plugin list`도 `enabled`로 보이는데 실제 반영은 없다. 침묵으로 실패하므로 스모크 없이는 발견되지 않는다. **머지가 곧 배포가 아니라는 것**이 이 레포의 릴리스 모델이다.

### 조치

- **버전 0.1.0 → 0.2.0**, 5곳 동시 (`VERSION` · `.claude-plugin/` · `.codex-plugin/` · `.cursor-plugin/` · `.antigravity-plugin/`의 `plugin.json`). 스크립트 동작 변경(발견 1)과 스킬 절차 추가(발견 3의 Step 5.5)를 포함하므로 patch가 아니라 minor로 올렸다.
- **`tests/install/test-version-consistency.sh` 신설** — 5곳 일치 + semver 형식 + 매니페스트 JSON 유효성. "언제 올려야 하는가"는 사람의 판단이라 테스트할 수 없지만 **부분 bump는 막는다**(일부만 올리면 플랫폼마다 다른 버전이 배포된다). 훼손 주입으로 실제로 잡는 것을 확인했다.
- **`tests/run.sh` 글롭 확장** — `install/`에서 `smoke.sh`만 집던 것을 `install/test-*.sh`도 포함하도록. 안 하면 신규 테스트가 러너에서 조용히 빠진다.
- **`docs/troubleshooting.md`에 항목 추가** — 증상·원인·확인 명령·해결. `claude plugin update <name>`이 접미어 없이는 `not found`로 실패하는 것과, 런타임 홈 symlink 때문에 **스크립트는 즉시 새 버전이 되고 스킬 문서만 재시작을 기다리는 비대칭**도 함께 기록했다.

### 검증

`tests/run.sh` 9스위트 **PASS 172 FAIL 0** (`test-version-consistency` 7건 신규).

### 발견 7 — 런타임 symlink가 버전에 고정된다 🔴

발견 6을 고쳐 0.2.0을 배포한 직후, **더 심각한 결함이 드러났다.**

```
플러그인 캐시   → 0.2.0  ✅  broken=0
런타임 홈       → 0.1.0  ❌  broken=1   ← 스킬·훅이 실제로 호출하는 경로
```

`~/.llm-wiki/scripts/*`는 `.../cache/<mp>/<plugin>/<version>/scripts/*`를 가리킨다. `hooks/session-start`의 부트스트랩 ①이 `[ -e "$LLMWIKI/$f" ] && continue`라서 **존재하면 절대 갱신하지 않는다.** 구버전 캐시가 남아 있으면 `-e`가 참이므로 버전을 올려도 재지정되지 않고, **버전을 올바르게 올렸는데도 수정이 적용되지 않는다.**

발견 6보다 나쁘다 — 6은 "업데이트가 안 됨"이라 `plugin update` 출력으로 눈치챌 여지가 있지만, 7은 업데이트가 **성공했다고 보고된 뒤** 런타임만 옛것인 상태다.

**수정: 형제 버전만 재지정한다.**

단순히 `ln -sfn`으로 바꾸면 안 된다 — `install.sh`도 같은 symlink를 만들고 **사용자 클론**을 가리키게 한다(`install.sh:110`, 하네스 소유 파일이라 비파괴 정책의 예외). 무조건 재지정하면 마켓플레이스 세션이 그 설정을 덮어쓴다. 그래서 `ROOT`가 `*/plugins/cache/*` 안일 때만 형제 판정을 켜고, symlink 대상이 **같은 플러그인의 다른 버전 디렉토리**일 때만 갱신한다.

**비교는 물리 경로(`pwd -P`)로 한다.** `readlink`는 저장된 원문을 돌려주므로 심볼릭 부모를 포함할 수 있다(macOS `/var` → `/private/var`). 원문끼리 비교하면 형제 판정이 조용히 빗나간다 — 테스트 작성 중에 실제로 이 함정에 걸렸다.

분기 5가지를 회귀로 고정했다(`test-session-start` PASS 23 → 29): 형제 버전 재지정 · 사용자 클론 보존 · 깨진 링크 복구 · 실제 파일 보존 · 멱등.

**⚠️ 전환에는 수동 복구가 1회 필요하다.** 이 수정은 **다음 버전의 훅부터** 동작한다. 설치된 0.2.0 훅은 수정 전 코드이므로 0.2.1로 업데이트해도 스스로 재지정하지 못한다. 0.2.1 설치 후 **한 번만** symlink 3개를 지우고 새 훅을 실행하면, 그 이후의 모든 버전 업데이트는 자동으로 따라온다.

```bash
rm -f ~/.llm-wiki/scripts/{resolve-vault,validate-frontmatter,build-link-graph}.sh
bash ~/.claude/plugins/cache/llm-wiki-harness/llm-wiki-harness/<새버전>/hooks/session-start claude </dev/null
```
