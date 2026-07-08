---
name: wiki-status
description: Use when the user wants to know what raw files are pending ingest, what was recently processed, or the overall state of the wiki — "wiki status", "뭐 쌓여있어", "ingest 뭐 남았어", "what's left", "/wiki-status".
---

# wiki-status

A **read-only** progress report: **"what's left," not "what's broken."** Config Gate first.

## Boundary with wiki-lint (strict)
status answers *what's left to do* — pending ingest, recent activity, size footprint. It does **NOT** report quality problems: orphans, broken links, conflicts, `⚠️ unverified` claims are **wiki-lint's domain — never report them here.** Even for detection-overlapping items (cleanable raw, manifest↔page integrity), status reports **counts/lists only** and points to `/wiki-lint` for the judgment and the fix. **status never deletes, fixes, or proposes deletion.** It's read-only — it writes nothing (not even a log line).

## Workflow
0. Config Gate. 0.5 Read `hot.md` (recent-activity context).
1. Read `.manifest.json`: last-ingest timestamp, total sources, total pages. No manifest → "아직 ingest된 파일 없음. /wiki-ingest를 먼저 실행하세요" → step 4.
2. Scan `raw/` vs manifest by **`content_hash` (never mtime)**:
   - not in manifest → 📥 미처리 (pending ingest)
   - in manifest, hash differs → 🔄 갱신 필요
   - in manifest, hash same → skip
   - in manifest, ingested + `ingested_at` >14d → 🗑️ 삭제 대기 — **report count/list only; the judgment and deletion belong to wiki-lint (§4-6 check 15).**
3. **Token-footprint estimate** (Glob `wiki/` sizes; tier from frontmatter grep):
   - per tier (core/supporting/peripheral): N pages → ~K tokens (≈ bytes/4; label "추정치" — Korean + markdown skew it)
   - index-only-pass estimate; normal-query estimate (index + top 5 pages)
   - if the **full-load total** (all tiers) > 100000 → ⚠️ "전체 로드 시 100K 초과 — wiki-query index-only 모드 권장" (only the full-load total trips the threshold; the per-pass estimates are reference-only).
4. Read `log.md` last 5 entries.
5. **Report:** `## 개요` (pages / sources / last ingest) · `## Raw 현황` (📥 🔄 🗑️ counts + lists) · `## 토큰 풋프린트` (tier table + pass estimates) · `## 최근 작업` (log tail).
6. **What to Do Next** (≤5 prioritized actions, only the applicable ones):
   1. 📥 미처리 raw N개 → `/wiki-ingest`
   2. 🔄 갱신 필요 raw N개 → `/wiki-ingest`
   3. 🗑️ 삭제 대기 raw N개 → `/wiki-lint --fix`
   4. 🩺 wiki-lint 마지막 실행 {date} — grep the last `LINT` line in log.md (may be older than the last-5 tail); if >30 days → "점검 권장".
   None apply → "✅ Wiki가 최신 상태입니다. 처리 대기 항목 없음."
