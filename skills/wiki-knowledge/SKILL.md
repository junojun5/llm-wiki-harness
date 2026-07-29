---
name: wiki-knowledge
description: 여러 summaries·concepts·sessions를 종합해 knowledge 페이지를 만들거나 갱신할 때 사용한다. 중복 통합, 충돌 감지, 커진 페이지의 서브폴더 분할을 처리한다. 트리거는 "knowledge 페이지 만들어줘"·"이 주제 정리해줘"·"summaries 종합해줘"·"knowledge 업데이트해줘".
---

# wiki-knowledge

여러 `summaries/`·`concepts/`·`sessions/`를 재료로 심층 `knowledge/` 페이지를 만들고 유지한다. (`wiki-ingest`는 소스 1개를 summaries에 1:1로 저장한다 — 역할이 다르다.)

시작 전 `using-llm-wiki` 스킬을 로드한다 — Config Gate, 종료 시퀀스, QMD refresh, 페이지 포맷(`references/page-format.md`).

**knowledge는 두 가지를 종합한다:** ① `summaries`·`concepts`에서 증류된 공식·신뢰성 있는 지식 + ② 사용자의 궁금증·조사·경험(`wiki-query` 결과 포함). 생성은 **사용자 주도만**이다.

## 페이지 템플릿

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
  - target: "[[summaries/articles/topic/source-a]]"
    type: depends_on
  - target: "[[concepts/related-concept]]"
    type: extends
---

## 개요
[2-3문장: 왜 중요한가, 이 페이지로 무엇을 이해하게 되는가]

## 핵심 개념
[유추·예시로 설명. 다이어그램 가능]

## 작동 원리 / 구조
[내부 메커니즘, 관계]

## 트레이드오프
| 선택 | 장점 | 비용 |
|---|---|---|

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
- 개요~트레이드오프 = summaries·concepts에서 증류된 공식 지식 (WHY 중심)
- 실제 사례 = 직접 경험·현장 적용
- 나의 노트 = 개인 의문·조사. `provenance`의 inferred/ambiguous 마커가 붙는 내용
- 열린 질문 = 문헌 갭 (소스가 답하지 않은 것)

**sources vs relationships:** `sources:`는 최종 원본 URL·conversation(외부 출처), `relationships: depends_on`은 **합성 경로**(어떤 summaries·concepts에서 증류됐나)다. 섞으면 provenance 추적이 복잡해진다.

## 워크플로

```
Step 0:   Config Gate
Step 0.5: wiki/hot.md 읽기 (있으면) — 동일 주제가 이미 캡처됐는지 확인.
          관련 summaries·sessions가 언급돼 있으면 Step 2 재료 수집에 우선 포함

Step 1: 대상 knowledge 페이지 존재 여부 확인
  없음 → 신규 생성 모드 (Step 2 → 2.5 → 5)
  있음 → 업데이트 모드   (Step 2 → 3 → 4 → 5)

Step 2: 재료 수집
  사용자가 지정한 summaries·concepts·sessions 읽기
  wiki/index.md grep으로 관련 기존 페이지 파악
  각 재료의 sources: 에서 원본 URL 추출 (knowledge 페이지 sources: 구성용)

Step 2.5: [신규 생성 모드 전용] 합성 계획 미리보기 — 쓰기 전 확인
  신규 knowledge는 합성·해석 비중이 높으므로 쓰기 전에 계획을 보고한다:
    - sources_used: 어떤 summaries·concepts·sessions를 합성하는지 목록
    - 섹션별 핵심 주장 개요 (개요·핵심 개념·트레이드오프에 무엇이 들어가는지)
    - 예상 provenance: inferred/ambiguous 비중이 높으면 미리 표시 (해석 비중 신호)
  확인 후 진행하고, 자연어로 범위·강조점 조정을 허용한다.
  승인 절차가 아니라 "이 방향이 맞나" 확인이다 — 게이트는 가볍게 둔다

Step 3: [업데이트 모드 전용] 기존 페이지 전체 읽기 + 변경 분석
  재료와 기존 페이지의 각 주장을 정성 분류한다 (수치 임계값이 아니다):
    □ 동일 주장       — 의미가 같음 → 본문 유지 + sources·relationships에 출처만 추가
    □ 표현·상세도 차이 — 한쪽이 다른쪽을 포함하거나 더 구체 → 더 정확·구체한 쪽으로 통합 (충돌 아님)
    □ 범위·맥락 차이   — 다른 조건·맥락의 주장 → 둘 다 보존, 맥락 명시해 통합 (충돌 아님)
    □ 정면 모순       — 같은 대상에 양립 불가한 주장 → status: conflict 예정 + 충돌 노트 준비
    □ 신규           — 기존에 없는 정보 → 적절한 섹션에 통합
    □ 구조 변경 필요   — 아래 분할 트리거 해당 여부
  1차 분류는 직접 한다. **"정면 모순"만 사용자 확정 대상**이고 나머지는 Step 4 보고 후 진행한다

Step 4: [업데이트 모드 전용] 변경 계획 보고
  예: "다음 변경을 적용합니다:
       - [통합] 핵심 개념 섹션에 attention mechanism 내용 추가
       - [출처 보강] 트레이드오프 3번 항목에 새 논문 출처 추가
       - [충돌] '학습률 고정' 주장 — 기존 [[source-a]]와 모순. 확인 필요
       - [구조 제안] 페이지 30% 증가 → 서브폴더 분할 권장 (별도 확인)"
  충돌·구조 변경은 사용자 확인 후 진행하고, 나머지는 바로 실행한다

Step 5: 페이지 작성·업데이트
  신규   → 위 템플릿 그대로 생성
  업데이트 → 기존 구조를 유지하며 **통합**한다 (append 금지)
  충돌 확정 → status: conflict + 충돌 노트 삽입 + status_changed 갱신
  구조 변경 확정 → 아래 "분할"

Step 6: wiki/index.md + wiki/log.md 갱신
  [YYYY-MM-DD] KNOWLEDGE mode=create|update page="{경로}" sources_used=N
  (업데이트 시) changes="merge|conflict|restructure"

Step 7: wiki/hot.md 갱신
Step 8: QMD refresh — 모든 쓰기 완료 후 마지막에
```

## 분할 — 파일이 커지면 서브폴더로

**트리거 (하나라도 해당되면 제안한다):**

```
□ summary: 400자 초과 (페이지 범위가 너무 넓다)
□ 특정 섹션이 스크롤 2화면 초과
□ 특정 섹션이 다른 페이지에서 단독으로 링크됨 (독립 인용 필요)
□ 신규 내용이 기존 페이지의 30% 이상 추가될 때
```

```
wiki/knowledge/{주제}/
  index.md        ← 전체 개요 2-3문장 + 하위 페이지 목차(각 한 줄 설명) + 읽기 순서
  {subtopic1}.md     자체 본문은 최소화하고 각 sub-page로 위임한다
  {subtopic2}.md
```

**순서는 원본 먼저다:** 신규 서브폴더 페이지를 먼저 쓰고 검증한 뒤에야 원본을 `index.md`로 전환한다. 인바운드 링크·`relationships` 재작성은 파생물이므로, 중간에 실패해도 `wiki-lint`가 깨진 링크·중복·orphan으로 감지·수리하고 롤백은 git이 맡는다 — 전용 staging·백업은 두지 않는다.

## 품질 체크

```
□ (신규) 합성 계획 미리보기 후 확인 — sources_used·핵심 주장·예상 provenance
□ 모든 주장에 출처 명시 (sources: 또는 인라인 (출처: [[페이지]]))
□ relationships: depends_on 으로 합성 경로 추적
□ 나의 노트의 추론·불확실 내용에 ^[inferred] / ^[ambiguous] 마커
□ provenance: 블록 설정 (inferred/ambiguous 비중이 높은 경우)
□ [[wiki-link]] 최소 2개 · summary ≤ 400자
□ index.md 등록 · log.md 기록 · hot.md 갱신
□ QMD refresh 실행 + 상태 문자열 보고
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 재료를 모아 신규 페이지를 바로 쓴다 | 합성 방향이 어긋난 것을 다 쓴 뒤에 알게 된다 | Step 2.5 합성 계획 미리보기 |
| 새 내용을 섹션 끝에 덧붙인다 | 같은 주제가 여러 문단에 흩어져 페이지가 누적물이 된다 | 기존 구조를 유지하며 통합 |
| 표현·상세도가 다른 주장을 conflict로 올린다 | 판단 대기가 쌓여 conflict 신호 자체가 무의미해진다 | 정면 모순만 conflict. 나머지는 4분류로 통합 |
| "몇 % 이상 다르면 충돌" 같은 수치로 판정한다 | 측정 불가한 기준을 만들어 일관성이 사라진다 | 정성 루브릭 4분류 |
| 분할할 때 원본을 `index.md`로 먼저 바꾼다 | 하위 페이지가 없는 채로 목차만 남는다 | 신규 페이지를 먼저 쓰고 검증한 뒤 전환 |
| 합성 재료 페이지를 `sources:`에 넣는다 | 외부 출처와 합성 경로가 섞여 provenance 추적이 무너진다 | 재료는 `relationships: depends_on` |
| ingest 흐름에서 knowledge를 자동 생성한다 | 사용자 주도 원칙이 무너진다 | 명시 요청 시만 |
