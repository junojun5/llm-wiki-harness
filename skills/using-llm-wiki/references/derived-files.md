# 파생물 — index.md · log.md · hot.md

셋 다 페이지에서 재구성 가능한 **파생물**이다. 쓰기 종료 시퀀스에서 원본(페이지) 다음에 이 순서로 갱신한다. 셋 다 문서 클래스 ③(원장)이라 frontmatter 검증 대상이 아니고, `wiki-lint` 스캔에서도 제외된다.

## index.md — 전체 목차

마크다운 표로 카테고리별 섹션을 유지한다. 링크는 표시명 + 상대경로다.

```markdown
## concepts
| 페이지 | 설명 |
|---|---|
| [어텐션 메커니즘](concepts/attention-mechanism.md) | 시퀀스 요소 간 가중 참조로 문맥을 만드는 방식 |

## summaries/web
| 페이지 | 설명 |
|---|---|
| [Karpathy — LLM Wiki](summaries/web/AI-ML/karpathy-com-llm-wiki.md) | LLM이 유지하는 지식 베이스 패턴 |
```

- 새 페이지는 해당 카테고리 섹션에 추가한다. 섹션이 없으면 만든다.
- **중복 항목을 만들지 않는다** — 재실행 시 이미 등록된 페이지는 스킵한다(idempotent).
- 페이지를 `archived/`로 옮기면 항목도 함께 옮긴다.

## log.md — append-only 작업 기록

한 줄 = 한 작업. `[YYYY-MM-DD] ACTION key=value…` 형식을 지킨다 — 훅과 `wiki-lint`·`wiki-status`가 기계적으로 파싱한다. 날짜 토큰은 **항상 `[YYYY-MM-DD]`**이고, 한 동작 = 한 줄이라 줄바꿈을 넣지 않는다.

**ACTION 어휘 12종 (단일 출처).** 이 목록에 없는 ACTION은 쓰지 않는다.

| ACTION | 발행 스킬 | 필드 |
|---|---|---|
| `INIT` | wiki-setup | `vault="{경로}"` |
| `QMD-RECONCILE` | wiki-setup `--update-qmd` | `pages_indexed=N embedded=true\|false` |
| `INGEST` | wiki-ingest | `source="{raw 경로}" pages_created=N pages_updated=M mode=append\|full` |
| `INGEST-URL` | ingest-url | `url="{url}" page="{경로}"` |
| `CAPTURE` | wiki-capture | `type=session page="{경로}" title="{제목}"` |
| `KNOWLEDGE` | wiki-knowledge | `mode=create\|update page="{경로}" sources_used=N [changes="merge\|conflict\|restructure"]` |
| `QUERY` | wiki-query | `query="{질문 요약}" result_pages=N mode=normal\|index_only escalated=true\|false` |
| `LINT` | wiki-lint | `issues_found=T` + 17개 점검 키 |
| `STATUS` | wiki-status | `unprocessed=N recent_ingest="{경로}" token_estimate=K` |
| `PROJECT-INIT` | wiki-project-init | `name="{name}" files=[...] markers=N` |
| `PROJECT-DESIGN` | wiki-project-design | `name="{name}" change="{slug}\|surface" files=[...]` |
| `PROJECT-RECORD` | wiki-project-record | `name="{name}" type=decision\|troubleshooting\|meeting\|backlog target="{경로}"` |

```
[2026-05-27] INGEST source="raw/articles/AI-ML/karpathy-llm-wiki.md" pages_created=3 pages_updated=1 mode=append
[2026-05-27] INGEST-URL url="https://example.com/x" page="summaries/web/AI-ML/example-com-x.md"
[2026-05-26] CAPTURE type=session page="summaries/sessions/2026-05-26-llm-wiki-설계.md" title="LLM Wiki 설계"
[2026-05-26] KNOWLEDGE mode=update page="knowledge/attention.md" sources_used=4 changes="merge|conflict"
[2026-05-26] QUERY query="attention이 뭐야" result_pages=2 mode=normal escalated=false
[2026-05-25] LINT issues_found=7 orphans=2 broken_links=1 …
[2026-05-25] STATUS unprocessed=3 recent_ingest="raw/papers/attention.pdf" token_estimate=48000
[2026-05-25] PROJECT-INIT name="wiki-harness" files=[overview.md,context.md] markers=2
```

기존 줄을 수정하지 않는다. 재실행으로 같은 작업이 두 줄 남는 것은 거짓이 아닌 정직한 재실행 기록이다.

> 다른 스킬이 `wiki-query`를 **서브루틴으로 호출할 때는 `QUERY` 라인을 남기지 않는다.** 호출한 스킬의 ACTION 한 줄이 그 세션을 대표한다 — 중첩 호출마다 로그를 남기면 원장이 노이즈로 덮인다.

## hot.md — 최근 활동 ~500단어 시맨틱 스냅샷

쓰기 스킬은 종료 시퀀스 4단계에서 갱신하고, 읽기 스킬은 Step 0.5에서 선읽기한다. **없으면 아래 템플릿으로 생성한다** (이 템플릿이 단일 출처다).

```markdown
---
title: Hot Cache
updated: YYYY-MM-DD
---
# Hot Cache
*A ~500-word semantic snapshot of recent activity.*
## Recent Activity
- [YYYY-MM-DD] INIT — vault created
## Active Threads
*None yet.*
## Key Takeaways
*None yet.*
## Flagged Contradictions
*None yet.*
```

빈 템플릿이 올바른 초기 상태다 — hot.md는 파생물이고 새 볼트의 활동은 0이다. 예외: 기존 `log.md`는 있는데 hot.md만 없는 볼트(마이그레이션·`--repair`)에서는 log.md에서 재구성한다.

**재구성 시 10과 3은 다른 수다.** `log.md` 최근 **10개**를 *읽고*(맥락 파악 범위), 그중 Recent Activity에 *남기는* 것은 **3개**다(보관 개수). 10개를 그대로 적지 않는다.

**갱신 규칙:**

- **Recent Activity** — 방금 한 작업 한 줄 요약. **최근 3개만 유지**한다(재구성 시 읽는 10개와 구분).
- **Key Takeaways** — 주목할 인사이트·결정이 나왔을 때만 갱신.
- **Active Threads** — 진행 중인 주제와 연결되거나 그 주제가 구체화됐을 때만 갱신.
- **Flagged Contradictions** — 충돌(`status: conflict`)이 새로 생겼을 때 한 줄 추가.
- `updated:` 타임스탬프를 항상 갱신한다.
