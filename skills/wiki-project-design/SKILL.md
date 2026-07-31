---
name: wiki-project-design
description: 프로젝트의 설계 문서를 만들거나 진화시킬 때 사용한다 — architecture, domain 모델(용어집 + 도메인·비즈니스 규칙), conventions. 볼트에서 근거를 끌어오고, 변경을 changes 폴더에 ADDED/MODIFIED/REMOVED 델타로 제안하고, 승인 후 병합한다. 사용자가 "아키텍처 잡자"·"설계 업데이트"·"도메인 규칙 정리"·"비즈니스 로직 정리"라고 하거나 프로젝트의 논리 구조를 논의할 때 사용한다.
---

# wiki-project-design

프로젝트의 **고빈도 진화** 문서를 소유한다: `architecture.md` · `domain.md` · `conventions.md`. 살아있는 설계이므로 의미 변경은 `changes/` proposal을 거쳐 병합한다.

시작 전 두 가지를 로드한다:
- `using-llm-wiki` — Config Gate, 종료 시퀀스, QMD refresh, 페이지 포맷
- `using-llm-wiki` 의 `references/project-docs.md` — 컨셉·공통 원칙 10개·디렉토리 구조·생애주기·접근 권한 매트릭스·decisions.md 항목 형식

다이어그램 문법·C4 표기 규칙은 이 스킬의 `references/mermaid-conventions.md`.

## 변경 유형 판별 — 표면 vs 의미

- **표면 변경** (오타, 현황 숫자, 링크 보수, 표현 다듬기) → proposal 생략, 바로 통합 갱신.
- **의미 변경** (주장·구조·기술 선택이 바뀜) → **change proposal 필수.** 1인 사용자라도 AS-IS→TO-BE와 의사결정 과정이 이력으로 남아야 차기 프로젝트 설계의 재료가 된다.

## change proposal 라이프사이클

```
제안 → 승인 → 병합 + 박제

1.  changes/YYYY-MM-DD-{slug}.md 생성 (status: proposed)
2.  사용자 검토 — 승인 / 수정 요청 / 거부
3a. 승인 → 대상 문서에 delta 병합(통합 갱신)
         → decisions.md 항목 append ([[change]] 링크 포함)
         → proposal을 changes/archive/로 이동 (status: applied, status_changed 갱신)
3b. 거부 → changes/archive/로 이동 (status: rejected + 사유) — 거부도 설계 이력이다
```

**QMD 인덱싱:** proposed를 포함해 전체 인덱싱한다(별도 제외 없음). 대신 frontmatter로 구분한다 — `base_confidence: 0.3`(전체 최저) + `tier: peripheral`. `wiki-query` 랭킹이 tier를 실제 적용하므로 proposed는 자연 강등되고, 인용 시 "(proposed — 미확정 설계)" 표시 책임은 `wiki-query`에 있다.

**링크 안정성:** proposal을 참조하는 링크는 처음부터 **최종 archive 경로** `[[changes/archive/YYYY-MM-DD-{slug}]]`로 쓴다 — 이동 후 깨짐 방지.

**다중 파일 실패 처리:** proposal 생성·delta 병합·decisions append·archive 이동·index/log/QMD는 detect-and-repair를 따른다 — 중간 실패는 `wiki-lint`의 change proposal 무결성 체크가 감지·수리한다(proposed 방치·archive 미이동·decisions 링크 누락). 전용 트랜잭션·staging은 두지 않는다.

## change proposal 템플릿

frontmatter는 문서 클래스 ② 축소셋이다 (`tags`·`sources`·`updated` 비필수 — 델타 문서라 근거는 본문 `## 근거`의 `[[링크]]`가 담당한다).

```markdown
---
title: "{변경 한 줄 제목}"
category: projects
project: "{name}"
targets: ["architecture.md"]
status: proposed   # proposed | applied | rejected
created: YYYY-MM-DD
status_changed: YYYY-MM-DD
summary: "≤400자"
base_confidence: 0.3   # 전체 소스 유형 중 최저 — proposed는 미확정 설계
tier: peripheral       # wiki-query 랭킹 최하위
---

## 동기
[왜 이 변경이 필요한가]

## Delta
### MODIFIED: architecture.md › 컨테이너 (C4 L2)
**AS-IS**: [현재 내용 요약·인용]
**TO-BE**: [변경 후 내용]

### ADDED: architecture.md › 기술 스택 결정 근거
[추가 내용]

### REMOVED: domain.md › {용어}
[제거 사유]

## 근거
[(출처: [[knowledge-페이지]]) 인용. 없으면 ⚠️ unverified + missing knowledge 기록]

## 영향
[영향받는 페이지 [[링크]], 후속 작업, 깨질 수 있는 것]
```

## 대상 문서 구조

**architecture.md 권장 구조:**

```markdown
## 시스템 컨텍스트 (C4 L1)   ← 외부 시스템·사용자 경계. mermaid 권장
## 컨테이너 (C4 L2)          ← 배포 단위·기술 스택. mermaid 권장
## 핵심 컴포넌트 (C4 L3)      ← 복잡한 부분만
## 기술 스택 결정 근거         ← (출처: [[knowledge]]) + [[decisions]] 링크
```

**domain.md — 도메인 모델(용어집 + 규칙):** 단순 용어집이 아니다. ① 고유 용어·매핑(유비쿼터스 언어) + ② **도메인 규칙·불변식**(항상 참인 제약, 예: "주문은 결제 완료 후에만 배송") + ③ **비즈니스 로직**(상태 전이·계산 규칙·정책)을 담는다. 규칙은 자연어로 기술하고 코드는 필요 시 **간단한 예시로만** 첨부한다. 일반 개념은 본문 복제 없이 `[[knowledge]]` 링크로 둔다.

```markdown
## 용어집              ← 고유 용어·매핑 (유비쿼터스 언어)
## 도메인 규칙·불변식    ← 항상 참인 제약 (출처: 논의 | [[knowledge]])
## 비즈니스 로직         ← 상태 전이·계산·정책 (코드는 간단한 예시만)
```

summary 400자·2화면을 넘으면 `domain/` 서브폴더로 **BC(bounded context)별 분할**한다 — `domain/index.md`(BC 목록 + 공통 용어·규칙) + `domain/{bc}.md`(BC별 ubiquitous language + 규칙). 같은 용어·규칙이 BC마다 다른 의미일 수 있어 BC가 분할 경계다. 구조 변경도 "신규 페이지 먼저, index 나중" 순서를 따른다.

**conventions.md — 부차적·논리 우선:** `projects/`의 1차 콘텐츠는 domain.md의 도메인 규칙·비즈니스 로직이고 코드 컨벤션은 부차적이다. 코드베이스에서 추출하는 게 아니라 **합의된 규칙을 논리적으로 기술**하고 코드는 간단한 예시로만 보인다. 코드 프로젝트가 아니면 생략한다.

**다이어그램 — 권장 + on-demand (의무 아님):** Obsidian Mermaid 네이티브 렌더링 환경이므로 C4 L1·L2를 권장 섹션으로 둔다. **그릴 가치가 있을 때만 작성하고 빈 다이어그램을 강제하지 않는다.** L3는 복잡한 부분만. 다이어그램도 의미 변경 시 proposal 대상이다.

## 워크플로

```
Step 0:   Config Gate
Step 0.5: hot.md 읽기

Step 1: 대상 문서·변경 유형 판별
  표면 → Step 5로 직행 / 의미 → Step 2

Step 2: 재료 수집
  대화에서 요구·제약·선택 수집
    (기존 프로젝트를 문서화하는 경우 대화 컨텍스트의 **코드 분석 결과 포함**)
  wiki-query로 knowledge/·summaries/ 근거 검색 — architecture 작업 시 필수 실행
  기존 changes/archive/ 이력 확인 (같은 주제의 재변경인지)

Step 3: change proposal 작성 (status: proposed) → 사용자 검토 요청

Step 4: [의미 변경 경로]
  승인 → apply 전 target 문서를 재읽어 AS-IS가 현행과 일치하는지 확인한다.
         불일치 시 proposal을 갱신하고 재승인받는다 (checksum 저장이 아니라 본문 재확인).
       → delta 병합 + decisions.md append + archive 이동 → Step 6
         decisions.md 는 using-llm-wiki 의 project-docs.md 항목 형식을 직접 준수한다 (위임 호출 없음)
  거부 → archive 이동 (rejected + 사유) 후 종료 시퀀스로

Step 5: [표면 변경 전용] 통합 갱신 실행 (append 금지).
        domain.md 의 일반 개념은 [[knowledge]] 링크로

Step 6: 자가검증 체크리스트 루프 (최대 2회)
Step 7: gap report (missing knowledge 포함)
Step 8: 공통 종료 시퀀스 — index → log → hot → QMD refresh
  [YYYY-MM-DD] PROJECT-DESIGN name="{name}" change="{slug}|surface" files=[...]
```

## 품질 체크

```
□ 의미 변경에 change proposal 존재 (표면 변경만 직접 갱신)
□ applied proposal마다 decisions.md 항목 + [[change]] 링크 (스냅샷-기록 짝)
□ AS-IS/TO-BE 가 구체적 (요약이 아니라 비교 가능한 수준)
□ apply 전 target 본문 재확인으로 AS-IS 현행성 검증
□ 기술 주장에 (출처: [[...]]) 또는 ⚠️ unverified + missing knowledge 기록
□ domain.md 에 일반 개념 본문 복제 없음 ([[knowledge]] 링크)
□ 다이어그램은 references/mermaid-conventions.md 준수 (빈 다이어그램 없음)
□ archive 링크를 처음부터 최종 경로로 작성
□ index.md 등록 · log.md 기록 · hot.md 갱신 · QMD refresh + 상태 문자열
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 기술 선택 변경을 표면 변경으로 보고 바로 반영한다 | AS-IS→TO-BE 이력이 사라져 차기 설계의 재료를 잃는다 | 의미 변경은 proposal 경유 |
| proposal의 AS-IS를 믿고 병합한다 | 그 사이 바뀐 본문을 덮어쓴다 | apply 전 target 본문을 재확인하고 불일치 시 재승인 |
| delta만 병합하고 `decisions.md`는 나중에 미룬다 | 스냅샷-기록 짝이 깨져 "왜"가 사라진다 | 병합과 같은 흐름에서 append |
| proposal 링크를 `changes/` 경로로 쓴다 | archive 이동 후 링크가 깨진다 | 처음부터 `changes/archive/` 경로 |
| 승인·거부된 proposal을 `changes/` 루트에 남긴다 | 진행 중 제안과 종료된 제안이 섞인다 | `archive/`로 이동 (거부도 설계 이력) |
| 일반 개념 설명을 `domain.md` 본문에 복제한다 | `knowledge/`와 중복돼 갱신이 갈라진다 | `[[knowledge]]` 링크 |
| 코드베이스를 읽어 `architecture.md`를 역추출한다 | 논리적 콘텐츠가 코드 구조 덤프로 바뀐다 | 대화 컨텍스트의 분석 결과를 합성 |
| 권장 섹션마다 다이어그램을 채운다 | 정보 없는 그림이 산문을 밀어낸다 | 그릴 가치가 있을 때만 |
| proposed proposal에 보통 신뢰도를 준다 | 미확정 설계가 확정 문서와 같은 순위로 회수된다 | `base_confidence: 0.3` + `tier: peripheral` |
