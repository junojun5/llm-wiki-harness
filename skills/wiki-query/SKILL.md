---
name: wiki-query
description: wiki에 저장된 지식에 대해 질문하거나 어떤 주제의 정보를 찾아달라고 할 때 사용한다. hot 캐시 → frontmatter 인덱스 → QMD 시맨틱 → 섹션 grep → 전체 읽기 순으로 계층 검색해 토큰 비용을 최소화한다. 트리거는 wiki 기반 질문, "wiki에서 X 찾아줘", "X에 대해 알고 있어?".
---

# wiki-query

볼트에 있는 지식으로 질문에 답한다. 싼 경로에서 답이 나오면 거기서 멈추는 것이 이 스킬의 전부다.

시작 전 `using-llm-wiki` 스킬을 로드한다 — Config Gate, read-only 경계, QMD 게이트.

> **read-only 경계:** 페이지·`index.md`·`hot.md`·QMD를 건드리지 않는다. Step 6의 `log.md` append만 예외(관찰 기록)이고, 그 실패는 스킬 실패가 아니다. **QMD refresh는 하지 않는다.**
>
> **QMD source of truth 원칙:** QMD는 **후보 수집(discovery)에만** 쓴다. 최종 인용·답변 근거는 **항상 파일 본문에서 확인**한다 — QMD가 캐시한 텍스트로 답하지 않는다.

## 워크플로 — 계층적 검색

```
Step 0: Config Gate + QMD 게이트 판정 (Step 2b 활용 여부 결정)

Step 0.5: wiki/hot.md 읽기 (있으면)
  질문이 최근 ingest된 내용과 관련 있으면 hot.md만으로 답변 가능한지 확인
  → 충분하면 Step 5로 점프

Step 1: 쿼리 분류
  타입:
    Factual lookup — "X란?"          → 관련 페이지 찾기
    Relationship   — "X와 Y 관계?"    → relationships: frontmatter 필수 탐색
    Synthesis      — "X 전반 정리?"    → 관련 모든 페이지 수렴
    Gap            — "X에 대해 뭘 모르나?" → "열린 질문" 섹션 탐색
  모드:
    Index-only — "quick answer", "just scan", "fast lookup" 키워드 → Step 2에서 중단
    Normal     — 전체 파이프라인

Step 2: Index Pass (cheap)
  wiki/index.md 읽기 + frontmatter-only grep으로 후보 5~10개 수집
    패턴: ^(title|tags|summary|tier):
  랭킹 (우선순위 순): title 정확 매치 → tags 매치 → summary에 쿼리 포함 →
                     index.md 항목에 쿼리 포함
    동점 시: tier core > supporting > peripheral (tier 없으면 supporting)

  [Index-only 모드] 여기서 중단하고 summary: 필드 + index.md 설명만으로 답변을 구성한다.
    답변 라벨: "(index-only — 페이지 본문 미읽음, 요약 기반 답변이므로 세부 내용 누락 가능)"
    → **Step 5(답변 합성)를 거쳐** Step 6으로 간다 — 답변 포맷·stale/proposed 라벨은
      모드와 무관하게 모든 경로에 적용된다 (Step 5를 건너뛰면 라벨이 통째로 누락된다)

Step 2b: QMD Semantic Pass (게이트 통과 시만)
  미통과 → 스킵, Step 3으로
  시맨틱 검색으로 키워드 미매치 개념을 보완한다 (후보 수집 전용)
  결과 충분 → Step 4로 점프 (QMD 상위 파일만 전체 읽기)
  결과 불충분 → Step 3

  ⚠️ stale 인덱스 가드: QMD가 가리킨 경로가 실재하지 않거나(삭제·이동) 본문에 해당
     내용이 없으면 → 그 후보를 폐기하고 "QMD 인덱스가 stale할 수 있음,
     wiki-setup --update-qmd 권장" 1줄을 답변에 붙인다

Step 3: Section Pass (medium — Step 2/2b 불충분 시)
  각 후보 파일에 Grep -A 10 -B 2 "<query-term>" <candidate-file>
  15~30줄 획득 (전체 읽기 100~500줄 대비)
  섹션 grep으로 충분 → Step 5로 점프

Step 4: Full Read (expensive — 최후 수단)
  상위 3개 후보 전체 읽기. tier 우선순위 적용 (core → supporting,
  peripheral은 유일한 매치일 때만). [[wiki-link]] 1-hop 허용
  Relationship query: relationships: 블록 탐색 → 타입·방향 명시
    ("Page A contradicts Page B (typed edge)")
  Gap query: "열린 질문" 섹션 확인
  여전히 부족 → vault 전체 content grep + 사용자에게 에스컬레이션 알림

Step 5: 답변 합성 (아래 포맷)

Step 6: wiki/log.md 쿼리 기록 (read-only 예외 — 관찰 기록)
  [YYYY-MM-DD] QUERY query="{질문 요약}" result_pages=N mode=normal|index_only escalated=true|false

Step 7: 답변이 새 지식이면 저장을 제안한다
  관련 knowledge/ 페이지 있음 → 그 페이지에 추가 제안 (wiki-knowledge)
  없음 → 새 knowledge/ 페이지 생성 또는 wiki-capture 제안
```

## 답변 포맷

```
> 위키 기반:
> [답변 + [[wikilinks]] 인용]
> 참고 페이지: [[page-a]], [[page-b]]
> 공백: [wiki가 커버하지 못하는 부분]
```

이 포맷은 **모든 경로에 적용된다** — index-only·hot.md 단독 답변도 Step 5를 거친다.

- **인용은 `[[wikilink]]` 기본이다** (Obsidian 1차 소비 환경 — 클릭 가능하고 페이지 이동 시 자동 추적된다). Step 3·4를 실제 수행한 경우에 한해 검증 편의로 `file_path:line` 힌트를 옆에 부가 표기할 수 있다 — 기본은 wikilink, 라인은 보조다.
- **검색 단계를 인용 뒤에 표시한다:** `found in summary` | `section grep` | `full page read`
- **stale 표시:** `(오늘 − updated:) > 90일` 이면 `[[page]] (stale: last updated YYYY-MM-DD)`
- **미확정 상태 표시** — 미확정 내용을 사실처럼 회수하지 않기 위해:
  - `status: proposed` (changes/ 제안) → `[[page]] (proposed — 미확정 설계)`
  - `[NEEDS CLARIFICATION]` 마커 잔존 (`status: unverified`) → `[[page]] (미확정: 가정 포함)`
- **wiki에 없으면 "wiki에 해당 내용이 없습니다"라고 명시한다.** 임의로 생성하지 않는다.

## 품질 체크

```
□ 가장 싼 경로에서 멈춤 (hot → index → QMD → section → full 중 필요한 단계까지만)
□ 최종 인용을 파일 본문에서 확인 (QMD 캐시 텍스트로 답하지 않음)
□ 인용마다 검색 단계 표시 + stale/proposed/미확정 라벨
□ 커버하지 못한 부분을 `공백:`에 명시
□ 페이지·index·hot·QMD 무수정 (log append만)
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 후보를 찾자마자 전체 읽기로 간다 | 답 하나에 볼트 상당 부분을 컨텍스트로 끌어온다 | hot → index → QMD → section → full 중 답이 나오는 단계에서 멈춘다 |
| QMD가 돌려준 텍스트로 답변한다 | 인덱스가 stale하면 이미 없는 내용을 인용한다 | QMD는 후보 수집만. 인용은 파일 본문에서 확인한다 |
| proposed·`[NEEDS CLARIFICATION]` 페이지를 그냥 인용한다 | 미확정 설계와 가정이 사실로 회수된다 | "(proposed — 미확정 설계)" / "(미확정: 가정 포함)" 표시 |
| 90일 넘은 페이지를 현행처럼 인용한다 | 낡은 정보가 최신 사실로 읽힌다 | `(stale: last updated YYYY-MM-DD)` 인라인 표시 |
| 볼트에 없는 부분을 일반 지식으로 메꾼다 | wiki 기반 답변과 모델 지식이 구분되지 않는다 | "wiki에 해당 내용이 없습니다" + `공백:` |
| 답이 좋으니 `knowledge/`에 정리해 저장한다 | 조회가 볼트를 바꿔 read-only 경계가 무너진다 | 저장은 제안만. 실행은 `wiki-knowledge`·`wiki-capture` |
| `log.md` append가 실패해 답변을 취소·재시도한다 | 이미 전달된 답변을 없던 일로 만든다 | log 실패는 스킬 실패가 아니다 |
