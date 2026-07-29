---
name: wiki-capture
description: 현재 대화의 지식을 wiki에 보존하려 할 때 사용한다. 항상 summaries/sessions에 먼저 저장하고, knowledge·concepts·entities·projects 승격은 사용자가 명시적으로 요청할 때만 한다. 트리거는 "이거 wiki에 저장해줘"·"capture this"·"wiki에 기록해줘".
---

# wiki-capture

현재 대화에서 보존 가치 있는 지식을 골라 `summaries/sessions/`에 캡처한다.

시작 전 `using-llm-wiki` 스킬을 로드한다 — Config Gate, 불변 규칙, 종료 시퀀스, QMD refresh, 페이지 포맷(`references/page-format.md` — 특히 provenance 산정).

**입력은 현재 대화 컨텍스트 자체다.** 스킬 실행 주체가 대화를 컨텍스트 윈도우에 들고 있는 LLM 자신이므로 트랜스크립트 API·파일 경유 같은 별도 획득 파이프라인이 필요 없다.

> ⚠️ 컨텍스트 압축 한계: 긴 세션의 초반부는 압축 후 요약본만 남는다. **캡처는 빠를수록 충실하며**, 압축 이후에 캡처할 때는 초반부가 요약 수준으로만 저장됨을 사용자에게 고지한다.

**캡처 범위:** 기본은 현재 세션 전체에서 Step 1 필터로 **선별**한다(전체 저장이 아니다). 사용자가 자연어로 범위를 지정하면("방금 논의한 X만") 그 부분만 — 별도 플래그 문법은 두지 않는다.

## 2단계 파이프라인

```
대화 세션 → summaries/sessions/        ← 이 스킬의 기본 동작
                  ↓ 사용자 명시 요청 시만
         knowledge/ | concepts/ | entities/ | projects/
```

`raw/ → summaries → knowledge` 파이프라인과 같은 원칙이다 — 캡처 시점에 선언적 재작성을 강제하지 않는다. **승격은 이 스킬의 일이 아니다** (`wiki-knowledge` 또는 `wiki-project-*`).

## 워크플로

```
Step 0:   Config Gate
Step 0.5: wiki/hot.md 읽기 (있으면) — 유사 내용이 이미 캡처됐는지 확인

Step 1: 보존 가치 있는 지식 식별
  ✅ 저장: 결정과 이유, 기술적 발견, 분석·프레임워크, 핵심 사실
  ❌ 스킵: 탐색 중 잡담, 미결론 논의, 일회성 Q&A
  판정 도구 — 재참조 테스트: "2주 뒤 이 내용을 다시 찾을 이유가 있는가?" Yes → 저장
  경계 사례는 사용자에게 묻는다
  → 보존 가치가 없으면 이유를 알리고 중단한다

Step 1.5: 저장 항목 미리보기 + 시크릿 마스킹
  저장할 항목을 한 줄씩 제시한다 → 민감 항목을 이 시점에 제외할 수 있다 (사람 눈 검수)
  시크릿(API 키·토큰·비밀번호 패턴)은 무조건 [REDACTED] 자동 마스킹 —
    재참조 가치 0, 유출 리스크만 있는 유일한 범주
  이메일·사람 이름·경로는 마스킹하지 않는다 — entities/를 두는 볼트에서 이름은 지식이다

Step 2: summaries/sessions/YYYY-MM-DD-{slug}.md 에 캡처
  slug: kebab-case, 최대 50자

  frontmatter:
    category: summaries
    sources: ["conversation:YYYY-MM-DD"]
    base_confidence: 0.42
    status: unverified
    status_changed: YYYY-MM-DD
    provenance: { extracted: <비율>, inferred: <비율>, ambiguous: <비율> }

  본문은 대화 내용을 충실히 기록한다 (대화 맥락 보존, 선언적 재작성 없음).
  추론·일반화 문장에 ^[inferred], 불확실·논쟁적 문장에 ^[ambiguous] 마커를 단다.
  그 마커를 세어 위 provenance 비율을 추정·기록한다 — 대화 기반이라 inferred 비중이 대개 높다.
  (wiki-lint가 같은 마커로 재계산해 검산한다. 마커 누락은 lint도 못 잡으므로
   마커를 성실히 다는 것이 이 비율의 유일한 신뢰 기반이다.)

  권장 섹션: ## 주제 / ## 논의 내용 / ## 결론·결정 / ## 열린 질문

Step 3: wiki/index.md (summaries/sessions 섹션) + wiki/log.md 갱신
  [YYYY-MM-DD] CAPTURE type=session page="{sessions 경로}" title="{제목}"

Step 4: wiki/hot.md 갱신
Step 5: QMD refresh — 모든 쓰기 완료 후 마지막에
Step 6: 저장 경로 + QMD 상태를 사용자에게 확인 보고
```

## sessions 폐기 정책 — 영구 유지

`raw/` cleanup(14일 삭제) 규칙을 sessions에 적용하지 않는다. raw는 삭제해도 summaries가 남지만 **sessions는 자신이 곧 summary**이므로(raw 대응 없음이 정의) 삭제하면 그 대화의 유일한 기록이 소실된다.

미승격은 실패가 아니라 정상 상태다 — 승격은 가치 추가일 뿐 의무가 아니다. 가치를 잃은 세션은 별도 메커니즘 없이 일반 페이지와 동일한 archive 워크플로를 적용한다.

## 품질 체크

```
□ 재참조 테스트로 선별 (전체 저장 아님), 경계 사례는 질문
□ Step 1.5 미리보기 제시 완료
□ 시크릿 [REDACTED] 마스킹 (이름·이메일은 유지)
□ 추론·불확실 문장에 ^[inferred] / ^[ambiguous] 마커
□ provenance 블록 기록 (합 ≈ 1.0, 마커 기준)
□ status: unverified · base_confidence: 0.42 · sources: conversation:YYYY-MM-DD
□ index.md 등록 · log.md 기록 · hot.md 갱신
□ QMD refresh 실행 + 상태 문자열 보고
```

## 안티패턴

| 이렇게 하기 쉽다 | 무엇이 깨지나 | 대신 |
|---|---|---|
| 세션을 통째로 저장한다 | 잡담·미결론이 검색 후보를 늘려 신호가 묻힌다 | 재참조 테스트로 선별한다 |
| 미리보기 없이 바로 쓴다 | 민감 항목을 뺄 기회가 사라진다 | Step 1.5에서 항목 목록을 한 줄씩 제시한다 |
| 이름·이메일까지 마스킹한다 | `entities/`를 두는 볼트에서 지식을 지운다 | 시크릿만 `[REDACTED]` |
| 마커 없이 provenance 비율만 추정해 넣는다 | 검산의 근거가 사라지고 추론이 조용히 extracted로 집계된다 | 문장에 마커를 먼저 달고 그것을 세어 비율을 낸다 |
| 캡처하면서 선언적으로 재작성한다 | 대화 맥락이 사라져 나중에 판단 근거를 복원할 수 없다 | 맥락을 보존한다. 재작성은 승격 시점의 일이다 |
| 가치 있어 보여 `knowledge/`에 바로 쓴다 | 2단계 파이프라인을 우회해 검증 전 지식이 공식 문서가 된다 | `sessions/` 먼저. 승격은 명시 요청 시만 |
| 오래된 sessions를 raw처럼 14일 후 삭제한다 | 그 대화의 유일한 기록이 소실된다 | 영구 유지. 가치를 잃으면 일반 archive |
| 컨텍스트가 압축된 뒤 조용히 캡처한다 | 초반부가 요약본인데 충실한 기록처럼 보인다 | 압축 이후 캡처임을 고지한다 |
