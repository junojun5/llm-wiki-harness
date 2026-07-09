---
name: wiki-lint
description: 사용자가 wiki의 문제를 감사·린트·점검하려 할 때 사용 — 고아 페이지, 깨진 링크, 포맷 오류, 충돌, stale 페이지, PII, 정리 가능한 raw 파일 — 또는 "lint the wiki", "/wiki-lint", "wiki 점검/audit"라고 할 때.
---

# wiki-lint

볼트를 감사하고 (선택적으로) 기계적 이슈를 수정한다. 먼저 Config Gate. **Report-only 실행은 read-only** (`log.md`에 LINT 줄만 추가됨); 페이지를 쓰는 유일한 모드는 `--fix`다.

## 정본 스크립트를 사용 — 재발명 금지
결정론적 체크는 **단일 코드 출처**에서 나온다 (validator 훅이 쓰는 것과 동일한 스크립트이므로 결과가 절대 드리프트하지 않음). `rg`/grep 링크 스캔을 손수 짜지 마라:
- `~/.llm-wiki/scripts/build-link-graph.sh <WIKI_DIR>` → **O(N) 단일 패스**로 고아, 깨진 링크, 개념 갭, 관계 target/self 이슈 산출 (체크 1, 2, 9, 12). 파일별 grep(O(N×M)) 금지.
- `~/.llm-wiki/scripts/validate-frontmatter.sh <file>` → 페이지별 클래스 인식 frontmatter 체크 (체크 3). 페이지 전반에 실행; §3-3 문서 클래스 규칙을 적용한다 (원장 파일 면제, changes/troubleshooting enum).

## 17개 체크 (심각도별로 출력 그룹화 🔴 ERROR → 🟡 REVIEW → ℹ️ SOFT)
| # | key | check | sev | source |
|--|--|--|--|--|
|1|orphans|inbound 0 (excl. index/log/hot)|🟡|graph|
|2|broken_links|`[[link]]` target missing|🟡|graph|
|3|format_errors|missing required keys / base_confidence out of [0,1]|🔴|validate-fm|
|4|missing_summary|no `summary:` / >400 chars|ℹ️|grep|
|5|unprocessed|raw/ not in manifest|🟡|raw vs manifest|
|6|index_missing|page not in index.md|🟡|index|
|7|unverified|inline `⚠️ unverified`|ℹ️|grep|
|8|conflicts|`status: conflict` (open items ≥1)|🟡|frontmatter|
|9|concept_gaps|referenced-but-absent (same data as #2, "to create")|🟡|graph|
|10|stale|`updated` older than newest source; verified+stale = higher priority|🟡|frontmatter+manifest|
|11|pii_exposure|keyword+real value (api_key:/token:/password:…); skip placeholders + `<!-- lint-ignore: pii -->`|ℹ️|grep|
|12|relationship_issues|type not in enum / broken target / self-ref|🔴|graph+fm|
|13|provenance_drift|recompute from `^[inferred]`/`^[ambiguous]` markers; Δ≥0.20, ambiguous>0.15, inferred>0.40 unsourced, or block+markers both absent on conversation/inferred page|ℹ️|body markers|
|14|supersession_issues|`superseded_by` target missing / not archived|🟡|frontmatter|
|15|raw_deletable|all 3: content_hash in manifest + summaries page exists + ingested_at >14d|ℹ️|manifest|
|16|change_proposal_issues|applied w/o decisions link · proposed >14d · broken target · stray applied/rejected in changes/ root|🟡|projects/*/changes|
|17|manifest_integrity|manifest pages_created path missing on disk|🟡|manifest|

각 그룹에 **next-action 줄**을 붙이되, 특히 수정 불가능한 것들에 붙인다 (conflict→"소스 하나를 채택한 뒤 §3-3 resolved로 갱신", PII→"수정/.gitignore", unprocessed→"/wiki-ingest <path>", orphan→"링크 걸거나 archive").

## `--fix` 모델 — dry-run 기본, 차등 적용
- `--fix` 단독 = **dry-run**: 무엇이 바뀔지 보여주고, 아무것도 쓰지 않음.
- 되돌릴 수 있는/저위험 (누락 포맷 필드 추가, index.md 등록, 관계 타입 오타→`related_to`): 한 번의 배치 확인; `--fix --yes`는 자동 적용.
- **되돌릴 수 없음 (체크 15 raw 삭제): 항상 개별 확인 — `--yes`도 이걸 건너뛰지 않는다.** 삭제 전에 summaries/ 페이지가 존재하는지 재확인.
- 자동 수정 불가 (판단 필요): 1, 2, 9, 12 / ingest 필요: 5 / 가치 판단: 3의 base_confidence 범위.
- **Frontmatter 편집은 append-only**: 누락 필드는 끝에 추가; 기존 필드 순서/주석 보존. YAML을 절대 재직렬화하지 않는다 (churn 방지). 값 변경은 절대 자동 적용 안 됨.

## 마무리(Close-out)
- `log.md`: `[YYYY-MM-DD] LINT issues_found=N orphans=A broken_links=B format_errors=C missing_summary=D unprocessed=E index_missing=F unverified=G conflicts=H concept_gaps=I stale=J pii_exposure=K relationship_issues=L provenance_drift=M supersession_issues=N raw_deletable=O change_proposal_issues=P manifest_integrity=Q`
- QMD refresh는 **`--fix`가 실제로 쓴 경우에만** (report-only는 read-only, refresh 없음).
