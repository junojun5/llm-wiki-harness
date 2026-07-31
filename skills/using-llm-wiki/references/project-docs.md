# projects/ 공통 — wiki-project 스킬군의 공유 규칙

`wiki-project-init` · `wiki-project-design` · `wiki-project-record` 세 스킬이 공유하는 컨셉·원칙·구조·형식의 단일 출처. 세 스킬 중 하나를 실행할 때 이 파일을 읽는다.

## 컨셉 — 볼트의 종착점

볼트 문서들은 프로젝트 설계에 반영하기 위한 **데이터**이고, `projects/`는 그 데이터로 프로젝트 스펙을 완성하는 곳이다.

```
raw → summaries → knowledge ──→ projects/{name}/   (증류 체인의 최종 소비자)
            concepts ─────────↗
```

따라서 이 스킬군은 받아쓰기가 아니라 **"대화에서 의도를 끌어내고(인터뷰), 볼트에서 근거를 끌어와(retrieval), 프로젝트 문서로 합성하는(synthesis)"** 스킬군이다.

**관리 대상 = 논리적 콘텐츠.** `projects/`가 담는 것은 코드 구조 덤프가 아니라 프로젝트의 논리적 내용이다 — 도메인 규칙·비즈니스 로직(domain.md), 결정된 사항(decisions.md), 변경된 사항(changes/), 할 일·위험(backlog.md), 설계 구조(architecture.md). **코드는 규칙을 설명하는 간단한 예시로만 등장한다.**

**코드베이스를 직접 읽어 역추출하지 않는다.** 설계문서 없는 기존 프로젝트를 문서화하는 경우, 코드 분석은 상류 개발 세션에서 일어나고 스킬은 **대화 컨텍스트에 든 분석 결과**를 재료로 합성한다.

## 공통 원칙 — 3스킬 모두 적용

1. **자동성 3계층.** 발동은 사용자 호출·에이전트 제안이 하고, "어느 파일에 속하나" **라우팅은 스킬이 자동 판단**하며, 쓰기 승인은 영향도에 따라 차등이다. 분류에 확신이 없으면 사용자에게 묻는다.
2. **knowledge 참조 정책 — 검색은 항상, 인용은 매치 시만.** 사실 기반 기술 주장을 쓸 때 `wiki-query`로 `knowledge/`·`summaries/`를 검색한다. 매치가 있으면 `(출처: [[페이지]])`로 인용하고, 없으면 `⚠️ unverified` 또는 `(출처: conversation)` + gap report에 `missing knowledge: {주제}`를 기록한다. **knowledge는 스펙의 전제조건이 아니라 품질 증폭기다** — 강제 인용은 금지(cold start·억지 인용 방지).
3. **스냅샷-기록 짝 원칙.** 스냅샷 문서에서 기존 내용을 뒤집는 **의미 변경**을 발견하면 반드시 change proposal(design) 또는 `decisions.md` 항목(record)을 짝으로 만든다. 스냅샷만 바뀌고 "왜"가 기록되지 않는 상태를 금지한다.
4. **knowledge 승격 밸브.** 프로젝트 논의에서 일반화 가능한(프로젝트 무관) 지식이 나오면 `projects/`에 쓰지 않고 `wiki-knowledge` 승격을 제안한다. `domain.md`는 프로젝트 고유 용어·규칙만 담고 일반 개념은 본문 복제 없이 `[[knowledge]]` 링크로 둔다.
5. **gap report — 모든 세션 종료 시 출력.** 세 종류를 구분한다: ① 단계 미진입("goals.md 없음 — 기획 단계 미도달", 정상) ② 진짜 갭("goals.md 있는데 성공 기준 섹션이 비어 있음") ③ missing knowledge 목록(다음 ingest 의제).
6. **필요한 파일만.** 처음부터 전체 파일을 만들지 않는다 (생성 트리거는 아래 생애주기 표).
7. **자가검증 체크리스트 루프.** 문서 작성 후 템플릿 요구사항에서 체크리스트를 생성해 스스로 검증하고 실패 항목을 수정한다 — **최대 2회 반복**, 잔여 항목은 보고한다.
8. **공통 종료 시퀀스.** 문서(페이지) 쓰기 → index.md → log.md → hot.md → QMD refresh (`using-llm-wiki`). **원본 먼저, 파생물 나중** — 역순이면 "기록은 있는데 문서가 없는" 거짓 기록이 남는다.
9. **재진입 — 파일 상태로 이어받는다.** design·record는 한 대화 턴에 안 끝날 수 있다. 별도 모드 플래그를 두지 않고 파일 상태로 재개한다 — change proposal `status: proposed` 존재 = 초안 완료(승인 대기), 승인 시 apply. 재실행 시 완료분은 스킵하고 미완분만 진행하므로 proposed 적체·승인 전 병합이 구조적으로 방지된다.

## 디렉토리 구조

```
wiki/projects/{프로젝트명}/
  overview.md / goals.md / context.md          ← init 소유 (스냅샷)
  architecture.md / domain.md / conventions.md ← design 소유 (진화)
  decisions.md                                 ← record 소유 (append-only)
  backlog.md                                   ← record 소유 (living: TODO·위험)
  troubleshooting/{case}.md                    ← record 소유 (open=점진 / resolved=불변)
  meetings/YYYY-MM-DD-{slug}.md                ← record 소유 (불변)
  changes/                                     ← design의 변경 제안 작업 공간
    YYYY-MM-DD-{slug}.md                       ←   status: proposed (진행 중)
    archive/YYYY-MM-DD-{slug}.md               ←   status: applied|rejected (불변 박제)
```

**프로젝트 canonical 식별자 = 디렉토리명** (kebab-case). wikilink·QMD 경로·log의 `name=`이 모두 이 값을 기준으로 한다 — 별도 `project_id`/`slug`/`aliases` frontmatter는 두지 않는다.

## 파일 생성 생애주기

```
init ──────────→ 기획 develop ──→ 설계 develop ──→ 실행 단계
overview.md      goals.md         architecture.md   conventions.md (코드 시작 시)
context.md                        domain.md         decisions.md (첫 결정부터)
                                                    troubleshooting/ (첫 사건부터)
                                                    meetings/ (첫 미팅부터)
```

| 파일 | 생성 트리거 | 갱신 방식 |
|---|---|---|
| overview.md | init 실행 시 항상 (유일한 무조건 생성) | 통합 갱신. 현황 섹션만 자주 |
| context.md | init 실행 시 overview와 함께 | 통합 갱신. 제약 변경은 change·decision 짝 |
| goals.md | 목표 논의 세션 ("목표 잡자") | 통합 갱신. **비목표 섹션 필수** |
| architecture.md | 설계 세션 ("아키텍처 잡자") | change proposal 경유 (의미 변경 시) |
| domain.md | 용어·도메인 규칙이 3개 이상 누적될 때 생성 제안 | 통합 갱신. 커지면 `domain/` BC별 분할 |
| conventions.md | 코드 시작 시점, 사용자 명시 요청만 | change proposal 경유 |
| changes/ | 설계 의미 변경 시 (design이 생성) | proposal 1건당 1파일. proposed → applied\|rejected 후 archive/ 이동(불변) |
| decisions.md | 첫 결정이 내려질 때 | append-only |
| backlog.md | 분석·논의 중 TODO·위험 발견 시 | living (체크박스 토글·위험 상태 갱신) |
| troubleshooting/ | 문제 해결 직후 "기록해줘" | 케이스당 1파일. open=점진 / resolved=불변. 재발 시 새 케이스 + Follow-up 링크 |
| meetings/ | 라이브 프로젝트 미팅 시 (raw 트랜스크립트는 `summaries/meetings/` 미러) | 미팅당 1파일, 불변 |

## 접근 권한 매트릭스

**W**=직접 생성·수정(소유) · **W\***=조건부 직접 쓰기 · **△**=직접 쓰기 금지(proposal 경유 또는 타 스킬 안내) · **R**=읽기 · **—**=해당 없음

| 스킬 | overview·context·goals | architecture·domain·conventions | changes/ | decisions.md | backlog.md | troubleshooting·meetings |
|---|---|---|---|---|---|---|
| `wiki-project-init` | **W** | R · △¹ | — | △→record² | — | — |
| `wiki-project-design` | R | **W**³ | **W** | **W\***⁴ | R | R |
| `wiki-project-record` | R | R · △¹ | R | **W** | **W** | **W** |

- ¹ 경계 기준은 **"설계 문서 본문을 바꾸는가?"** — 예면 `wiki-project-design`을 안내한다.
- ² init 재프레이밍의 목적·KPI·제약 변경은 `wiki-project-record`(decisions.md)를 안내한다.
- ³ 표면 변경은 직접 W, **의미 변경은 `changes/` proposal 경유 후 병합.**
- ⁴ applied proposal의 **짝 항목만** 아래 형식으로 직접 append한다 (위임 호출 없음).

**교차 스킬:** `wiki-query`는 전 문서 R(`changes/` proposed는 `tier: peripheral` 강등 + 인용 시 "(proposed — 미확정 설계)" 표시) · `wiki-lint`는 전 문서 R + `--fix`로 frontmatter 필드 추가·relationship type 오타 폴백·`index.md` 등록을 수리하고(본문 의미는 무수정) **비가역 raw 삭제도 개별 확인 후 수행**한다 · `wiki-ingest`는 `projects/`에 직접 쓰지 않는다.

## 원장·라이프사이클 문서 형식

`decisions.md`·`backlog.md`는 문서 클래스 ③(원장)이라 frontmatter가 없다. 소유자는 `wiki-project-record`이고, `decisions.md`만 design이 조건부로 함께 쓴다.

**decisions.md 항목** (append-only):

```markdown
## [YYYY-MM-DD] {제목}
- 결정: ...
- 이유: ... (출처: [[knowledge-페이지]] 인용 가능)
- 대안 및 제외 이유: ...
- 변경 기록: [[changes/archive/YYYY-MM-DD-{slug}]]   ← design 경유 시만
```

`변경 기록:` 필드 유무가 두 출처(design 경유 / record 직행)를 구분한다. proposal 링크는 처음부터 **최종 archive 경로**로 쓴다 — `changes/` → `archive/` 이동 후 깨지지 않게.

**backlog.md** (living — 체크박스·상태 갱신 허용):

```markdown
## TODO
- [ ] {할 일} (출처: 코드 분석 | [[페이지]] | 논의) — {한 줄 맥락}
- [x] {완료 항목}

## 위험
- {위험 한 줄} — 영향: {무엇} / 완화: {방안 또는 "미정"} / 상태: open|mitigated|accepted
```

**troubleshooting/{case}.md** (문서 클래스 ② 축소셋):

```markdown
---
title: "{사건 한 줄 제목}"
category: projects
status: open | resolved
created: YYYY-MM-DD
updated: YYYY-MM-DD
summary: "≤400자 — 증상·해결 요약"
---
## 증상                    ← open부터 작성
## 가설 / 실험              ← open 동안 점진 갱신
## 원인 / 해결 / 재발 방지    ← resolved 시 채움, 이후 불변
## Follow-up               ← 재발 시 [[새 케이스]] 링크만 append (본문 무수정)
```
