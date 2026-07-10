---
name: using-llm-wiki
description: LLM Wiki 볼트에서 작업할 때 사용 — wiki에 읽거나 쓰기 전, 소스를 ingest할 때, 지식 베이스로부터 답할 때, 또는 볼트를 유지보수할 때.
---

# LLM Wiki 사용하기

스킬로 유지되는 개인 마크다운 지식 베이스. **Step 0는 모든 작업보다 먼저 실행된다.**

## Step 0 — Config Gate (필수, 매 작업마다)

```
bash ~/.llm-wiki/scripts/resolve-vault.sh
```
- exit 0 → stdout의 `VAULT_PATH` / `WIKI_DIR` / `RAW_DIR` 사용.
- exit ≠ 0 → stderr 복구 안내를 그대로 전달하고 **중단**. 경로를 절대 추측하지 않는다.
- 스크립트 없음 → "harness install.sh를 재실행하세요"라고 말하고 중단.

## 불변 규칙

- **raw/ 는 불변.** `raw/` 아래를 생성·수정·삭제하지 않는다 — **사용자가 명시적으로 요청해도.** 소스를 고치려면 볼트 밖에서 고쳐 재-ingest한다. (훅도 raw/ 쓰기를 차단한다.)
- **쓰기 종료 시퀀스**, 순서대로: 페이지 → `index.md` → `log.md` → `hot.md` → QMD refresh. 원본 먼저, 파생물 나중.
- 모든 사실 기반 주장에 **출처 표시**: `(출처: [[page]])` 또는 `⚠️ unverified` 표시. 충돌 → `## Conflicts` + `status: conflict`. 폐기(삭제 금지) → `wiki/archived/`로 이동.
- 페이지는 한국어; 파일명은 소문자-하이픈(lowercase-kebab); 링크는 `[[wiki-link]]`.

## QMD refresh (§3-5) — 쓰기 스킬 전용

QMD는 볼트 위의 **선택적** 검색 인덱스이며, markdown이 source of truth. read-only 스킬(`wiki-query`, `wiki-status`)은 절대 refresh하지 않는다. 상태 없음(stateless) — qmd 자체 레지스트리가 단일 출처이며 설정 파일은 없다.

**게이트** (refresh·검색 전):
1. `command -v ${QMD_CLI:-qmd}` 실패 → Grep fallback, `QMD skipped: qmd CLI unavailable` 보고.
2. `${QMD_CLI:-qmd} collection list`에 `$VAULT_PATH/$WIKI_DIR` 경로와 매칭되는 컬렉션 없음 → Grep fallback + "/wiki-setup --update-qmd로 등록하세요", `QMD skipped: collection not registered` 보고.
3. 둘 다 통과 → 매칭된 컬렉션명을 `QMD_WIKI_COLLECTION`으로 사용 (문자 그대로 "wiki"가 아니어도 동작).

**시퀀스** (쓰기 종료의 마지막 단계, page→index→log→hot 이후; **파일당이 아니라 스킬 실행당 1회** — `update`는 전체 해시 스캔):
```bash
${QMD_CLI:-qmd} update                  # text/BM25 index — cheap, always
${QMD_CLI:-qmd} embed                    # vector index — only when update reports new hashes need vectors
${QMD_CLI:-qmd} get "qmd://$QMD_WIKI_COLLECTION/<category>/<page>.md" -l 5   # verify (or: ls "$QMD_WIKI_COLLECTION" | grep <slug>)
```
실패 시 **볼트는 절대 롤백하지 않는다** — QMD 상태만 별도로 보고한다. 쓴 게 없으면(해시 일치 ingest, report-only lint) 전부 생략.

**상태 문자열은 정확히 하나만 보고:**
`QMD refreshed: update + embed + verified` · `QMD refreshed: update only + verified` · `QMD partial: update 성공 · verify 실패 (인덱스 미반영 가능 — 단발 무시, 반복 시 --update-qmd)` · `QMD skipped: collection not registered` · `QMD skipped: qmd CLI unavailable` · `QMD failed: <짧은 에러 요약>`

**self-healing:** 단발 실패는 액션이 불필요하다 — 다음 쓰기 스킬의 전체 스캔 `update`가 그 공백을 흡수하고, 그동안 검색은 Grep으로 fallback한다. 2회 연속 실패 또는 stale한 결과 → `/wiki-setup --update-qmd` (전체 재정합).

## 라우팅 — 매칭되는 스킬을 호출

`wiki-setup` 초기화/복구 · `wiki-ingest` raw 소스 · `ingest-url` URL · `wiki-capture` 현재 대화 · `wiki-query` 답변 · `wiki-lint` 감사/수정 · `wiki-status` 남은 일 · `wiki-knowledge` 종합 · `wiki-project-init` / `wiki-project-design` / `wiki-project-record` 프로젝트.

어느 것이 맞는지 불확실하면 묻는다 — 추측하지 않는다.
