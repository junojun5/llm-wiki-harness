---
name: wiki-project-design
description: 프로젝트의 design 문서를 만들거나 발전시킬 때 사용 — architecture, domain model(용어집 + 도메인/비즈니스 규칙), conventions — projects/{name}/에. "design the architecture", "update the design", "capture the domain rules", "/wiki-project-design".
---

# wiki-project-design

change proposal을 통해 프로젝트의 design 문서(`architecture.md`, `domain.md`, `conventions.md`)를 생성/발전시킨다. 먼저 Config Gate. 이 세 문서를 소유하며; 증거는 knowledge/summaries에서 끌어온다.

## Surface vs semantic 변경 (결정적)
- **Surface** (오타, 상태 숫자, 링크 복구, 문구) → 직접 편집, 통합.
- **Semantic** (주장, 구조, 또는 기술 선택이 바뀜) → **change proposal 필수.** design 문서의 *의미*를 절대 직접 편집하지 않는다 — AS-IS→TO-BE와 결정 흔적은 history로 남아야 한다 (1인 사용자라도; 다음 프로젝트의 재료다).

## Change-proposal 라이프사이클
1. `changes/YYYY-MM-DD-{slug}.md` 생성, `status: proposed`. Class-② frontmatter: title / category=projects / project / targets / status / created / status_changed / summary / `base_confidence: 0.3` / `tier: peripheral`. 본문: `## 동기` / `## Delta` (ADDED/MODIFIED/REMOVED, 각각 **AS-IS** + **TO-BE**) / `## 근거` (`(출처: [[knowledge]])` 또는 `⚠️ unverified` + missing-knowledge 노트) / `## 영향`.
2. 사용자 검토 → 승인 / 수정 / 거부.
3a. **승인 →** 대상 문서를 다시 읽어 **AS-IS가 여전히 현재 내용과 일치하는지 확인** (저장된 체크섬이 아니라 본문을 재검증); 드리프트했으면 proposal을 갱신하고 재승인. 그다음: delta 병합 (통합, append 아님) → `decisions.md` 항목을 **직접** append (§4-9-3 포맷; `변경 기록: [[changes/archive/YYYY-MM-DD-{slug}]]`를 **최종 archive 경로**로 써서 이동 후에도 링크가 살아남게) → proposal을 `changes/archive/`로 이동 (`status: applied`, `status_changed` 갱신).
3b. **거부 →** `changes/archive/`로 이동 (`status: rejected` + 이유). 거부도 design history다.

시퀀스 중간 실패는 괜찮다: lint 체크 16이 방치된 proposed / 미-archive / 누락된 decisions 링크를 탐지; git이 롤백 (§3-6 — 스테이징/트랜잭션 없음).

## 워크플로우
0. Config Gate. 0.5 hot.md. 1. 대상 문서 + 변경 유형 식별 (surface → step 5; semantic → step 2). 2. 자료 수집 (코드 분석 결과 포함 대화; **wiki-query knowledge/summaries — architecture 작업에 필수**; 같은 주제의 이전 history를 `changes/archive/`에서 확인). 3. proposal 작성 (proposed) → 검토 요청. 4. (semantic) 승인 → AS-IS 재검증 → 병합 + decisions append + archive; 거부 → archive. 5. (surface) 직접 통합; domain.md에서 일반 개념은 `[[knowledge]]` 링크로 (본문 중복 없음). 6. 자기 검증 루프. 7. Gap 리포트 (missing knowledge 포함). 8. 종료 시퀀스. log: `[YYYY-MM-DD] PROJECT-DESIGN name="…" change="{slug}|surface" files=[…]`.

## 문서 구조
- **architecture.md:** 시스템 컨텍스트 (C4 L1) / 컨테이너 (C4 L2) — mermaid 권장 (`references/mermaid-conventions.md` 참조) / 핵심 컴포넌트 (L3, 복잡한 부분만 on-demand) / 기술 스택 결정 근거 (`(출처: [[knowledge]])` + `[[decisions]]`).
- **domain.md** = 도메인 모델: 용어집 (ubiquitous language) / 도메인 규칙·불변식 / 비즈니스 로직 (code = 간단한 예시만; 코드베이스에서 역추출 절대 금지 — Phase 2). 일반 개념 → `[[knowledge]]` 링크. >400자 요약 또는 >2화면 → bounded context별로 `domain/{bc}.md`로 분할.
- **conventions.md:** 부차적, 로직 우선 (합의된 규칙을 서술; 코드는 간단한 예시로만). 코드 프로젝트만.

## decisions.md 공동 작성 경계
**design을 바꾸는 결정**의 `decisions.md` 짝은 직접 append한다 (포맷은 record의 단일 출처; 위임 호출 없음). design과 *무관한* 결정은 wiki-project-record에 속한다. 둘은 `변경 기록:` 줄로 구별된다 (존재 ⟺ design을 경유함).

## 품질 체크
의미 변경에 change proposal 존재 (표면 변경만 직접 갱신) · applied proposal마다 decisions.md 항목 + `[[change]]` 링크 (스냅샷-기록 짝) · AS-IS/TO-BE가 구체적 (요약이 아니라 비교 가능한 수준) · 기술 주장에 `(출처: [[...]])` 또는 `⚠️ unverified` + missing knowledge 기록 · domain.md에 일반 개념 본문 복제 없음 (`[[knowledge]]` 링크) · 다이어그램은 mermaid-conventions.md 준수 · index/log/hot/QMD 갱신됨 (§3-5).
