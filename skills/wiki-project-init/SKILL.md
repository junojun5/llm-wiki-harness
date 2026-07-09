---
name: wiki-project-init
description: wiki에서 프로젝트를 시작하거나 (재)정의할 때 사용 — "start a project", "plan project X", "프로젝트 기획하자", "프로젝트 문서 세팅", "/wiki-project-init". projects/{name}/ overview, context, goals를 생성한다.
---

# wiki-project-init

가이드 인터뷰를 통해 `projects/{name}/` 스냅샷 문서(overview, context, goals)를 생성/재정의한다. 먼저 Config Gate. **overview/context/goals만 소유** — design 문서는 wiki-project-design, decisions/logs는 wiki-project-record.

## 인터뷰 패턴 (spec-kit)
파일별 체크리스트를 **한 번에 한 질문씩** 묻고, 추천 답변을 제시한다("yes"로 수용 가능). 불확실한 항목: **정보에 근거한 추측으로 채우고**, 프로젝트를 좌우하는 미지수에 대해서만 본문에 `[NEEDS CLARIFICATION: 질문]` 마커를 추가한다 — **총 최대 5개.** 잔여 마커가 ≥1개인 문서는 frontmatter `status: unverified`를 받는다 (그래서 wiki-query가 "(미확정: 가정 포함)"으로 플래그); 미해결 마커는 gap 리포트에 드러난다.
- **overview:** 목적 한 문장? 이해관계자? 성공 KPI? 현재 상황?
- **context:** 왜 지금 하는가? 제약(예산·기한·기술·인력)? 외부 의존성? 실패 시나리오?
- **goals:** 마일스톤? 측정 가능한 성공 기준? **비목표(non-goals) — 명시적으로 안 하는 것 (필수 섹션).**

## 워크플로우
0. Config Gate. 0.5 hot.md 읽기 (관련 스레드).
1. 이름 확인 (slug §2) → `projects/{name}/`가 존재하는지 확인. 존재 → **reframe 모드**: 기존 것 읽기, 인터뷰로 갱신, **기존 콘텐츠 보존 & 통합(절대 덮어쓰지 않음)**. reframe 시 의미 변경 라우팅: 목적/KPI/제약 변경 → decisions.md 짝(wiki-project-record); architecture/기술선택 변경 → wiki-project-design.
2. 인터뷰 (체크리스트, 한 번에 하나씩; 마커 ≤5개).
3. 증거를 위한 wiki-query (공통 원칙: 항상 검색, 매치될 때만 인용; 아니면 `⚠️ unverified` + gap 리포트에 "missing knowledge: {topic}" 기록 — 억지 인용 없음).
4. `overview.md` + `context.md` 생성 (`goals.md`는 goals가 논의된 경우만). `category: projects`; 관련 concepts/entities 링크.
5. 자기 검증 체크리스트 루프 (≤2회 반복, 그다음 잔여 보고).
6. **Gap 리포트** (3종): ① stage-not-entered ("goals.md 없음 — 기획 단계 미도달", 정상) ② 실제 갭 ("성공 기준 섹션 비어 있음") ③ missing knowledge 목록.
7. 종료 시퀀스 — index → log → hot → QMD. log: `[YYYY-MM-DD] PROJECT-INIT name="…" files=[…] markers=N`.

## 경계 — 이것들은 쓰지 않는다
architecture/domain/conventions → wiki-project-design (제안). decisions.md → wiki-project-record. **콘텐츠가 있는 파일만** 생성 — 아홉 개를 처음부터 다 만들지 않는다.

## 품질 체크
overview에 1줄 목적 + KPI · goals(작성됐다면)에 non-goals 섹션 · `[NEEDS CLARIFICATION]` ≤5개, gap 리포트에 노출 · 기술 주장에 출처 또는 `⚠️ unverified` · 매치가 있을 때 `[[links]]` ≥2개 · index/log/hot/QMD 갱신됨.
