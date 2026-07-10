---
name: wiki-knowledge
description: 여러 요약·개념·세션을 종합해 knowledge 페이지를 만들거나 갱신할 때 사용 — "종합해줘", "정리해서 knowledge로", "이 주제 정리해줘", "summaries 종합해줘", "/wiki-knowledge".
---

# wiki-knowledge

## 개요
`summaries/` · `concepts/` · 대화 세션 여러 개를 가로질러 증류한 살아있는 `knowledge/` 페이지를 만들거나 갱신한다. `wiki-ingest`가 소스 1개당 요약 1개를 만드는 것과 달리, 이 스킬은 소스 *전반에 걸쳐* 종합(synthesis)한다 — 재료를 그대로 옮기지 않고 해석·통합한다.

> **MUST — 사용자 주도만.** `knowledge/` 페이지는 이 스킬을 통한 사용자의 명시적 요청으로만 생성·갱신된다.
> - ✅ 사용자가 "종합해줘" / "정리해서 knowledge로" 등으로 명시 요청.
> - ❌ `wiki-ingest`·`ingest-url`이 ingest 도중 자동으로 `knowledge/` 페이지를 만드는 것 — **금지**.

## 언제 사용
- **트리거:** "knowledge 페이지 만들어줘", "이 주제 정리해줘", "summaries 종합해줘", "knowledge 업데이트해줘", `/wiki-knowledge`.
- **아니면:** 소스 1개를 그대로 요약할 때는 `wiki-ingest`/`ingest-url`. 지금 대화 자체를 캡처할 때는 `wiki-capture`(승격은 사용자 명시 요청 시만, 이 스킬로 위임).

## 워크플로우

0. **Config Gate** (`using-llm-wiki` 참조).
0.5. **`wiki/hot.md` 읽기** (있으면) — 최근 활동·진행 중 스레드 파악. 동일 주제가 이미 캡처됐는지 확인하고, 관련 summaries·sessions가 언급돼 있으면 Step 2 재료 수집에 우선 포함한다.
1. **대상 knowledge 페이지 존재 여부 확인.**
   - 없음 → **신규 생성 모드**: Step 2 → 2.5 → 5.
   - 있음 → **업데이트 모드**: Step 2 → 3 → 4 → 5.
2. **재료 수집.** 사용자가 지정한 summaries·concepts·sessions를 읽는다. `wiki/index.md`를 grep해 관련 기존 페이지를 파악한다. 각 재료의 `sources:`에서 원본 URL을 추출한다(신규 knowledge 페이지의 `sources:` 구성용).
2.5. **[신규 생성 모드 전용] 쓰기 전 종합 계획 미리보기.** 신규 knowledge는 합성·해석 비중이 높으므로, 업데이트 모드의 Step 4와 대칭으로 쓰기 전에 아래를 보고하고 확인받는다:
   - `sources_used` — 어떤 summaries·concepts·sessions를 합성하는지 목록.
   - 섹션별 핵심 주장 개요(개요·핵심 개념·트레이드오프에 무엇이 들어가는지).
   - 예상 provenance — inferred/ambiguous 비중이 높으면 미리 표시(해석 비중 신호).
   확인 후 진행. 자연어로 범위·강조점 조정 허용. 1인 로컬 전제이므로 가벼운 게이트다 — 승인 절차가 아니라 "이 방향이 맞나" 확인.
3. **[업데이트 모드 전용] 기존 페이지 전체 읽기 + 변경 분석.** 재료와 기존 페이지의 각 주장을 정성적으로 분류한다(수치 임계값 아님):
   - **동일 주장** → 본문 유지 + `sources`·`relationships`에 출처만 추가.
   - **표현·상세도 차이** → 더 정확·구체한 쪽으로 통합(충돌 아님).
   - **범위·맥락 차이** → 둘 다 보존, 맥락 명시해 통합(충돌 아님).
   - **정면 모순** → `status: conflict` 예정 + `## Conflicts` 노트 준비(§3-3).
   - **신규** → 적절한 섹션에 통합.
   - **구조 변경 필요** → 아래 분할 트리거 해당 여부 확인.
   LLM이 1차 분류한다. "정면 모순"만 사용자 확정 대상, 나머지는 Step 4 보고 후 진행.
4. **[업데이트 모드 전용] 변경 계획을 사용자에게 보고.** 예:
   ```
   다음 변경을 적용합니다:
   - [통합] 핵심 개념 섹션에 attention mechanism 내용 추가
   - [출처 보강] 트레이드오프 3번 항목에 새 논문 출처 추가
   - [충돌] '학습률 고정' 주장 — 기존 [[source-a]]와 모순. 확인 필요
   - [구조 제안] 페이지 30% 증가 → 서브폴더 분할 권장 (별도 확인)
   ```
   충돌·구조 변경은 사용자 확인 후 진행. 나머지는 바로 실행.
5. **페이지 작성 / 업데이트.** 아래 템플릿 구조를 준수한다.
   - **신규** → 템플릿 그대로 생성.
   - **업데이트** → 기존 구조 유지하며 **병합**(통합, append 금지).
   - **충돌 확정 시** → `status: conflict`, `## Conflicts` 노트 삽입(§3-3), `status_changed` 갱신.
   - **구조 변경 확정 시** → 서브폴더 생성 + `index.md` 분리. 신규 서브폴더 페이지를 먼저 쓰고 검증한 뒤에야 원본을 `index.md` 허브로 전환한다(원본 먼저, §3-6). 인바운드 링크·relationships 재작성 중 실패는 wiki-lint가 감지·수리하고 롤백은 git이 맡는다 — 전용 staging·백업 트랜잭션은 두지 않는다.
6. **`wiki/index.md` + `wiki/log.md` 갱신.**
   ```
   [YYYY-MM-DD] KNOWLEDGE mode=create|update page="{경로}" sources_used=N
   (업데이트 시) changes="merge|conflict|restructure"
   ```
7. **`wiki/hot.md` 갱신** — Recent Activity(생성/업데이트한 페이지 한 줄, 최근 3개 유지) · 심층 인사이트·새 합성 결과 있으면 Key Takeaways 갱신 · 진행 중 주제가 knowledge로 구체화됐으면 Active Threads 갱신 · `updated` 타임스탬프 갱신.
8. **QMD refresh** — hot.md까지 모든 쓰기 완료 후 마지막에 실행(`using-llm-wiki` 참조).

## 페이지 템플릿

Diátaxis Explanation + Zettelkasten concept note + Developer Docs Framework 종합.

```markdown
---
title: "[개념] 이해하기"
category: knowledge
tags: [tag1, tag2]
sources: ["https://원본-URL-1", "https://원본-URL-2"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
summary: "≤400자 요약"
status: verified | unverified | conflict
base_confidence: 0.0-1.0
relationships:
  - target: "[[source-a]]"
    type: depends_on
  - target: "[[related-concept]]"
    type: extends
---

## 개요
[2-3문장: 왜 중요한가, 이 페이지로 무엇을 이해하게 되는가]

## 핵심 개념
[유추·예시로 설명. 다이어그램 가능]

## 작동 원리
[내부 메커니즘, 관계]

## 트레이드오프
| 선택 | 장점 | 비용 |
|------|------|------|

## 실제 사례
[적용 예시, 현장 경험]

## 나의 노트
[개인 의문·조사·wiki-query 결과·실험. ^[inferred] / ^[ambiguous] 마커 사용]

## 열린 질문
[소스·문헌이 답하지 않은 갭. 탐구 방향]

## 관련 페이지
- [[related-concept]]
```

**섹션 원칙:**
- 개요~트레이드오프 = summaries·concepts에서 증류된 공식 지식(WHY 중심, Diátaxis Explanation).
- 실제 사례 = 직접 경험·현장 적용.
- 나의 노트 = 개인 의문·조사. `^[inferred]`/`^[ambiguous]` 마커가 붙는 내용.
- 열린 질문 = 문헌 갭(소스가 답하지 않은 것).

**`sources:` vs `relationships:` — 혼동 금지:**
- `sources:` → 최종 원본 URL·conversation(외부 출처).
- `relationships: depends_on` → 합성 경로(어떤 summaries/concepts에서 증류됐나, lineage).
- `## 관련 페이지` → 사람이 읽는 내비게이션 링크. 위 두 필드와 다른 목적이다.

## 중첩링크 주의

`relationships.target`의 `[[...]]`는 **frontmatter 중첩 필드 안에 있어 Obsidian 그래프·백링크로 인식되지 않는다** — QMD·CLI의 표준 YAML 파서는 정상 해석하지만, Obsidian은 파싱만 되고 그래프에 반영하지 않는다(spec §3-3). 이 필드의 소비자는 wiki-query 같은 머신이지 Obsidian 그래프가 아니다.

**따라서 사람용 연결은 반드시 본문에도 만든다:**
- ✅ 합성 계보를 나타내는 재료는 `relationships: depends_on`에 기록**하고**, 사람이 따라갈 연결은 본문 `[[slug]]` 링크와 `## 관련 페이지` 섹션에 둔다.
- ❌ `relationships:`에만 링크를 넣고 본문·관련 페이지에 대응 링크를 두지 않는 것 — 그래프·백링크상 고아처럼 보인다.

## 분할 트리거

하나라도 해당되면 서브폴더 분할을 제안한다:
```
□ summary: 400자 초과 (페이지 범위 너무 넓음)
□ 특정 섹션이 스크롤 2화면 초과
□ 특정 섹션이 다른 페이지에서 단독으로 링크됨 (독립 인용 필요)
□ 신규 내용이 기존 페이지의 30% 이상 추가될 때
```

분할 시:
```
wiki/knowledge/{주제}/
  index.md        ← 전체 개요 + 하위 페이지 목차 (navigation hub)
  {subtopic1}.md
  {subtopic2}.md
```
`index.md`는 전체 주제 개요(2-3문장) + 하위 페이지 목차·한 줄 설명 + 읽기 순서만 담고, 본문은 각 하위 페이지로 위임한다(Diátaxis landing page 원칙). 신규 서브폴더 페이지를 먼저 쓰고 검증한 뒤 원본을 허브로 전환한다(원본 먼저, §3-6).

## 품질 체크
```
□ (신규 생성) 종합 계획 미리보기 후 확인 — sources_used·핵심 주장·예상 provenance
□ 모든 주장에 출처 명시 (sources: 또는 인라인 (출처: [[페이지]]))
□ relationships: depends_on으로 합성 경로 추적
□ 본문 [[slug]] 링크 · ## 관련 페이지에도 사람용 연결 존재 (중첩링크만 두지 않음)
□ 나의 노트 섹션의 추론·불확실 내용에 ^[inferred] / ^[ambiguous] 마커
□ provenance: 블록 설정 (inferred/ambiguous 비중이 높은 경우)
□ 최소 2개 [[slug]] 연결
□ (업데이트) 정면 모순은 status: conflict + ## Conflicts, 나머지는 병합(append 아님)
□ index.md 등록, log.md 기록
□ summary: ≤400자
□ hot.md 갱신 (Recent Activity + 해당 시 Key Takeaways / Active Threads)
□ QMD refresh 실행 — update → 필요 시 embed → 검증 → 상태 문자열 보고
```
