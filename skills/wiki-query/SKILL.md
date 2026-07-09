---
name: wiki-query
description: 사용자가 wiki에 저장된 지식에 대해 질문하거나, 어떤 주제의 정보를 찾으려 할 때 사용 — "what does the wiki say about X", "wiki에서 X 찾아줘", "X에 대해 알아?".
---

# wiki-query

저렴→비싼 검색 사다리로 wiki에서 답한다. 먼저 Config Gate (+ QMD 게이트, §3-5).

**Read-only 경계:** 페이지 / index / hot / QMD를 절대 수정하지 않는다. 유일한 쓰기는 `log.md` QUERY 추가 (관측성, §3-6) — "read-only"는 *지식 콘텐츠를 바꾸지 않는다*는 뜻이지 *0바이트를 쓴다*는 뜻이 아니다. log 추가 실패는 스킬 실패가 아니다 (답은 이미 전달됨).

**QMD = discovery 전용.** QMD로 후보를 찾되; **답은 항상 파일 본문에서 검증한다** — QMD의 캐시된 텍스트로 답하지 않는다. 파일이 없거나 본문에 내용이 없는 QMD 히트 → 버리고 "QMD 인덱스가 stale할 수 있음 — /wiki-setup --update-qmd"라고 기록 (self-healing).

## 검색 사다리 (답할 수 있는 즉시 멈춤 — 토큰 최소화)
0. Config Gate + QMD 게이트. `hot.md` 읽기 — 질문이 최근 활동에 대한 것이면 hot.md만으로 바로 답할 수도 (→ step 5).
1. **분류.** 유형: Factual / Relationship (`relationships:` 필요) / Synthesis / Gap (Open Questions). 모드: "quick"/"fast lookup"/"just scan" → **index-only**; 아니면 normal.
2. **Index 패스 (저렴).** `index.md` 읽기; frontmatter-grep `^(title|tags|summary|tier):` → 후보 5–10개. 랭킹: title 정확 일치 > tags > summary 포함 > index-line 포함; 동점 tie-break은 tier core > supporting > peripheral.
   *Index-only 모드는 여기서 멈춤* — `summary:` + index 줄로 답하고, `(index-only — 본문 미읽음, 세부 누락 가능)` 라벨. → step 6.
2b. **QMD 패스** (게이트가 열린 경우만). 키워드가 놓친 후보를 시맨틱 검색 (discovery 전용; 위의 stale-hit 가드). 충분 → step 4 (top 파일만 읽음).
3. **Section 패스 (중간).** `Grep -A 10 -B 2 "<term>" <candidate>` → 100–500줄 전체 읽기 대신 15–30줄. 충분 → step 5.
4. **Full read (비쌈, 최후의 수단).** tier 기준 top 3 (peripheral은 유일한 매치일 때만). 1-hop `[[link]]` 허용. Relationship 쿼리 → `relationships:` 블록 읽기 (타입+방향 명시). Gap 쿼리 → "Open Questions" 섹션. 여전히 부족 → 볼트 전체 콘텐츠 grep + 에스컬레이션 중이라고 사용자에게 알림.
5. **종합:**
   > Based on the wiki:
   > [answer with [[wikilink]] citations]
   > Pages consulted: [[a]], [[b]]
   > Gaps: [what the wiki doesn't cover]

   인용마다 실제 사용한 경로를 라벨링: "found in summary" / "section grep" / "full page read". (오늘 − `updated`) > 90일이면 stale 페이지를 `[[page]] (stale: last updated YYYY-MM-DD)`로 표시. 미확정 페이지는 사실로 회상하지 않도록 표시: `status: proposed` → `(proposed — 미확정 설계)`; 잔여 `[NEEDS CLARIFICATION]` / `status: unverified` → `(미확정: 가정 포함)`.
   **wiki에 없음 → 솔직히 그렇게 말한다. 절대 자신의 지식으로 답을 지어내 wiki 콘텐츠인 양 제시하지 않는다.**
6. **`log.md` 추가:** `[YYYY-MM-DD] QUERY query="…" result_pages=N mode=normal|index_only escalated=true|false`.
7. 답이 가치 있는 새 지식이면 → 저장을 **제안** (`knowledge/` 페이지 또는 `/wiki-capture`). 절대 자동 생성 안 함.
