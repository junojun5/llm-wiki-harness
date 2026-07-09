---
name: wiki-knowledge
description: 사용자가 여러 요약·개념·세션을 종합하여 knowledge/ 페이지를 만들거나 갱신하려 할 때 사용 — "make a knowledge page", "이 주제 정리해줘", "summaries 종합해줘", "knowledge 업데이트", "/wiki-knowledge".
---

# wiki-knowledge

여러 summaries / concepts / sessions를 살아있는 `knowledge/` 페이지로 종합한다. 먼저 Config Gate. `wiki-ingest`(소스당 요약 하나)와 달리, 이 스킬은 소스 *전반에 걸쳐* 증류한다. `knowledge/` 페이지는 **이 스킬 또는 사용자의 명시적 요청으로만** 생성된다 — ingest가 자동 생성하지 않는다.

## 페이지 템플릿 (Diátaxis Explanation + Zettelkasten + dev-docs)
Frontmatter — 서로 구별되는 세 provenance 필드에 주목:
```yaml
sources: ["https://url-1", "https://url-2"]   # upstream ORIGINAL URLs/conversation (provenance)
relationships:                                 # SYNTHESIS TRAIL — which pages this was distilled FROM
  - target: "[[summaries/papers/x]]"
    type: depends_on
  - target: "[[concepts/y]]"
    type: extends
provenance: { extracted: <r>, inferred: <r>, ambiguous: <r> }   # when 나의 노트/inference present, sum ≈ 1.0
```
**구별을 유지:** `sources:` = upstream URL · `relationships: depends_on` = 종합 계보(lineage) · `## 관련 페이지` = 내비게이션 링크. (흔한 함정은 계보를 관련 페이지로 뭉개는 것.)
섹션: `## 개요` / `## 핵심 개념` / `## 작동 원리` / `## 트레이드오프` (표) / `## 실제 사례` / `## 나의 노트` / `## 열린 질문` / `## 관련 페이지`.
- 개요~트레이드오프 = 증류된 공식 지식 (WHY 중심). 실제 사례 = 적용 경험. **`## 나의 노트`** = 개인적 질문/조사 — 추론 문장은 `^[inferred]`, 불확실/논쟁적인 것은 `^[ambiguous]`로 표시하고, 그 마커들로부터 `provenance` 비율을 추정. 열린 질문 = 문헌 갭.

## 워크플로우
0. Config Gate. 0.5 hot.md 읽기 (관련 스레드).
1. 대상 페이지가 존재? **없음 → create 모드** (2 → 2.5 → 5). **있음 → update 모드** (2 → 3 → 4 → 5).
2. **자료 수집:** 지정된 summaries/concepts/sessions 읽기; index.md에서 관련 페이지 grep; 각 자료의 `sources:` URL을 끌어옴 (knowledge 페이지의 `sources:`를 채우기 위해).
2.5 **[create 모드] 쓰기 전 종합 미리보기** (update의 Step 4와 대칭): `sources_used` 목록 + 섹션별 핵심 주장 + 예상 provenance 보고 (inferred/ambiguous가 높으면 플래그). 방향 확인 — 정식 승인이 아니라 "형태가 맞나?" 정도의 가벼운 게이트.
3. **[update 모드] 기존 페이지를 읽고, 각 주장을 분류** (수치 임계값이 아니라 정성적): 동일 주장 → 유지 + 출처 추가; 세부/구체성 차이 → 더 정밀한 버전을 통합; 범위/맥락 차이 → 둘 다 유지, 맥락 명시; **정면 모순 → status: conflict + §3-3 충돌 노트**; 신규 → 통합; 구조적 → 분할 트리거 확인. LLM이 분류; 정면 모순만 사용자 판정 필요.
4. **[update 모드] 변경 계획 보고** (`[통합]` / `[출처 보강]` / `[충돌]` / `[구조 제안]`); 충돌과 구조 변경은 확인 필요, 나머지는 진행.
5. **작성 / 갱신:**
   - create → 템플릿; update → 구조 보존, **병합(통합, 절대 맹목적 append 아님)**.
   - 충돌 확정 → `status: conflict`, `## Conflicts` 열린 항목, `status_changed` 갱신.
   - 구조 변경 → 하위 폴더 + `index.md` 허브; 새 하위 페이지를 먼저 쓰고, 그다음 원본을 허브로 전환 (§3-6 원본 먼저). Lint가 링크 드리프트를 복구; git이 롤백.
6. `index.md` + `log.md`: `[YYYY-MM-DD] KNOWLEDGE mode=create|update page="…" sources_used=N changes=merge|conflict|restructure`.
7. hot.md (Recent Activity + 주목할 만하면 Key Takeaways / Active Threads).
8. **QMD refresh** (마지막).

## 분할 트리거 (→ 하위 폴더; 원본은 index 허브가 됨)
`summary` >400자 · 한 섹션이 >2화면 · 한 섹션이 단독 링크됨 · 새 콘텐츠가 기존 페이지의 >30%.

## 품질 체크
모든 주장에 출처 (`(출처: [[…]])` 또는 `sources:`) · `relationships: depends_on`이 종합을 추적 · `## 나의 노트` 추론은 `^[inferred]`/`^[ambiguous]` 표시 + `provenance` 설정 · `[[links]]` ≥2개 · index/log/hot/QMD 갱신됨 · `summary` ≤400.
