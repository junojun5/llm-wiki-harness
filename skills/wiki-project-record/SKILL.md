---
name: wiki-project-record
description: 프로젝트 이벤트를 기록할 때 사용 — 결정, 트러블슈팅 사례, 미팅 요약, 백로그 항목 — projects/{name}/에. "record this decision", "log this issue", "백로그에 추가", 문제 해결 후, "/wiki-project-record".
---

# wiki-project-record

프로젝트 이벤트를 올바른 파일로 라우팅하여 기록한다. 먼저 Config Gate. 단순 로거가 아니라 **라우팅 싱크(routing sink)** — 관통하는 특성은 *route-then-record*이며; 불변성은 파일마다 다르다.

## 라우팅 표 (자동 판단; 불확실하면 묻기)
- **결정이 내려짐:**
  - **design 문서를 바꿈** (architecture/domain/conventions) → **wiki-project-design**에 넘김 (proposal → merge → decisions.md 짝을 소유).
  - design과 무관 (벤더, 일정, 예산) → **decisions.md append (직접).**
- **TODO / 잠재 위험** → `backlog.md` (`## TODO` / `## 위험`, 출처 포함).
- **문제 해결됨** → `troubleshooting/{case}.md` (`status: resolved` — 증상/원인/해결/재발 방지).
- **디버깅, 미해결** → `troubleshooting/{case}.md` (`status: open` — 증상/가설/실험, 점진적으로 갱신).
- **실시간 미팅 (raw transcript 없음)** → `meetings/YYYY-MM-DD-{slug}.md`. (Raw transcript → wiki-ingest → `summaries/meetings/`, §4-2.)
- **일반화 가능한 지식** → **wiki-knowledge** 승격 제안 (projects/에 쓰지 말 것).
- **design 문서 변경이지만 결정 형태는 아님** (용어/규칙/구조 정리) → wiki-project-design.
- **불확실** → 묻는다.

## 승인 — 결정은 사용자의 것
**절대 자동 append 금지.** 초안(결정 / 이유 / 대안)을 제시하고 먼저 확인받는다. 논의가 수렴하면 "결정으로 기록할까요?"라고 *제안*할 수 있으나, 도장은 사용자가 찍는다.

## 불변성 (파일마다 다름)
- **decisions.md / meetings/** — 완전 불변 (append 또는 새 파일만). decisions.md 항목 (frontmatter 없음 — class-③ 원장):
  ```
  ## [YYYY-MM-DD] {제목}
  - 결정: …
  - 이유: … ((출처: [[knowledge]]) 인용 가능)
  - 대안 및 제외 이유: …
  - 변경 기록: [[changes/archive/YYYY-MM-DD-{slug}]]   ← design 경유 시만
  ```
  결정을 뒤집으려면: 옛 항목을 참조하는 **새** 항목을 append — 기존 항목을 절대 편집하지 않는다.
- **troubleshooting/{case}.md** — `open` (가변: 증상/가설/실험) → `resolved` (불변: 원인/해결/재발 방지 채움). 재발 → `## Follow-up — [[new case]]` 링크만 append; 본문은 건드리지 않음. frontmatter (class-② 문서):
  ```
  ---
  title: "{사건 한 줄 제목}"
  category: projects
  status: open | resolved
  created: YYYY-MM-DD
  updated: YYYY-MM-DD
  summary: "≤400자 — 증상·해결 요약"
  ---
  ## 증상                      ← open부터 작성
  ## 가설 / 실험                ← open 동안 점진 갱신
  ## 원인 / 해결 / 재발 방지      ← resolved 시 채움, 이후 불변
  ## Follow-up                 ← 재발 시 [[새 케이스]] 링크만 append (본문 무수정)
  ```
- **backlog.md** — 살아있음 (체크박스 토글, 위험 상태 갱신). 유일하게 가변인 출력. frontmatter 없음 (class-③ 원장):
  ```
  ## TODO
  - [ ] {할 일} (출처: 코드 분석 | [[페이지]] | 논의) — {한 줄 맥락}
  - [x] {완료 항목}

  ## 위험
  - {위험 한 줄} — 영향: {무엇} / 완화: {방안 또는 "미정"} / 상태: open|mitigated|accepted
  ```

## 워크플로우
0. Config Gate. 0.5 hot.md. 1. 라우팅 (위 표). 2. 대화로부터 초안 작성, 파일 포맷을 따름 → **사용자와 확인**. 3. 사례 파일 append / 생성 (첫 기록 시 생성). 4. 관련 `[[knowledge/concepts/design]]` 링크. 5. 간단한 gap 리포트 (미기록 결정 후보 플래그). 6. 종료 시퀀스. log: `[YYYY-MM-DD] PROJECT-RECORD name="…" type=decision|troubleshooting|meeting|backlog target="…"`.

## 품질 체크
append 전에 승인 획득 · 기존 항목 미변경 (decisions / resolved troubleshooting / meetings는 append-only; backlog + open troubleshooting이 가변 예외) · 결정 이유에 출처 또는 `⚠️ unverified` · resolved 사례에 4개 섹션 모두 · 백로그 항목에 출처 · index/log/hot/QMD 갱신됨.
