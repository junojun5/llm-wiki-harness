# LLM Wiki Harness — Agent Rules

이 볼트는 스킬·스크립트·훅으로 유지되는 개인 마크다운 지식 베이스(LLM Wiki)다. Claude는 `using-llm-wiki` 스킬로, Codex·Cursor·Antigravity는 이 `AGENTS.md`로 동일 규칙을 로드한다. (단일 출처 = 루트 `AGENTS.md`; 상세 절차는 각 `SKILL.md`·스펙으로 위임.)

## Step 0 — Config Gate (모든 wiki 작업 전, 매번)

```
bash ~/.llm-wiki/scripts/resolve-vault.sh
```
- exit 0 → stdout `VAULT_PATH` / `WIKI_DIR` / `RAW_DIR` 사용.
- exit ≠ 0 → stderr 복구 안내를 그대로 사용자에게 전달하고 **중단**. 경로를 추측하지 않는다.
- 스크립트 자체가 없음 → "harness install.sh를 재실행하세요" 후 중단.

## 불변 규칙

- **raw/ 는 불변.** `raw/` 아래를 생성·수정·삭제하지 않는다 — **사용자가 명시적으로 요청해도.** 소스를 고치려면 볼트 밖에서 고쳐 재-ingest한다. (훅이 raw/ 쓰기를 기계적으로 차단한다.)
- **쓰기 종료 시퀀스** (모든 wiki 쓰기 후, 순서대로): 페이지 → `index.md` → `log.md` → `hot.md` → QMD refresh. 원본 먼저, 파생물 나중.
- **모든 사실 기반 주장에 출처**: `(출처: [[page]])` 또는 `⚠️ unverified` 표시. 충돌 → `## Conflicts` 블록 + `status: conflict`. 폐기(삭제 금지) → `wiki/archived/`로 이동.
- 페이지는 한국어. 파일명은 소문자-하이픈. 내부 링크는 [[slug]] (파일명만, 폴더 경로 없음). index.md는 마크다운-표 `| [표시명](상대경로.md) | 설명 |`. 분류 불확실하면 묻는다.

## QMD refresh (§3-5) — 쓰기 스킬 종료 단계

QMD는 볼트 위의 **선택적** 검색 인덱스(markdown이 source of truth). read-only 스킬(`wiki-query`·`wiki-status`)은 refresh하지 않는다. 설정 파일 없음 — qmd 레지스트리가 단일 출처.

- **게이트** (refresh·검색 전): ① `command -v ${QMD_CLI:-qmd}` 실패 → Grep fallback, `QMD skipped: qmd CLI unavailable`. ② `${QMD_CLI:-qmd} collection list`에 `$VAULT_PATH/$WIKI_DIR` 매칭 컬렉션 없음 → Grep fallback + "/wiki-setup --update-qmd로 등록하세요", `QMD skipped: collection not registered`. ③ 둘 다 통과 → 매칭 컬렉션명을 `QMD_WIKI_COLLECTION`으로 사용.
- **시퀀스** (page→index→log→hot 이후 마지막, **스킬 실행당 1회** — update가 전체 해시 스캔): `${QMD_CLI:-qmd} update` (텍스트/BM25, 매번) → `${QMD_CLI:-qmd} embed` (벡터, update가 새 해시에 벡터 필요 보고 시만) → `${QMD_CLI:-qmd} get "qmd://$QMD_WIKI_COLLECTION/<category>/<page>.md" -l 5` 검증. 실패해도 **볼트는 롤백하지 않는다** — QMD 상태만 별도 보고. 쓴 게 없으면(해시 일치 ingest, report-only lint) 생략.
- **상태 문자열(하나):** `QMD refreshed: update + embed + verified` · `QMD refreshed: update only + verified` · `QMD partial: update 성공 · verify 실패 (인덱스 미반영 가능 — 단발 무시, 반복 시 --update-qmd)` · `QMD skipped: collection not registered` · `QMD skipped: qmd CLI unavailable` · `QMD failed: <짧은 에러 요약>`
- **self-healing:** 단발 실패는 액션 불필요(다음 스킬의 전체 스캔 update가 흡수, 그동안 Grep fallback). 2회 연속 실패·stale 체감 → `/wiki-setup --update-qmd`.

## 스킬 라우팅 — 해당 스킬을 호출

| 의도 | 스킬 |
|---|---|
| 볼트 초기화/복구 | `wiki-setup` |
| raw/ 소스 ingest | `wiki-ingest` |
| URL ingest | `ingest-url` |
| 현재 대화 캡처 | `wiki-capture` |
| wiki 기반 질문 답변 | `wiki-query` |
| 볼트 감사/수정 | `wiki-lint` |
| 볼트 상태/남은 일 | `wiki-status` |
| knowledge 페이지 종합 | `wiki-knowledge` |
| 프로젝트 시작(overview/context/goals) | `wiki-project-init` |
| 프로젝트 설계 변경(architecture/domain/conventions) | `wiki-project-design` |
| 결정/이슈/미팅/백로그 기록 | `wiki-project-record` |


> Codex 참고: `AGENTS.md`는 instruction chain으로 병합되며 기본 `project_doc_max_bytes`=32 KiB다. 이 파일은 축약판만 둔다 — 한도 초과 시 `project_doc_max_bytes`를 높이거나 상세를 SKILL.md로 위임한다 (README 트러블슈팅 참조).
