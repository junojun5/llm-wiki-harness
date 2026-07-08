---
name: wiki-capture
description: Use when the user wants to preserve knowledge from the current conversation into the wiki — "capture this", "save this to the wiki", "wiki에 기록해줘".
---

# wiki-capture

Captures the current conversation to `summaries/sessions/`. Run the Config Gate first.

**Two-stage pipeline:** conversation → `summaries/sessions/` (this skill's job). Promotion to `knowledge/` / `concepts/` / `entities/` / `projects/` happens **only on explicit user request** — never auto-promote.

Input = the current conversation (you already hold it; no transcript pipeline needed). ⚠️ If the session was compacted, its early parts survive only as summaries — tell the user capture is most faithful done early.

## Workflow
0. **Config Gate.**
0.5 Read `hot.md` — has similar content already been captured?
1. **Select what to save** (not the whole session). Re-reference test: *"would I look this up again in 2 weeks?"* Yes → save. ✅ decisions + rationale, technical findings, analyses/frameworks, key facts. ❌ exploratory chatter, inconclusive threads, one-off Q&A. Boundary cases → ask. Nothing worth saving → tell the user why and stop.
1.5 **Preview + secret masking.** Show the items to save, one per line (the user can exclude sensitive ones here). **Mask secrets only** — API keys, tokens, passwords → replace the value with `[REDACTED]` automatically (zero re-reference value, pure leak risk). **Do NOT mask names, emails, or paths** — in a vault that keeps `entities/`, a name is knowledge, not a secret. No hedging: keep them. (Local-vault premise + this preview is the human review step.)
2. **Write the session page** `summaries/sessions/YYYY-MM-DD-{slug}.md` (slug kebab-case, ≤50 chars):
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
   Body: record the discussion **faithfully** (preserve conversational context, no declarative rewrite). Mark inferred/generalized sentences `^[inferred]` and uncertain/contested ones `^[ambiguous]` (§3-3); estimate the `provenance` ratios from those markers — conversation captures usually skew `inferred` high (wiki-lint check 13 re-computes from the markers). Sections: `## 주제` / `## 논의 내용` / `## 결론·결정` / `## 열린 질문`.
   Entities mentioned (people/orgs) → create/update `entities/` pages, link both ways.
3. `index.md` (summaries/sessions section) + `log.md`: `[YYYY-MM-DD] CAPTURE type=session page="…" title="…"`.
4. `hot.md`: Recent Activity (1-line, keep last 3) + Key Takeaways if notable; bump `updated`.
5. **QMD refresh** (last, after all writes).
6. Report the saved path(s) + QMD status.

## Sessions are permanent
The 14-day raw-cleanup rule does **not** apply to `sessions/` — a session *is* its own summary (no raw counterpart), so deleting it loses the only record. Non-promotion is normal, not failure. A session that has lost value uses the ordinary archive workflow (single demotion mechanism), not deletion.

`knowledge/` page creation is a separate skill — wiki-capture stops at `sessions/`.
