---
name: wiki-knowledge
description: Use when the user wants to create or update a knowledge/ page by synthesizing multiple summaries, concepts, or sessions — "make a knowledge page", "이 주제 정리해줘", "summaries 종합해줘", "knowledge 업데이트", "/wiki-knowledge".
---

# wiki-knowledge

Synthesizes multiple summaries / concepts / sessions into a living `knowledge/` page. Config Gate first. Unlike `wiki-ingest` (one summary per source), this distills *across* sources. `knowledge/` pages are created **only by this skill or on explicit user request** — never auto-created by ingest.

## Page template (Diátaxis Explanation + Zettelkasten + dev-docs)
Frontmatter — note the three distinct provenance fields:
```yaml
sources: ["https://url-1", "https://url-2"]   # upstream ORIGINAL URLs/conversation (provenance)
relationships:                                 # SYNTHESIS TRAIL — which pages this was distilled FROM
  - target: "[[summaries/papers/x]]"
    type: depends_on
  - target: "[[concepts/y]]"
    type: extends
provenance: { extracted: <r>, inferred: <r>, ambiguous: <r> }   # when 나의 노트/inference present, sum ≈ 1.0
```
**Keep distinct:** `sources:` = upstream URLs · `relationships: depends_on` = synthesis lineage · `## 관련 페이지` = navigation links. (The baseline trap is collapsing the lineage into Related pages.)
Sections: `## 개요` / `## 핵심 개념` / `## 작동 원리` / `## 트레이드오프` (table) / `## 실제 사례` / `## 나의 노트` / `## 열린 질문` / `## 관련 페이지`.
- 개요~트레이드오프 = distilled official knowledge (WHY-focused). 실제 사례 = applied experience. **`## 나의 노트`** = personal questions/investigation — mark inferred sentences `^[inferred]`, uncertain/contested `^[ambiguous]`, and estimate the `provenance` ratios from those markers. 열린 질문 = literature gaps.

## Workflow
0. Config Gate. 0.5 Read hot.md (related threads).
1. Target page exists? **No → create mode** (2 → 2.5 → 5). **Yes → update mode** (2 → 3 → 4 → 5).
2. **Gather material:** read the specified summaries/concepts/sessions; grep index.md for related pages; pull each material's `sources:` URLs (to populate the knowledge page's `sources:`).
2.5 **[create mode] Synthesis preview before writing** (symmetric with update's Step 4): report `sources_used` list + per-section key claims + expected provenance (flag if inferred/ambiguous is high). Confirm the direction — a light "is this the right shape?" gate, not a formal approval.
3. **[update mode] Read the existing page, classify each claim** (qualitative, not numeric thresholds): same claim → keep + add the source; detail/specificity diff → integrate the more precise version; scope/context diff → keep both, state the context; **head-on contradiction → status: conflict + §3-3 conflict note**; new → integrate; structural → check split triggers. The LLM classifies; only head-on contradiction needs user adjudication.
4. **[update mode] Report the change plan** (`[통합]` / `[출처 보강]` / `[충돌]` / `[구조 제안]`); conflicts and structure changes need confirmation, the rest proceeds.
5. **Write / update:**
   - create → the template; update → preserve structure, **merge (integrate, never blind-append)**.
   - conflict confirmed → `status: conflict`, `## Conflicts` open item, bump `status_changed`.
   - structure change → subfolder + `index.md` hub; write the new sub-pages first, then flip the original to a hub (§3-6 original-first). Lint repairs link drift; git is the rollback.
6. `index.md` + `log.md`: `[YYYY-MM-DD] KNOWLEDGE mode=create|update page="…" sources_used=N changes=merge|conflict|restructure`.
7. hot.md (Recent Activity + Key Takeaways / Active Threads if notable).
8. **QMD refresh** (last).

## Split triggers (→ subfolder; original becomes the index hub)
`summary` >400 chars · a section >2 screens · a section linked standalone · new content >30% of the existing page.

## Quality check
every claim sourced (`(출처: [[…]])` or `sources:`) · `relationships: depends_on` traces the synthesis · `## 나의 노트` inference marked `^[inferred]`/`^[ambiguous]` + `provenance` set · ≥2 `[[links]]` · index/log/hot/QMD updated · `summary` ≤400.
