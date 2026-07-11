---
name: wiki-project-init
description: 프로젝트를 시작·(재)정의할 때 사용 — "프로젝트 시작", "새 프로젝트 정리", "/wiki-project-init"
---

# wiki-project-init

## 개요
가이드 인터뷰로 `projects/{name}/`의 스냅샷 문서 — `overview.md` / `context.md` / `goals.md` — 를 생성하거나 재정의한다. 이 세 파일만 소유(W)한다. `architecture.md`/`domain.md`/`conventions.md`는 `wiki-project-design`, `decisions.md`/`backlog.md`/`troubleshooting/`/`meetings/`는 `wiki-project-record` 소관이다.

## 언제 사용
- **트리거:** "프로젝트 시작", "새 프로젝트 정리", "프로젝트 기획하자", "X 프로젝트 시작", "프로젝트 문서 세팅", `/wiki-project-init`.
- **경계:** 상세는 아래 `## 경계` 참조. 짧게: overview/context/goals만 쓴다(W). design 문서는 읽기만(R)하고 의미 변경은 `wiki-project-design`으로 안내(△). 결정 기록이 필요하면 `wiki-project-record`로 안내.

## 인터뷰 패턴
spec-kit `[NEEDS CLARIFICATION]` 패턴을 채택한다.
- 파일별 필수 질문 체크리스트(아래)를 **한 번에 하나씩** 묻는다. 가능하면 추천 답을 제시해 "yes"로 바로 수락할 수 있게 한다.
- 답이 불확실한 항목은 **informed guess로 우선 채운다.** 프로젝트 방향을 좌우하는 미지수에 대해서만 본문에 `[NEEDS CLARIFICATION: 질문]` 마커를 남긴다 — **전체 상한 5개.**
- **미확정 검색 오염 방지:** 세션 종료 시 잔존 마커가 ≥1개인 문서는 frontmatter `status: unverified`를 받는다(신규 status 값 도입 아님 — 기존 값 재사용). 이렇게 하면 `wiki-query`가 인용 시 "(미확정: 가정 포함)"으로 표시해 가정이 사실처럼 회수되지 않는다. 해소되지 않은 마커는 gap report에도 드러난다.

체크리스트:
- **overview:** 목적 한 문장? 이해관계자? 성공을 측정할 KPI? 현재 상황?
- **context:** 왜 지금 하는가? 제약(예산·기한·기술·인력)? 외부 의존성? 실패 시나리오?
- **goals:** 마일스톤? 측정 가능한 성공 기준? **비목표(non-goals) — 명시적으로 안 하는 것.**

## 워크플로우
0. **Config Gate** (AGENTS.md / CLAUDE.md Step 0).
0.5. `hot.md` 읽기 — 관련 논의 스레드 확인.
1. 프로젝트명 확인(slug 규칙 §2) → `wiki/projects/{name}/` 존재 검사.
   - **존재하지 않음** → 신규 생성 경로, Step 2로.
   - **존재함 → 재프레이밍 모드.** 기존 파일을 읽고 인터뷰로 갱신한다. **기존 콘텐츠를 보존·통합한다 — 절대 덮어쓰지 않는다.**
     - **의미 변경 라우팅:** 목적·KPI·제약이 바뀌면 → `decisions.md` 짝 항목을 위해 `wiki-project-record`로 안내. 아키텍처·기술 선택이 바뀌면 → `wiki-project-design`으로 안내.
2. 인터뷰 진행 — 위 체크리스트를 한 번에 하나씩, 마커 상한 5개.
3. 증거 수집을 위한 `wiki-query` 실행(공통 원칙: 항상 검색하고 매치될 때만 인용). 매치 있으면 `(출처: [[페이지]])` 인용, 없으면 `⚠️ unverified` + gap report에 `missing knowledge: {주제}` 기록 — 억지 인용 금지. 대상은 context의 외부 의존성·overview 배경 등 사실 기반 기술 주장.
4. `overview.md` + `context.md` 생성(`goals.md`는 목표 논의가 있었던 경우만). frontmatter `category: projects`. 관련 concepts/entities를 `[[wiki-link]]`로 연결.
   - **goals.md를 쓴다면 비목표(non-goals) 섹션은 필수다.**
5. 자기 검증 체크리스트 루프(공통 원칙 7) — 아래 `## 품질 체크` 기준으로 최대 2회 반복, 그 이후 잔여 항목은 보고만 한다.
6. **Gap report 출력** — 세 종류를 구분한다:
   1. 단계 미진입 (예: "goals.md 없음 — 기획 단계 미도달", 정상 상태)
   2. 실제 갭 (예: "goals.md 있는데 성공 기준 섹션 비어 있음")
   3. missing knowledge 목록 (다음 ingest 의제)
7. 종료 시퀀스 — index → log → hot → QMD refresh(§3-5).
   log: `[YYYY-MM-DD] PROJECT-INIT name="{name}" files=[…] markers=N`

## 경계
- **W (소유·직접 쓰기):** `overview.md` / `context.md` / `goals.md`.
- **R · △ (읽기만, 직접 쓰기 금지):** `architecture.md` / `domain.md` / `conventions.md`. 경계 기준은 **"설계 문서 본문을 바꾸는가?"** — 예면 `wiki-project-design`으로 안내한다.
- **△→record:** 재프레이밍 중 목적·KPI·제약이 바뀌면 직접 기록하지 않고 `wiki-project-record`(`decisions.md`)로 안내한다.
- **해당 없음:** `changes/` / `backlog.md` / `troubleshooting/` / `meetings/` — 이 스킬은 건드리지 않는다.
- **필요한 파일만 생성** — 처음부터 아홉 개 파일을 다 만들지 않는다. `overview.md`만 항상 생성(유일한 무조건 생성), `context.md`는 init 시 함께, `goals.md`는 목표 논의가 있을 때만.

## 품질 체크
- overview에 목적 1문장 + KPI 존재.
- goals를 작성했다면 비목표(non-goals) 섹션 존재.
- `[NEEDS CLARIFICATION]` ≤ 5개, 잔존 시 gap report에 노출.
- 기술 주장에 `(출처: [[...]])` 또는 `⚠️ unverified`.
- `[[wiki-link]]` — 검색 매치가 있을 때 최소 2개, 없으면 억지로 걸지 않고 gap report에 missing knowledge 기록.
- index.md 등록, log.md 기록, hot.md 갱신, QMD refresh(§3-5) 완료.
