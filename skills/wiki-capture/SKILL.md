---
name: wiki-capture
description: 사용자가 현재 대화의 지식을 wiki에 보존하려 할 때 사용 — "capture this", "save this to the wiki", "wiki에 기록해줘".
---

# wiki-capture

현재 대화를 `summaries/sessions/`에 캡처한다. 먼저 Config Gate를 실행한다.

**2단계 파이프라인:** 대화 → `summaries/sessions/` (이 스킬의 일). `knowledge/` / `concepts/` / `entities/` / `projects/`로의 승격(promotion)은 **사용자의 명시적 요청 시에만** 일어난다 — 절대 자동 승격하지 않는다.

입력 = 현재 대화 (이미 갖고 있음; transcript 파이프라인 불필요). ⚠️ 세션이 compact됐다면 초반부는 요약으로만 남아 있으니 — 캡처는 일찍 할수록 가장 충실하다고 사용자에게 알린다.

## 워크플로우
0. **Config Gate.**
0.5 `hot.md` 읽기 — 유사한 내용이 이미 캡처됐는가?
1. **저장할 것 선별** (전체 세션이 아님). 재참조 테스트: *"2주 뒤에 이걸 다시 찾아볼까?"* 예 → 저장. ✅ 결정 + 근거, 기술적 발견, 분석/프레임워크, 핵심 사실. ❌ 탐색성 잡담, 결론 없는 스레드, 일회성 Q&A. 경계 사례 → 묻는다. 저장할 게 없음 → 이유를 사용자에게 말하고 중단.
1.5 **미리보기 + 시크릿 마스킹.** 저장할 항목을 한 줄에 하나씩 보여준다 (사용자가 여기서 민감한 것을 제외할 수 있음). **시크릿만 마스킹** — API 키, 토큰, 비밀번호 → 값을 자동으로 `[REDACTED]`로 교체 (재참조 가치 제로, 순수 유출 리스크). **이름, 이메일, 경로는 마스킹하지 않는다** — `entities/`를 유지하는 볼트에서 이름은 시크릿이 아니라 지식이다. 얼버무리지 말고: 그대로 둔다. (로컬 볼트 전제 + 이 미리보기가 사람의 검토 단계다.)
2. **세션 페이지 작성** `summaries/sessions/YYYY-MM-DD-{slug}.md` (slug은 kebab-case, ≤50자):
   ```yaml
   ---
   title: "..."
   category: summaries
   tags: [...]
   sources: ["conversation:YYYY-MM-DD"]
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   summary: "..."            # ≤400 chars
   status: unverified
   status_changed: YYYY-MM-DD
   base_confidence: 0.42     # conversation source — fixed value, not a guess
   provenance: { extracted: <r>, inferred: <r>, ambiguous: <r> }   # marker-based, sum ≈ 1.0
   ---
   ```
   본문: 논의를 **충실히** 기록 (대화 맥락 보존, 선언형으로 다시 쓰지 말 것). 추론/일반화된 문장은 `^[inferred]`, 불확실/논쟁적인 것은 `^[ambiguous]`로 표시 (§3-3); 그 마커들로부터 `provenance` 비율을 추정 — 대화 캡처는 보통 `inferred`가 높게 치우친다 (wiki-lint 체크 13이 마커로부터 재계산). 섹션: `## 주제` / `## 논의 내용` / `## 결론·결정` / `## 열린 질문`.
   언급된 엔티티(사람/조직)는 세션 페이지 본문에서 `[[entities/...]]`로 **언급·링크만** 한다 (참조는 페이지 생성이 아니다). `entities/` 페이지 생성/갱신은 하지 않는다 — 승격은 사용자의 명시적 요청 시에만 일어난다 (상단 2단계 파이프라인).
3. `index.md` (summaries/sessions 섹션) + `log.md`: `[YYYY-MM-DD] CAPTURE type=session page="…" title="…"`.
4. `hot.md`: Recent Activity (1줄, 최근 3개 유지) + 주목할 만하면 Key Takeaways; `updated` 갱신.
5. **QMD refresh** (마지막, 모든 쓰기 이후).
6. 저장된 경로 + QMD 상태 보고.

## 세션은 영구적
14일 raw-cleanup 규칙은 `sessions/`에 **적용되지 않는다** — 세션은 그 자체가 요약(raw 대응 없음)이므로, 삭제하면 유일한 기록을 잃는다. 승격되지 않는 것은 정상이지 실패가 아니다. 가치를 잃은 세션은 일반 archive 워크플로우(단일 강등 메커니즘)를 쓰지, 삭제하지 않는다.

`knowledge/` 페이지 생성은 별도 스킬이다 — wiki-capture는 `sessions/`에서 멈춘다.
