---
name: wiki-project-record
description: 프로젝트의 사건이나 작업 항목을 기록할 때 사용한다 — 결정, 트러블슈팅 케이스, 미팅 요약, 할 일·위험. decisions.md(append-only)·troubleshooting·meetings·living backlog.md로 라우팅하며 불변 과거 항목은 절대 재작성하지 않는다. 사용자가 "이거 결정으로 기록"·"트러블슈팅 남겨줘"·"백로그에 추가"라고 하거나 문제를 해결한 직후에 사용한다.
---

# wiki-project-record

프로젝트 **기록·작업 sink**다. 대화에서 나온 기록거리를 올바른 파일로 라우팅해 기록한다. 통합 형질은 불변성이 아니라 **"라우팅 후 기록"**이고, 불변성은 파일별로 차등이다.

시작 전 두 가지를 로드한다:
- `using-llm-wiki` — Config Gate, 종료 시퀀스, QMD refresh, 페이지 포맷
- `using-llm-wiki` 의 `references/project-docs.md` — 컨셉·공통 원칙 10개·디렉토리 구조·생애주기·접근 권한 매트릭스 + **decisions.md·backlog.md·troubleshooting 형식**(이 스킬이 형식 소유자다)

## 라우팅 테이블 — 자동 판단, 확신 없으면 질문

```
├─ 결정이 내려졌다 ("X로 가기로 했다")
│    ├─ 설계 문서(architecture/domain/conventions) 본문 변경 동반
│    │                                    → wiki-project-design 안내
│    │                                      (design이 proposal→병합→decisions 짝까지 처리)
│    └─ 설계 본문 무관 (외주사·일정·예산 등 운영 결정)
│                                         → decisions.md append (직행)
├─ 할 일·잠재 위험을 발견했다              → backlog.md (## TODO / ## 위험, 출처 명시)
├─ 문제를 겪고 해결했다                    → troubleshooting/{case}.md (status: resolved)
├─ 문제를 디버깅 중이다 (미해결)           → troubleshooting/{case}.md (status: open)
├─ 미팅 내용이다 (라이브·raw 없음)         → meetings/YYYY-MM-DD-{slug}.md
│                                           (raw 트랜스크립트는 wiki-ingest → summaries/meetings/)
├─ 일반화 가능한 지식이다                  → wiki-knowledge 승격 제안 (projects에 쓰지 않는다)
├─ 설계 본문 변경인데 결정 형태가 아님
│    (용어·규칙·구조 정리)                 → wiki-project-design 안내
└─ 확신 없음                              → 사용자에게 질문
```

**경계 판단의 단일 기준: "이 결정이 설계 문서 본문을 바꾸는가?"** 예 → design, 아니오 → record.

## decisions.md 공동 쓰기 — 형식은 record, 쓰기는 두 스킬

`decisions.md`는 이 스킬이 **소유**하지만(형식·append 규칙의 단일 출처), 쓰기는 둘이 공유한다. 설계 본문 변경을 동반하는 결정은 `wiki-project-design`이 끝까지 처리하고(병합 시 직접 append), **설계 본문 무관 결정만** record가 직행 append한다. 한 파일에 두 출처가 섞이지만 `변경 기록: [[changes/archive/...]]` 필드 유무로 구분된다.

## 승인 규칙 — 결정은 사용자의 것

- append 전 반드시 **결정·이유·대안 초안을 제시하고 확인받는다. 자동 append 금지.**
- 논의가 수렴했다고 판단되면 "결정으로 기록할까요?"를 제안할 수 있으나, 도장은 사용자가 찍는다.
- **기존 항목 수정 절대 금지** — 뒤집을 때는 새 항목을 append하고 이전 항목을 참조한다. (본문 항목이 불변이라는 뜻이고, frontmatter `updated`·`summary` 같은 메타데이터 갱신은 정상이다.)

## 불변성 예외 — 파일별 차등

| 파일 | 불변성 |
|---|---|
| `decisions.md` · `meetings/` | 완전 불변 (append·신규만) |
| `troubleshooting/{case}.md` | `status: open` 동안 증상·가설·실험 점진 갱신 허용 → `status: resolved` 이후 불변. 재발 시 기존 본문 무수정, 말미에 `## Follow-up — [[새 케이스]]` 링크만 append. 완전 정정은 새 케이스 |
| `backlog.md` | living — TODO 체크박스 토글·위험 상태 갱신 허용. 이 스킬의 유일한 가변 산출물 |

## 워크플로

```
Step 0:   Config Gate
Step 0.5: hot.md 읽기

Step 1: 라우팅 테이블로 대상 판별 (확신 없으면 질문)
Step 2: 초안 작성 (대화에서 추출, project-docs.md 형식 준수) → 사용자 확인
Step 3: append / 신규 케이스 파일 생성 (해당 파일 첫 기록이면 파일 생성)
Step 4: 관련 [[wiki-link]] 연결 (관련 knowledge·concepts·설계 문서)
Step 5: gap report (간략 — 미기록 결정 후보가 있으면 알린다)
Step 6: 공통 종료 시퀀스 — index → log → hot → QMD refresh
  [YYYY-MM-DD] PROJECT-RECORD name="{name}" type=decision|troubleshooting|meeting|backlog target="{경로}"
```

## 품질 체크

```
□ append 전 사용자 확인 완료 (자동 append 없음)
□ 기존 항목 본문 무수정 — decisions·resolved troubleshooting·meetings의 diff가 append뿐
  (backlog · open troubleshooting 은 가변 예외)
□ decisions 이유에 출처 인용 또는 ⚠️ unverified
□ troubleshooting: resolved 는 4섹션(증상/원인/해결/재발 방지) 완비, open 은 증상/가설/실험
□ backlog 항목에 출처(코드 분석·논의) 명시
□ 설계 본문 변경 동반 결정은 wiki-project-design 으로 라우팅 (직접 쓰지 않음)
□ index.md 등록 · log.md 기록 · hot.md 갱신 · QMD refresh + 상태 문자열
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 논의가 수렴했으니 `decisions.md`에 바로 append한다 | 사용자가 찍지 않은 도장이 결정으로 굳는다 | 초안(결정·이유·대안)을 제시하고 확인받는다 |
| 틀린 과거 항목을 고쳐 쓴다 | 원장이 사후 편집돼 이력의 의미가 사라진다 | 새 항목 append + 이전 항목 참조 |
| 설계 변경을 동반한 결정을 직행 append한다 | proposal·delta 없이 설계가 바뀐다 | `wiki-project-design` 안내 |
| 재발한 문제를 resolved 케이스에 이어 쓴다 | 해결 시점의 기록이 훼손된다 | 새 케이스 + `## Follow-up` 링크만 append |
| 일반화 가능한 지식을 `projects/`에 기록한다 | 프로젝트마다 같은 지식이 복제된다 | `wiki-knowledge` 승격 제안 |
| 라우팅이 애매한데 그럴듯한 파일에 넣는다 | 불변성 등급이 다른 파일에 기록이 섞인다 | 사용자에게 질문한다 |
| backlog 항목을 출처 없이 적는다 | 나중에 왜 필요한 일인지 복원할 수 없다 | `(출처: 코드 분석 \| [[페이지]] \| 논의)` 명시 |
