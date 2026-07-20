---
name: using-llm-wiki
description: LLM Wiki 볼트에서 작업할 때 사용 — 세션 시작 시 규칙·라우팅 로드
---

# LLM Wiki 사용하기

부트스트랩: Claude/Codex/Cursor는 세션 시작 시 이 스킬을, Antigravity는 `AGENTS.md`를 로드한다 — 동일 내용이므로 항상 동기화(정본: `AGENTS.md`).

## Step 0 — Config Gate (필수, 매 작업마다)

```
bash ~/.llm-wiki/scripts/resolve-vault.sh
```
- exit 0 → stdout의 `VAULT_PATH` / `WIKI_DIR` / `RAW_DIR` 사용.
- exit ≠ 0 → stderr 복구 안내 그대로 전달 후 **중단**. 경로 추측 금지.
- 스크립트 없음 → "harness install.sh를 재실행하세요" 후 중단.

## 불변 규칙

- **raw/ 는 불변** — 생성·수정·삭제 금지(**사용자가 명시 요청해도**). 소스 수정은 볼트 밖에서 고쳐 재-ingest. (훅이 raw/ 쓰기를 차단.)
- **쓰기 종료 시퀀스**(순서대로): 페이지 → `index.md` → `log.md` → `hot.md` → QMD refresh. 원본 먼저, 파생물 나중.
- 사실 기반 주장엔 **출처**: `(출처: [[page]])` 또는 `⚠️ unverified`. 충돌 → `## Conflicts` + `status: conflict`. 폐기(삭제 금지) → `wiki/archived/`로 이동.
- 페이지는 한국어, 파일명은 소문자-하이픈(lowercase-kebab). 내부 링크 `[[slug]]`(파일명만, 폴더 경로 없음). `index.md` 엔트리는 `| [표시명](상대경로.md) | 설명 |` 표. 분류 불확실하면 사용자에게 묻는다.

## QMD refresh — 쓰기 스킬 전용

QMD는 볼트 위 **선택적** 검색 인덱스(markdown이 source of truth). read-only 스킬(`wiki-query`, `wiki-status`)은 refresh하지 않는다. Stateless — qmd 레지스트리가 단일 출처, 설정 파일 없음.

**게이트** (refresh·검색 전):
1. `command -v ${QMD_CLI:-qmd}` 실패 → Grep fallback, `QMD skipped: qmd CLI unavailable`.
2. `${QMD_CLI:-qmd} collection list`에 `$VAULT_PATH/$WIKI_DIR`와 매칭되는 컬렉션 없음 → Grep fallback + "/wiki-setup --update-qmd로 등록하세요", `QMD skipped: collection not registered`.
3. 둘 다 통과 → 매칭 컬렉션명을 `QMD_WIKI_COLLECTION`으로 사용(문자 그대로 "wiki"가 아니어도 무방).

**시퀀스** (쓰기 종료의 마지막 단계, page→index→log→hot 이후; **파일당이 아니라 스킬 실행당 1회** — `update`는 전체 해시 스캔):
```bash
${QMD_CLI:-qmd} update                  # text/BM25 index — cheap, always
${QMD_CLI:-qmd} embed                    # vector index — only when update reports new hashes need vectors
${QMD_CLI:-qmd} get "qmd://$QMD_WIKI_COLLECTION/<category>/<page>.md" -l 5   # verify (or: ls "$QMD_WIKI_COLLECTION" | grep <slug>)
```
실패 시 **볼트는 롤백하지 않는다** — QMD 상태만 별도 보고. 쓴 게 없으면(해시 일치 ingest, report-only lint) 생략.

**상태 문자열은 정확히 하나만 보고:**
`QMD refreshed: update + embed + verified` · `QMD refreshed: update only + verified` · `QMD partial: update 성공 · verify 실패 (인덱스 미반영 가능 — 단발 무시, 반복 시 --update-qmd)` · `QMD skipped: collection not registered` · `QMD skipped: qmd CLI unavailable` · `QMD failed: <짧은 에러 요약>`

**self-healing:** 단발 실패는 액션 불필요 — 다음 쓰기 스킬의 전체 스캔 `update`가 공백을 흡수, 그동안 검색은 Grep fallback. 2회 연속 실패 또는 stale 결과 → `/wiki-setup --update-qmd`(전체 재정합).

## 라우팅 표 — 의도별 스킬 호출

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

어느 것이 맞는지 불확실하면 묻는다 — 추측하지 않는다.
