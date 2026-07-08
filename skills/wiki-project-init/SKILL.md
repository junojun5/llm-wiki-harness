---
name: wiki-project-init
description: Use when starting or (re)framing a project in the wiki — "start a project", "plan project X", "프로젝트 기획하자", "프로젝트 문서 세팅", "/wiki-project-init". Creates projects/{name}/ overview, context, goals.
---

# wiki-project-init

Creates/reframes `projects/{name}/` snapshot docs (overview, context, goals) via a guided interview. Config Gate first. **Owns overview/context/goals only** — design docs belong to wiki-project-design, decisions/logs to wiki-project-record.

## Interview pattern (spec-kit)
Ask the per-file checklist **one question at a time**, offering a recommended answer (acceptable with "yes"). For uncertain items: **fill an informed guess**, and only for project-shaping unknowns add a `[NEEDS CLARIFICATION: question]` marker in the body — **max 5 total**. A doc with ≥1 residual marker gets frontmatter `status: unverified` (so wiki-query flags it "(미확정: 가정 포함)"); unresolved markers surface in the gap report.
- **overview:** 목적 한 문장? 이해관계자? 성공 KPI? 현재 상황?
- **context:** 왜 지금 하는가? 제약(예산·기한·기술·인력)? 외부 의존성? 실패 시나리오?
- **goals:** 마일스톤? 측정 가능한 성공 기준? **비목표(non-goals) — 명시적으로 안 하는 것 (필수 섹션).**

## Workflow
0. Config Gate. 0.5 Read hot.md (related threads).
1. Confirm the name (slug §2) → check whether `projects/{name}/` exists. Exists → **reframe mode**: read existing, interview to update, **preserve & integrate existing content (never overwrite)**. Semantic-change routing on reframe: 목적/KPI/제약 change → decisions.md pair (wiki-project-record); architecture/tech-choice change → wiki-project-design.
2. Interview (checklist, one at a time; ≤5 markers).
3. wiki-query for evidence (common principle: search always, cite only on match; otherwise `⚠️ unverified` + record "missing knowledge: {topic}" in the gap report — no forced citations).
4. Create `overview.md` + `context.md` (`goals.md` only if goals were discussed). `category: projects`; link related concepts/entities.
5. Self-verification checklist loop (≤2 iterations, then report residue).
6. **Gap report** (3 kinds): ① stage-not-entered ("goals.md 없음 — 기획 단계 미도달", normal) ② real gap ("성공 기준 섹션 비어 있음") ③ missing knowledge list.
7. End sequence — index → log → hot → QMD. log: `[YYYY-MM-DD] PROJECT-INIT name="…" files=[…] markers=N`.

## Boundary — don't write these
architecture/domain/conventions → wiki-project-design (propose). decisions.md → wiki-project-record. Create **only the files you have content for** — never all nine up front.

## Quality check
overview has 1-line purpose + KPI · goals (if written) has a non-goals section · ≤5 `[NEEDS CLARIFICATION]`, surfaced in gap report · tech claims sourced or `⚠️ unverified` · ≥2 `[[links]]` when matches exist · index/log/hot/QMD updated.
