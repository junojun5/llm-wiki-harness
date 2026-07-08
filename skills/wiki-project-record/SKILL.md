---
name: wiki-project-record
description: Use when recording a project event — a decision, a troubleshooting case, a meeting summary, or a backlog item — into projects/{name}/. "record this decision", "log this issue", "백로그에 추가", after a problem is solved, "/wiki-project-record".
---

# wiki-project-record

Routes a project event to the right file and records it. Config Gate first. A **routing sink**, not just a logger — the unifying trait is *route-then-record*; immutability differs per file.

## Routing table (auto-judge; ask if unsure)
- **Decision made:**
  - **changes a design doc** (architecture/domain/conventions) → hand to **wiki-project-design** (it owns proposal → merge → the decisions.md pairing).
  - design-independent (vendor, schedule, budget) → **decisions.md append (direct).**
- **TODO / potential risk** → `backlog.md` (`## TODO` / `## 위험`, with source).
- **Problem solved** → `troubleshooting/{case}.md` (`status: resolved` — 증상/원인/해결/재발 방지).
- **Debugging, unsolved** → `troubleshooting/{case}.md` (`status: open` — 증상/가설/실험, updated incrementally).
- **Live meeting (no raw transcript)** → `meetings/YYYY-MM-DD-{slug}.md`. (Raw transcript → wiki-ingest → `summaries/meetings/`, §4-2.)
- **Generalizable knowledge** → propose **wiki-knowledge** promotion (don't write it into projects/).
- **Design-doc change but not decision-shaped** (terms/rules/structure cleanup) → wiki-project-design.
- **Unsure** → ask.

## Approval — the decision is the user's
**Never auto-append.** Present the draft (결정 / 이유 / 대안) and get confirmation first. You may *propose* "결정으로 기록할까요?" when discussion converges, but the user stamps it.

## Immutability (differs per file)
- **decisions.md / meetings/** — fully immutable (append or new file only). decisions.md entry (no frontmatter — class-③ ledger):
  ```
  ## [YYYY-MM-DD] {제목}
  - 결정: …
  - 이유: … ((출처: [[knowledge]]) 인용 가능)
  - 대안 및 제외 이유: …
  - 변경 기록: [[changes/archive/YYYY-MM-DD-{slug}]]   ← design 경유 시만
  ```
  To reverse a decision: append a **new** entry referencing the old one — never edit an existing entry.
- **troubleshooting/{case}.md** — `open` (mutable: 증상/가설/실험) → `resolved` (immutable: fill 원인/해결/재발 방지). Recurrence → append `## Follow-up — [[new case]]` link only; body untouched.
- **backlog.md** — living (toggle checkboxes, update risk status). The only mutable output.

## Workflow
0. Config Gate. 0.5 hot.md. 1. Route (table above). 2. Draft from the conversation, follow the file's format → **confirm with the user**. 3. Append / create the case file (create on its first record). 4. Link related `[[knowledge/concepts/design]]`. 5. Brief gap report (flag unrecorded decision candidates). 6. End sequence. log: `[YYYY-MM-DD] PROJECT-RECORD name="…" type=decision|troubleshooting|meeting|backlog target="…"`.

## Quality check
approval obtained before append · existing entries unmodified (decisions / resolved troubleshooting / meetings are append-only; backlog + open troubleshooting are the mutable exceptions) · decision 이유 sourced or `⚠️ unverified` · resolved case has all 4 sections · backlog item has a source · index/log/hot/QMD updated.
