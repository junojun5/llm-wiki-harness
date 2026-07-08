---
name: wiki-project-design
description: Use when creating or evolving a project's design docs — architecture, domain model (glossary + domain/business rules), conventions — in projects/{name}/. "design the architecture", "update the design", "capture the domain rules", "/wiki-project-design".
---

# wiki-project-design

Creates/evolves a project's design docs (`architecture.md`, `domain.md`, `conventions.md`) via change proposals. Config Gate first. Owns these three docs; pulls evidence from knowledge/summaries.

## Surface vs semantic change (decisive)
- **Surface** (typo, status number, link repair, wording) → edit directly, integrate.
- **Semantic** (a claim, structure, or tech choice changes) → **change proposal REQUIRED.** Never edit a design doc's *meaning* directly — AS-IS→TO-BE and the decision trail must persist as history (even for a solo user; it's material for the next project).

## Change-proposal lifecycle
1. Create `changes/YYYY-MM-DD-{slug}.md`, `status: proposed`. Class-② frontmatter: title / category=projects / project / targets / status / created / status_changed / summary / `base_confidence: 0.3` / `tier: peripheral`. Body: `## 동기` / `## Delta` (ADDED/MODIFIED/REMOVED, each with **AS-IS** + **TO-BE**) / `## 근거` (`(출처: [[knowledge]])` or `⚠️ unverified` + missing-knowledge note) / `## 영향`.
2. User reviews → approve / revise / reject.
3a. **Approve →** re-read the target doc to **confirm AS-IS still matches the current content** (re-verify the body, not a stored checksum); if it drifted, update the proposal and re-approve. Then: merge the delta (integrate, don't append) → append the `decisions.md` entry **directly** (§4-9-3 format; write `변경 기록: [[changes/archive/YYYY-MM-DD-{slug}]]` as the **final archive path** so the link survives the move) → move the proposal to `changes/archive/` (`status: applied`, bump `status_changed`).
3b. **Reject →** move to `changes/archive/` (`status: rejected` + reason). Rejections are design history too.

Mid-sequence failure is fine: lint check 16 detects stranded proposed / un-archived / missing decisions link; git is rollback (§3-6 — no staging/transaction).

## Workflow
0. Config Gate. 0.5 hot.md. 1. Identify target doc + change type (surface → step 5; semantic → step 2). 2. Gather material (conversation incl. code-analysis results; **wiki-query knowledge/summaries — required for architecture work**; check `changes/archive/` for prior history on the same topic). 3. Write the proposal (proposed) → request review. 4. (semantic) approve → AS-IS re-verify → merge + decisions append + archive; reject → archive. 5. (surface) integrate directly; in domain.md, general concepts go as `[[knowledge]]` links (no body duplication). 6. Self-verify loop. 7. Gap report (incl. missing knowledge). 8. End sequence. log: `[YYYY-MM-DD] PROJECT-DESIGN name="…" change="{slug}|surface" files=[…]`.

## Doc structure
- **architecture.md:** 시스템 컨텍스트 (C4 L1) / 컨테이너 (C4 L2) — mermaid recommended (see `references/mermaid-conventions.md`) / 핵심 컴포넌트 (L3, complex parts on-demand) / 기술 스택 결정 근거 (`(출처: [[knowledge]])` + `[[decisions]]`).
- **domain.md** = domain model: 용어집 (ubiquitous language) / 도메인 규칙·불변식 / 비즈니스 로직 (code = brief example only; never reverse-extract from a codebase — Phase 2). General concepts → `[[knowledge]]` link. >400-char summary or >2 screens → split to `domain/{bc}.md` per bounded context.
- **conventions.md:** secondary, logic-first (describe agreed rules; code only as brief examples). Code projects only.

## decisions.md co-write boundary
You append the `decisions.md` pairing for **design-changing decisions** directly (format is record's single source; no delegation call). Design-*independent* decisions belong to wiki-project-record. The two are distinguished by the `변경 기록:` line (present ⟺ went through design).
