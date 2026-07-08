---
name: wiki-query
description: Use when the user asks a question about knowledge stored in the wiki, or to find information on a topic — "what does the wiki say about X", "wiki에서 X 찾아줘", "X에 대해 알아?".
---

# wiki-query

Answers from the wiki with a cheap→expensive search ladder. Config Gate first (+ QMD gate, §3-5).

**Read-only boundary:** never modify pages / index / hot / QMD. The ONLY write is a `log.md` QUERY append (observability, §3-6) — "read-only" means *don't change knowledge content*, not *write zero bytes*. A failed log append is NOT a skill failure (the answer is already delivered).

**QMD = discovery only.** Use QMD to find candidates; **always verify the answer in the file body** — never answer from QMD's cached text. A QMD hit whose file is missing or whose body lacks the content → discard it and note "QMD 인덱스가 stale할 수 있음 — /wiki-setup --update-qmd" (self-healing).

## Search ladder (stop as soon as you can answer — minimize tokens)
0. Config Gate + QMD gate. Read `hot.md` — if the question is about recent activity, hot.md may answer outright (→ step 5).
1. **Classify.** Type: Factual / Relationship (needs `relationships:`) / Synthesis / Gap (Open Questions). Mode: "quick"/"fast lookup"/"just scan" → **index-only**; else normal.
2. **Index pass (cheap).** Read `index.md`; frontmatter-grep `^(title|tags|summary|tier):` → 5–10 candidates. Rank: title exact > tags > summary contains > index-line contains; tie-break tier core > supporting > peripheral.
   *Index-only mode stops here* — answer from `summary:` + index line, labeled `(index-only — 본문 미읽음, 세부 누락 가능)`. → step 6.
2b. **QMD pass** (only if the gate is open). Semantic search for keyword-missed candidates (discovery only; stale-hit guard above). Enough → step 4 (read only the top files).
3. **Section pass (medium).** `Grep -A 10 -B 2 "<term>" <candidate>` → 15–30 lines instead of a full 100–500-line read. Enough → step 5.
4. **Full read (expensive, last resort).** Top 3 by tier (peripheral only if it's the sole match). 1-hop `[[link]]` allowed. Relationship query → read the `relationships:` block (state type+direction). Gap query → the "Open Questions" section. Still short → vault-wide content grep + tell the user you're escalating.
5. **Synthesize:**
   > Based on the wiki:
   > [answer with [[wikilink]] citations]
   > Pages consulted: [[a]], [[b]]
   > Gaps: [what the wiki doesn't cover]

   Per citation, label the path actually used: "found in summary" / "section grep" / "full page read". Mark stale pages `[[page]] (stale: last updated YYYY-MM-DD)` when (today − `updated`) > 90 days. Mark unconfirmed pages so you don't recall them as fact: `status: proposed` → `(proposed — 미확정 설계)`; residual `[NEEDS CLARIFICATION]` / `status: unverified` → `(미확정: 가정 포함)`.
   **Not in the wiki → say so plainly. Never invent an answer from your own knowledge and present it as wiki content.**
6. **`log.md` append:** `[YYYY-MM-DD] QUERY query="…" result_pages=N mode=normal|index_only escalated=true|false`.
7. If the answer is valuable new knowledge → **offer** to save it (`knowledge/` page or `/wiki-capture`). Never auto-create.
