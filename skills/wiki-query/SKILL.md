---
name: wiki-query
description: wiki에 저장된 지식을 질문·조회할 때 사용 — "wiki에서 찾아줘", "~에 대해 뭐 있지?", "/wiki-query".
---

# wiki-query

## 개요
저렴한 단계부터 비싼 단계까지 순서대로 밟아 wiki에서 질문에 답한다. 답할 수 있는 즉시 멈춰 토큰을 최소화한다. 먼저 Config Gate.

## read-only 경계
wiki-query는 페이지 / `index.md` / `hot.md` / QMD 무엇도 쓰지 않는다. 유일한 예외는 Step 6의 `log.md` QUERY 추가(관찰 기록) — 정의·근거는 "read-only 스킬의 경계"를 참조한다. log append가 실패해도 답변은 이미 전달됐으므로 스킬 실패가 아니다.

QMD는 후보 수집(discovery)에만 쓴다. 최종 인용·답변 근거는 **항상 파일 본문에서 검증**한다 — QMD가 캐시한 텍스트로 답하지 않는다. 파일이 없거나 본문에 해당 내용이 없는 QMD 히트는 버리고 "QMD 인덱스가 stale할 수 있음 — /wiki-setup --update-qmd"라고 기록한다(self-healing).

## 검색 사다리
**Step 0 — Config Gate + QMD 게이트.** Config Gate 통과 후 QMD 게이트 판정 → 이후 Step 2b 활용 여부가 정해진다.

**Step 0.5 — `wiki/hot.md` 읽기(있으면).** 질문이 최근 활동에 대한 것이면 hot.md만으로 바로 답할 수 있는지 확인한다 → 충분하면 Step 5로 점프.

**Step 1 — 쿼리 분류.**
- 타입: Factual("X란?") / Relationship("X와 Y 관계?" → `relationships:` frontmatter 필수 탐색) / Synthesis("X 전반 정리?") / Gap("X에 대해 뭘 모르나?" → "Open Questions" 섹션).
- 모드: "quick"/"just scan"/"fast lookup" 키워드 → **Index-only**(Step 2에서 중단); 그 외 → **Normal**(전체 파이프라인).

**Step 2 — Index Pass (저렴).** `wiki/index.md` 읽기 + frontmatter-only grep `^(title|tags|summary|tier):` → 후보 5~10개 수집. 랭킹: title 정확 매치 > tags 매치 > summary 필드 포함 > index.md 항목 포함; 동점 시 tier `core` > `supporting` > `peripheral`(tier 없으면 supporting).
- **Index-only 모드는 여기서 중단.** `summary:` 필드 + index.md 설명만으로 답변을 구성하고 라벨 `(index-only — 페이지 본문 미읽음, 세부 내용 누락 가능)`을 붙인다 → Step 6으로 점프.

**Step 2b — QMD Semantic Pass** (QMD 게이트 통과 시만; 미설정이면 스킵하고 Step 3으로). 시맨틱 검색으로 키워드가 놓친 후보를 보완한다(후보 수집 전용). 결과 충분 → Step 4로 점프(QMD 상위 파일만 전체 읽기). 결과 불충분 → Step 3.
- ⚠️ **stale 인덱스 가드:** QMD가 가리킨 경로가 실재하지 않거나(삭제·이동) 본문에 해당 내용이 없으면 → 그 후보를 폐기하고 "QMD 인덱스가 stale할 수 있음, /wiki-setup --update-qmd 권장" 1줄을 답변에 덧붙인다(self-healing).

**Step 3 — Section Pass (중간 비용, Step 2/2b 불충분 시).** 각 후보 파일에 `Grep -A 10 -B 2 "<query-term>" <candidate-file>` 실행 → 15~30줄 확보(전체 읽기 100~500줄 대비 저렴). 충분하면 Step 5로 점프.

**Step 4 — Full Read (비쌈, 최후 수단).** 상위 3개 후보 전체 읽기, tier 우선순위 적용(core → supporting; peripheral은 유일한 매치일 때만). `[[link]]` 1-hop 허용.
- Relationship 쿼리 → `relationships:` frontmatter 블록 탐색, 타입·방향 명시(예: "A contradicts B (typed edge)").
- Gap 쿼리 → "Open Questions" 섹션 확인.
- 여전히 부족 → 볼트 전체 content grep 실행 + 사용자에게 에스컬레이션 중임을 알린다.

**Step 5 — 답변 합성.** 아래 "## 답변 포맷"을 따른다.

**Step 6 — `wiki/log.md` 쿼리 기록** (read-only 예외 — 관찰 기록):
```
[YYYY-MM-DD] QUERY query="{질문 요약}" result_pages=N mode=normal|index_only escalated=true|false
```
log append 실패해도 답변은 이미 전달됨 → 스킬 실패 아님(self-healing).

**Step 7 — 저장 제안.** 답변이 가치 있는 새 지식이면 `knowledge/` 저장을 **제안만** 한다(자동 생성 금지). 관련 `knowledge/` 페이지가 있으면 해당 페이지 추가를 제안하고, 없으면 새 `knowledge/` 페이지 또는 `/wiki-capture` 호출을 제안한다.

## 답변 포맷
```
> 위키 기반:
> [답변 + [[slug]] 인용]
> 참고 페이지: [[slug-a]], [[slug-b]]
> 공백: [wiki가 커버하지 못하는 부분]
```

- 인용은 `[[slug]]` 기본(Obsidian 1차 소비 환경 — 클릭 가능, 페이지 이동 시 자동 추적). Section grep·Full read를 실제 수행한 경우(Step 3·4)에 한해 검증 편의로 `file_path:line` 힌트를 인용 옆에 보조 표기할 수 있다 — 기본은 항상 `[[slug]]`.
- 인용마다 검색 단계 투명성 라벨을 붙인다: `found in summary` | `section grep` | `full page read`.
- 스테일 체크: (오늘 − `updated`) > 90일 → `[[slug]] (stale: last updated YYYY-MM-DD)`.
- 미확정 상태 표시(wiki-project 스킬군 연동): `status: proposed`(changes/ 제안) → `[[slug]] (proposed — 미확정 설계)`; `[NEEDS CLARIFICATION]` 마커 잔존 또는 `status: unverified` → `[[slug]] (미확정: 가정 포함)`. 미확정 내용을 사실처럼 회수하지 않는다.
- wiki에 없으면 "wiki에 해당 내용이 없습니다"라고 명시한다(임의 생성 금지). 절대 자신의 지식으로 답을 지어내 wiki 콘텐츠인 양 제시하지 않는다.
