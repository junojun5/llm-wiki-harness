---
name: wiki-capture
description: 현재 대화 지식을 wiki에 보존할 때 사용 — "이거 기록해줘", "save this to the wiki", "wiki에 기록해줘", "/wiki-capture".
---

# wiki-capture

## 개요
현재 대화에서 보존 가치 있는 지식을 선별해 `summaries/sessions/YYYY-MM-DD-{slug}.md`에 **항상 먼저** 저장한다. `knowledge/`·`concepts/`·`entities/`·`projects/`로의 승격은 **사용자가 명시적으로 요청할 때만** 일어난다 — 절대 자동 승격하지 않는다.

```
대화 세션 → summaries/sessions/ (이 스킬의 일, 항상)
                    ↓ 사용자 명시 요청 시만
           knowledge/ | concepts/ | entities/ | projects/
```

**입력:** 현재 대화 컨텍스트 — 스킬을 실행하는 LLM 자신이 이미 대화를 컨텍스트 윈도우에 들고 있으므로 transcript API·파일 경유·stdin 같은 별도 획득 파이프라인은 불필요하다.

> ⚠️ **컨텍스트 압축 한계:** 긴 세션의 초반부는 압축 후 요약본만 남는다. 캡처는 빠를수록 충실하다 — 압축 이후 캡처 시 초반부가 요약 수준으로만 저장됨을 사용자에게 고지한다.

**캡처 범위:** 기본 = 현재 세션 전체에서 워크플로우 Step 1 필터로 선별한 것 (세션 전체 저장이 아님). 사용자가 자연어로 범위를 지정하면("방금 논의한 X만") 그 부분만 — 별도 플래그 문법은 두지 않는다.

## 언제 사용
- **트리거:** "이거 기록해줘", "capture this", "save this to the wiki", "wiki에 기록해줘", `/wiki-capture`.
- **아니면:** `raw/`에 이미 있는 로컬 파일을 ingest할 때는 `wiki-ingest`. URL을 저장할 때는 `ingest-url`. 세션을 `knowledge/`·`concepts/`·`entities/`·`projects/`로 승격하는 것은 이 스킬의 일이 아니다 — 사용자가 명시적으로 요청하면 해당 승격 스킬(예: `wiki-knowledge`)로 안내한다.

## 비밀 마스킹 규칙

> **GATE — Step 1.5 미리보기 시점에 항상 적용.**
> - ✅ **시크릿(API 키·토큰·비밀번호 패턴)은 무조건 자동으로 `[REDACTED]`로 교체한다** — 재참조 가치가 0이고 유출 리스크만 있는 유일한 범주다. 예외 없음.
> - ❌ **이메일·사람 이름·경로는 마스킹하지 않는다** — `entities/`를 두는 볼트에서 이름은 시크릿이 아니라 지식이다. 얼버무리지 말고 그대로 둔다.
> - 근거: 개인 로컬 볼트 전제 + Step 1.5 미리보기가 사람 눈 검수 역할을 이미 수행한다.

## 워크플로우

0. **Config Gate.**
0.5. **`wiki/hot.md` 읽기** (있으면) — 최근 활동 파악, 유사 내용이 이미 캡처됐는지 확인.
1. **보존 가치 있는 지식 식별.**
   - ✅ 저장: 결정과 이유, 기술적 발견, 분석/프레임워크, 핵심 사실.
   - ❌ 스킵: 탐색 중 잡담, 결론 없는 논의, 일회성 Q&A.
   - 판정 도구 — 재참조 테스트: *"2주 뒤 이 내용을 다시 찾을 이유가 있는가?"* 예 → 저장.
   - 경계 사례 → 사용자에게 질문한다 (분류가 불확실하면 묻는다).
   - 보존 가치 있는 게 없으면 이유를 사용자에게 알리고 중단한다.
1.5. **저장 항목 미리보기 + 시크릿 마스킹.** 저장할 항목을 한 줄씩 사용자에게 제시한다 — 이 시점에 민감 항목을 제외할 수 있다. 마스킹 규칙은 위 **## 비밀 마스킹 규칙** 참조.
2. **세션 페이지 작성** `wiki/summaries/sessions/YYYY-MM-DD-{slug}.md` (slug: kebab-case, ≤50자):
   ```yaml
   ---
   title: "..."
   category: summaries
   tags: [...]
   sources: ["conversation:YYYY-MM-DD"]
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   summary: "..."            # ≤400자
   status: unverified
   status_changed: YYYY-MM-DD
   base_confidence: 0.42     # conversation 소스 — 고정값, 추정치 아님
   provenance: { extracted: <r>, inferred: <r>, ambiguous: <r> }   # 마커 기준 추정, 합 ≈ 1.0
   ---
   ```
   본문: 논의를 **충실히** 기록한다 — 대화 맥락을 보존하고, 선언형으로 다시 쓰지 않는다.
   - **마커:** 추론·일반화 문장에 `^[inferred]`, 불확실·논쟁적 문장에 `^[ambiguous]`.
   - **provenance:** 위 frontmatter의 비율은 이 마커들을 근거로 추정·기록한다 (대화 캡처는 보통 `inferred` 비중이 높다).
   - **검산:** wiki-lint check 13이 마커를 재계산해 이 비율을 검산한다.
   권장 섹션: `## 주제` / `## 논의 내용` / `## 결론 / 결정` / `## 열린 질문`.
   언급된 엔티티(사람/조직)는 본문에서 `[[slug]]`로 **언급·링크만** 한다 (참조는 페이지 생성이 아니다) — `entities/` 페이지 자체의 생성·갱신은 하지 않는다. 승격은 사용자의 명시적 요청 시에만 일어난다 (상단 2단계 파이프라인).
3. **`wiki/index.md` 갱신.** `summaries/sessions` 서브섹션에 페이지를 추가한다.
   - 서브섹션이 없으면 새로 만들고 추가한다 (wiki-setup은 최상위 카테고리 섹션만 시드하며, 서브섹션은 하드코딩하지 않는다).
   - **`wiki/log.md`:** `[YYYY-MM-DD] CAPTURE type=session page="{sessions 경로}" title="{제목}"` 한 줄을 덧붙인다.
4. **`wiki/hot.md` 갱신** (없으면 §4-1 Step 8 템플릿으로 생성). Recent Activity — 방금 캡처한 내용 한 줄 요약, 최근 3개 유지. Key Takeaways — 주목할 인사이트·결정 포함 시 갱신. `updated` 타임스탬프 갱신.
5. **QMD refresh** (§3-5, `using-llm-wiki` 참조) — hot.md까지 모든 쓰기 완료 후 마지막 단계. QMD 상태 문자열을 최종 보고에 포함한다.
6. **저장 경로 + QMD 상태를 사용자에게 확인 보고.**

## 세션은 영구적

14일 raw-cleanup 규칙은 `sessions/`에 **적용되지 않는다** — 세션은 그 자체가 요약(raw 대응 없음)이므로, 삭제하면 그 대화의 유일한 기록을 잃는다. 승격되지 않는 것은 정상이지 실패가 아니다(승격은 가치 추가일 뿐 의무가 아니다). 가치를 잃은 세션은 별도 메커니즘 없이 일반 archive 워크플로우(단일 강등 원칙)를 그대로 적용한다.

> ⚠️ wiki-capture는 `sessions/` 캡처까지만 담당한다. `knowledge/` 페이지 생성은 별도 스킬(`wiki-knowledge`)이 처리한다.

## 품질 체크
```
□ 저장 항목이 재참조 테스트(2주 뒤 다시 찾을 이유)를 통과함 — 잡담/일회성 Q&A 제외됨
□ Step 1.5 미리보기에서 시크릿(API 키·토큰·비밀번호)이 전부 [REDACTED]로 마스킹됨
□ 이메일·이름·경로는 마스킹하지 않음 (entities 링크는 언급만, 페이지 생성 없음)
□ frontmatter 고정값 정확: base_confidence: 0.42 · status: unverified · sources: ["conversation:YYYY-MM-DD"]
□ provenance 비율이 본문의 ^[inferred] / ^[ambiguous] 마커와 정합
□ index.md summaries/sessions 서브섹션 반영 (없으면 신설)
□ log.md 기록 · hot.md 갱신
□ QMD 상태 문자열을 최종 보고에 포함
```
