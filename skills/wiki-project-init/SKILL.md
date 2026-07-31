---
name: wiki-project-init
description: wiki에서 프로젝트를 시작하거나 재프레이밍할 때 사용한다 — 가이드 인터뷰로 projects 하위에 overview·context·goals를 만든다. 사용자가 "프로젝트 기획하자"·"X 프로젝트 시작"·"프로젝트 문서 세팅"이라고 할 때 사용한다.
---

# wiki-project-init

프로젝트의 **저빈도 스냅샷** 문서를 인터뷰로 세운다: `overview.md` · `context.md` · `goals.md`. 한번 쓰면 거의 고정되는 문서들이다.

시작 전 두 가지를 로드한다:
- `using-llm-wiki` — Config Gate, 종료 시퀀스, QMD refresh, 페이지 포맷
- `using-llm-wiki` 의 `references/project-docs.md` — 컨셉·공통 원칙 9개·디렉토리 구조·생애주기·접근 권한 매트릭스

설계 문서(architecture·domain·conventions)에는 직접 쓰지 않는다 — 그건 `wiki-project-design`이다.

## 인터뷰 패턴

- 파일별 필수 질문을 **한 번에 하나씩** 묻는다. 가능하면 추천답을 제시해 "yes"로 수락할 수 있게 한다.
- 답이 불확실한 항목은 **informed guess로 우선 채우고**, 프로젝트 방향을 좌우하는 항목만 본문에 `[NEEDS CLARIFICATION: 질문]` 마커를 남긴다 — **전체 상한 5개.** 해소되지 않은 마커는 gap report에 노출한다.
- **미확정 검색 오염 방지:** 잔존 마커가 1개 이상인 문서는 frontmatter `status: unverified`로 둔다(새 status 값을 만들지 않는다). `wiki-query`가 인용 시 "(미확정: 가정 포함)"으로 표시해 가정이 사실처럼 회수되지 않게 한다.

**질문 체크리스트:**

```
overview:  목적 한 문장? 이해관계자? 성공을 측정할 KPI? 현재 상황?
context:   왜 지금 하는가? 제약(예산·기한·기술·인력)? 외부 의존성? 실패 시나리오?
goals:     마일스톤? 측정 가능한 성공 기준? 비목표(명시적으로 안 하는 것)?
```

## 워크플로

```
Step 0:   Config Gate
Step 0.5: hot.md 읽기 — 관련 논의 스레드 확인

Step 1: 프로젝트명 확인 (slug 규칙) → {vault}/wiki/projects/{name}/ 존재 검사
  이미 있으면 → 재프레이밍 모드: 기존 파일을 읽고 인터뷰로 갱신한다.
    기존 본문은 보존·통합한다 (덮어쓰기 금지).
    의미 변경 라우팅 —
      목적·KPI·제약 변경        → decisions.md 짝 (wiki-project-record 안내)
      아키텍처·기술 선택 변경    → wiki-project-design 안내

Step 2: 인터뷰 — 위 체크리스트, 한 번에 하나씩, 마커 상한 5

Step 3: wiki-query 근거 수집 (공통 원칙 2)
  대상: context의 의존성, overview 배경의 기술 주장
  매치 있으면 (출처: [[페이지]]), 없으면 ⚠️ unverified + missing knowledge 기록

Step 4: overview.md + context.md 생성 (goals.md는 목표 논의가 있었던 경우만)
  frontmatter category: projects. 관련 concepts·entities 를 [[wiki-link]]로 연결

Step 5: 자가검증 체크리스트 루프 (최대 2회)
Step 6: gap report 출력 (단계 미진입 / 진짜 갭 / missing knowledge)
Step 7: 공통 종료 시퀀스 — index → log → hot → QMD refresh
  [YYYY-MM-DD] PROJECT-INIT name="{name}" files=[...] markers=N
```

## 품질 체크

```
□ overview 에 목적 1문장 + KPI 존재
□ goals 작성 시 비목표 섹션 존재
□ [NEEDS CLARIFICATION] ≤ 5개, gap report에 노출, 잔존 시 status: unverified
□ 기술 주장에 (출처: [[...]]) 또는 ⚠️ unverified
□ [[wiki-link]] — 검색 매치가 있을 때 최소 2개, 없으면 gap report에 missing knowledge (억지 링크 금지)
□ 재프레이밍 시 기존 본문 보존 + 의미 변경은 record·design으로 라우팅
□ index.md 등록 · log.md 기록 · hot.md 갱신 · QMD refresh + 상태 문자열
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 체크리스트 질문을 한 번에 다 던진다 | 답이 뭉개지고 추천답으로 수락할 여지가 사라진다 | 한 번에 하나씩, 가능하면 추천답과 함께 |
| 모르는 항목마다 `[NEEDS CLARIFICATION]`을 남긴다 | 마커가 문서를 덮어 무엇이 중요한지 사라진다 | 방향을 좌우하는 항목만, 상한 5개. 나머지는 informed guess |
| 마커가 남았는데 `status: verified`로 둔다 | 가정이 검색에서 사실처럼 회수된다 | `status: unverified` |
| 재프레이밍에서 기존 overview를 새로 쓴다 | 이전 판단 기록이 사라진다 | 기존 본문을 보존·통합 (덮어쓰기 금지) |
| 근거가 없는데 그럴듯한 페이지를 링크한다 | 링크 그래프가 거짓 근거를 만든다 | 매치가 없으면 gap report에 missing knowledge |
| 인터뷰에서 나온 아키텍처 결정을 `architecture.md`에 적는다 | 소유권과 proposal 경유가 무너진다 | `wiki-project-design` 안내 |
| `goals.md`에 목표만 적는다 | 범위가 무한정 확장되고 "안 하는 것"이 합의되지 않는다 | 비목표 섹션 필수 |
