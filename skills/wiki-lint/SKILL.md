---
name: wiki-lint
description: 볼트의 구조적 문제를 감사할 때 사용한다 — 깨진 링크, 고아 페이지, frontmatter 누락, 미처리 소스, 오래된 내용, PII 값 노출, provenance drift, relationship 오류, change proposal 무결성. severity별로 보고하고 가역적인 것만 --fix로 수리한다. 트리거는 "wiki 상태 점검"·"lint 실행"·"wiki 감사"·"wiki health check".
---

# wiki-lint

볼트에서 **무엇이 잘못됐나**를 찾는다. ("무엇이 남았나"는 `wiki-status`.)

시작 전 `using-llm-wiki` 스킬을 로드한다 — Config Gate, 종료 시퀀스, QMD refresh, 페이지 포맷(`references/page-format.md` — 문서 클래스·provenance 산정·충돌 노트 불변식).

## 워크플로

```
Step 0: Config Gate (bash ~/.llm-wiki/scripts/resolve-vault.sh — 실패 시 안내 후 중단)
        --fix 지정 시 QMD 게이트도 함께 판정 (Step 6에서 필요)

Step 1: 링크 그래프 1회 패스
        bash ~/.llm-wiki/scripts/build-link-graph.sh <wiki_dir>
        → 항목 1·2·9·12(target 부재·자기참조)를 이 출력에서 얻는다

Step 2: frontmatter 검증
        각 페이지에 bash ~/.llm-wiki/scripts/validate-frontmatter.sh <file>
        → 항목 3·4. 클래스 판정은 스크립트가 한다(훅과 동일 출처)

Step 3: manifest·raw 대조 — 항목 5·10·15·17
        .manifest.json content_hash 기준. mtime은 쓰지 않는다
        (스키마·소비 패턴: using-llm-wiki/references/manifest.md)

Step 4: 본문·frontmatter 스캔 — 항목 6·7·8·11·13·14·16

Step 5: 리포트 출력 (아래 형식) — severity 그룹 + 항목마다 다음 액션 1줄

Step 6: --fix 지정 시에만 수리 (차등 확인, 아래 규칙)

Step 7: 종료 시퀀스 (아래 "종료")
```

## 스캔 원칙

- **결정론적 검증은 스크립트에 맡긴다.** 링크 그래프(항목 1·2·9·12)는 `bash ~/.llm-wiki/scripts/build-link-graph.sh <wiki_dir>` 1회 패스로 얻는다 — 출력은 `ORPHAN <page>` / `BROKEN <src> <target>` / `REL_BROKEN <src> <target>` / `REL_SELF <src> <target>` / `SUMMARY nodes=N …`. 파일명별 볼트 전체 grep(O(N×M))은 금지한다.
- **frontmatter 기계 규칙**은 `bash ~/.llm-wiki/scripts/validate-frontmatter.sh <file>`가 문서 클래스(①②③)를 판정해 검증한다 — 훅과 같은 스크립트를 재사용하므로 규칙이 갈라지지 않는다.
- 나머지는 frontmatter-scoped grep(`^---` 범위) 우선, 섹션 anchored read 활용. 불필요한 전체 페이지 읽기를 지양한다.
- **특수 파일 제외:** `wiki/index.md`·`log.md`·`hot.md`는 스캔·항목 계수에서 제외한다 (쓰기 스킬이 자동 갱신하는 파생물이다).

## 점검 항목 17가지

각 항목의 `[키]`는 log 필드명과 1:1 매칭된다. severity: 🔴 ERROR(즉시 수정) / 🟡 REVIEW(검토 필요) / ℹ️ SOFT(소프트 경고).

| # | 키 | 항목 | sev | 체크 |
|---|---|---|---|---|
| 1 | `orphans` | 고아 페이지 | 🟡 | 링크 그래프 인바운드 0 |
| 2 | `broken_links` | 깨진 `[[wiki-link]]` | 🟡 | 링크 그래프 — 대상 .md 부재 |
| 3 | `format_errors` | page format 위반 | 🔴 | validator(클래스별 필수 키·enum·형식). 추가: `base_confidence`가 [0.0, 1.0] 밖 |
| 4 | `missing_summary` | `summary:` 없음·400자 초과 | ℹ️ | 없으면 cheap retrieval 불가, 초과면 범위가 넓다는 신호 |
| 5 | `unprocessed` | 미처리 raw 소스 | 🟡 | raw/ 스캔 vs `.manifest.json` |
| 6 | `index_missing` | `index.md` 미등록 페이지 | 🟡 | wiki/ 페이지 vs index.md |
| 7 | `unverified` | 인라인 `⚠️ unverified` 포함 | ℹ️ | 목록만 |
| 8 | `conflicts` | `status: conflict` 페이지 | 🟡 | 충돌 노트 open 항목 ≥1 (불변식) |
| 9 | `concept_gaps` | 개념 갭 | 🟡 | 항목 2와 같은 데이터, 목적이 다름 — "만들어야 할 페이지" 식별 |
| 10 | `source_drift` | 소스 변경 미반영 | 🟡 | manifest `content_hash` ≠ 현재 소스 해시인데 대응 페이지가 그대로. **`status: verified` + drift는 우선순위 상향** |
| 11 | `pii_exposure` | PII 값 노출 | ℹ️ | 아래 정밀도 규칙 |
| 12 | `relationship_issues` | typed relationship 유효성 | 🔴 | 타입이 5종 밖 / 깨진 target / 자기 참조. 블록 없는 페이지는 스킵 |
| 13 | `provenance_drift` | provenance drift | ℹ️ | 아래 재계산 규칙 |
| 14 | `supersession_issues` | supersession 무결성 | 🟡 | 대상 부재 / 대상이 archived(체인) / `superseded_by`는 있는데 `status`가 archived 아님 |
| 15 | `raw_deletable` | 삭제 대기 raw | ℹ️ | 아래 3조건 |
| 16 | `change_proposal_issues` | change proposal 무결성 | 🟡 | 아래 4종 |
| 17 | `manifest_integrity` | manifest↔페이지 정합성 | 🟡 | `pages_created` 경로가 디스크에 부재 (항목 5의 역방향) |

**항목 9 — 총계 이중 계상 금지.** 항목 9는 항목 2와 **같은 데이터의 재분류 뷰**다("만들어야 할 페이지" 식별). 각 항목의 `(N건)`은 각자 표시하되 `총 이슈`(T)는 **중복 제거된 고유 이슈 수**이므로 항목 9를 T에 두 번 더하지 않는다.

**항목 10 — 이름이 `stale`이 아닌 이유.** `wiki-query`의 stale(= 오늘 − `updated` > 90일, §4-5 `PAGE_STALE_DAYS`)과 **서로 다른 술어**다. 한 단어를 두 개념이 공유해 "query에선 stale인데 lint는 깨끗"한 혼선이 있었다 — 페이지 나이는 `stale`, 소스 대비 구식은 `source_drift`로 분리한다. 판정은 manifest `content_hash` 비교이며 **파일 mtime은 쓰지 않는다**(git checkout·복사·동기화로 깨진다 — 항목 15와 동일 근거).

**항목 11 — PII는 "키워드 + 실제 값 할당" 패턴만 잡는다.** `api_key: "sk-..."`, `password: <비어있지 않은 값>`, `token:`/`secret:`/`email:`/`phone:` + 실제 값. 설명 텍스트("API token을 발급받아")는 값이 없으므로 미스이고, placeholder(대문자+밑줄 `YOUR_API_KEY`, `xxx`, `<...>`)는 제외한다. 줄 끝 `<!-- lint-ignore: pii -->` 억제 마커 1개를 지원한다(allowlist 파일은 두지 않는다).

**항목 13 — provenance 재계산.** `provenance:` 블록이 없어도 본문 `^[inferred]`/`^[ambiguous]` 마커를 스캔한다(블록 생략으로 검사를 회피하지 못하게). 산정 단위는 `page-format.md`가 단일 출처다. 경고 조건:
- 저장값과 재계산값 차이 ≥ 0.20 (필드별) → frontmatter를 재계산값으로 교정 권고 (**마커가 진실**)
- `inferred > 0.40`이면서 `sources:` 없음 → "unsourced synthesis"
- `ambiguous > 0.15` → "speculation-heavy" (재소싱 또는 knowledge/ 이동 권고)
- 블록도 마커도 전혀 없는데 `sources: conversation`·추론성 페이지 → "provenance 미표기"

**항목 15 — raw 삭제 대기는 3조건을 모두 충족해야 한다.** `.manifest.json`에 `content_hash` 있음(ingest 완료) + 대응 `summaries/` 페이지 존재 + manifest의 `ingested_at` 기준 14일 초과. (mtime은 git checkout·복사·동기화로 깨지므로 쓰지 않는다.) 미ingest raw는 삭제 대상이 아니다.

**항목 16 — change proposal 무결성.** `changes/` 없는 프로젝트는 스킵. ① `status: applied`인데 해당 프로젝트 `decisions.md`에 `[[change]]` 링크 없음(스냅샷-기록 짝 위반) ② `proposed` + `created` 14일 경과(방치) ③ `targets:`의 파일이 프로젝트 폴더에 없음 ④ `changes/` 루트에 applied|rejected 파일 잔류(archive/ 미이동).

## 출력 형식

severity 그룹(🔴 → 🟡 → ℹ️)으로 묶고, 각 섹션에 **다음 액션 1줄**을 붙인다. 특히 `--fix`가 불가능한 항목은 사용자가 바로 해결을 시작할 수 있어야 한다.

리포트 본문은 `##` 제목 아래 severity 그룹 `###`, 항목 `####` 순으로 내려간다 (제목 레벨이 역행하지 않게).

```markdown
## Wiki Lint Report — YYYY-MM-DD

### ════ 🔴 ERROR (즉시 수정) ════

#### 필수 frontmatter 누락 (N건)
- `wiki/summaries/articles/topic/baz.md` — 누락: tags, sources
- `wiki/concepts/qux.md` — base_confidence 1.4 범위 초과 [0.0, 1.0]
  → 액션: 값 판단 필요(자동 수정 불가). 올바른 신뢰도로 직접 교정

### ════ 🟡 REVIEW (검토 필요) ════

#### 고아 페이지 (N건)
- `wiki/concepts/foo.md` — 인바운드 링크 없음
  → 액션: 관련 페이지에서 링크 추가 또는 archive (자동 수정 불가, 판단 필요)

#### 소스 변경 미반영 (N건)
- `wiki/summaries/papers/paper-x.md` — manifest content_hash 불일치, 페이지 미갱신
- `wiki/concepts/important.md` — source_drift + status=verified ⚠️ 높은 우선순위

### ════ ℹ️ SOFT (소프트 경고) ════

#### Provenance drift (N건)
- `wiki/concepts/theory.md` — drift: stored inferred=0.10, recomputed=0.38 (Δ=0.28)

총 이슈: T개 | 🔴 즉시 수정: E개 | 🟡 검토 필요: R개 | ℹ️ 소프트 경고: S개
자동 수정 가능: F개 (--fix 옵션)
```

집계 문자는 서로 겹치지 않게 쓴다 — `T`(총 이슈, 중복 제거) · `E`/`R`/`S`(severity별) · `F`(자동 수정 가능). 아래 LINT 라인의 항목 문자(`A`~`Q`)와도 구분된다.

액션 문구 예: conflict → "소스 채택 결정 후 충돌 노트 resolved 갱신" · PII → "값 확인 후 redaction/.gitignore" · 미처리 raw → "`wiki-ingest <경로>`" · 고아 → "링크 추가 또는 archive" · manifest 정합성 → "의도된 삭제면 manifest prune, 복구면 `wiki-ingest --full <raw경로>`".

## `--fix` — 기본 dry-run, 적용은 차등 확인

- **`--fix` 단독 = dry-run.** 무엇을 바꿀지 보여주기만 한다 (안전한 기본값).
- **가역·저위험** (format 필드 추가, `index.md` 등록, relationship type 오타 → `related_to` 폴백): 일괄 확인 1회. `--fix --yes`로 자동 적용.
- **비가역 (항목 15 raw 삭제): 항상 개별 확인 — `--yes`로도 건너뛰지 않는다.** 삭제 전 대응 `summaries/` 페이지 존재를 재확인한다.
- **항목 12는 서브케이스별로 갈린다.** `type` 오타 → `related_to` 폴백은 가역이라 **자동 수정 대상**이고, 깨진 target·자기 참조는 어느 페이지를 가리키려 했는지 판단이 필요해 **자동 수정 불가**다.
- **자동 수정 불가:** 판단 필요(항목 1·2·9·17 + 항목 12의 깨진 target·자기 참조) / ingest 필요(항목 5) / 값 판단(항목 3의 base_confidence 범위).
- **frontmatter 수정은 append-only.** 누락 필드를 frontmatter 끝에 추가만 한다. 기존 필드 순서·주석·정렬을 보존하고 YAML을 통째로 재serialize하지 않는다(문서 churn 방지). 값 변경은 자동 수정 대상이 아니다.

## 종료

`--fix`로 실제 쓰기가 발생하면 **쓰기 스킬의 종료 시퀀스를 그대로 따른다** — 원본 먼저, 파생물 나중:

```
페이지 → index.md → log.md → hot.md → QMD refresh
```

`--fix`는 페이지 frontmatter와 `index.md`를 쓰는 명백한 쓰기 스킬이므로 `hot.md`도 갱신한다
(12개 쓰기 스킬 중 유일하게 빠져 있었다). report-only 실행은 read-only이므로
`log.md` 기록만 하고 `hot.md`·QMD는 건드리지 않는다.

```
log.md 기록 (한 줄, 17개 필드 전부. issues_found는 중복 제거된 총계 T):
[YYYY-MM-DD] LINT issues_found=T orphans=A broken_links=B format_errors=C missing_summary=D
unprocessed=E index_missing=F unverified=G conflicts=H concept_gaps=I source_drift=J pii_exposure=K
relationship_issues=L provenance_drift=M supersession_issues=N raw_deletable=O
change_proposal_issues=P manifest_integrity=Q

QMD refresh: --fix로 실제 파일 쓰기가 발생한 경우만.
report-only 실행은 read-only이므로 refresh하지 않는다.
```

## 품질 체크

```
□ 링크 그래프·frontmatter 검증을 스크립트로 수행 (수동 O(N×M) grep 없음)
□ index.md · log.md · hot.md 를 스캔에서 제외
□ 17개 항목 전부 계수 (0건도 log 필드에 0으로 기록)
□ severity 그룹 출력 + 수정 불가 항목마다 다음 액션 1줄
□ 총 이슈(T)에 항목 9를 항목 2와 이중 계상하지 않음
□ --fix 없이는 파일을 쓰지 않음 / --fix 단독은 dry-run
□ 비가역 삭제는 --yes에서도 개별 확인
□ --fix로 쓰기가 발생하면 종료 시퀀스 완주 (페이지 → index → log → hot → QMD)
□ 쓰기가 발생했으면 QMD refresh + 상태 문자열, 아니면 생략
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 파일명마다 볼트 전체를 grep해 링크를 검사한다 | O(N×M)이라 볼트가 커지면 사실상 완주하지 못한다 | `build-link-graph.sh` 1회 패스 |
| frontmatter 규칙을 직접 판정한다 | 훅의 판정과 갈라져 "훅은 통과했는데 lint는 에러"가 생긴다 | `validate-frontmatter.sh` 재사용 |
| `--fix` 없이 발견한 문제를 고친다 | 감사가 조용히 볼트를 바꾼다 | report-only. `--fix` 단독도 dry-run |
| `--yes`니까 raw 삭제까지 일괄 승인한다 | 비가역 삭제가 확인 없이 실행된다 | raw 삭제는 항상 개별 확인 |
| 누락 필드를 채우려 frontmatter를 다시 serialize한다 | 필드 순서·주석이 날아가 diff가 문서 전체로 번진다 | 끝에 append만 |
| 범위를 벗어난 `base_confidence`·provenance를 자동 교정한다 | 판단이 필요한 값을 LLM이 결정한다 | 권고만. 교정은 사용자의 몫 |
| `index.md`·`log.md`·`hot.md`도 검사한다 | 파생물이 orphan·format 오류로 잡혀 리포트가 노이즈가 된다 | 스캔·계수에서 제외 |
| 0건 항목을 log에서 뺀다 | LINT 라인 파싱과 추세 비교가 깨진다 | 17개 필드를 항상 기록 (0건도 `=0`) |
| 수정 불가 항목을 사실만 나열한다 | 사용자가 다음에 무엇을 할지 알 수 없다 | 항목마다 다음 액션 1줄 |
