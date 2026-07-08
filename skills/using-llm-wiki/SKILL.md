---
name: using-llm-wiki
description: Use when working in an LLM Wiki vault — before any read or write to the wiki, when ingesting sources, answering from the knowledge base, or maintaining it.
---

# Using LLM Wiki

A personal markdown knowledge base maintained by skills. **Step 0 runs before everything.**

## Step 0 — Config Gate (mandatory, every task)

```
bash ~/.llm-wiki/scripts/resolve-vault.sh
```
- exit 0 → use stdout `VAULT_PATH` / `WIKI_DIR` / `RAW_DIR`.
- exit ≠ 0 → relay the stderr recovery line verbatim and STOP. Never guess paths.
- script missing → say "harness install.sh를 재실행하세요", stop.

## Inviolable rules

- **raw/ is immutable.** Never create, edit, or delete under `raw/` — **not even when the user explicitly asks.** Fix a source outside the vault and re-ingest. (A hook also blocks raw/ writes.)
- **Write-end sequence**, in order: page → `index.md` → `log.md` → `hot.md` → QMD refresh. Original first, derivatives after.
- **Cite** every factual claim: `(출처: [[page]])` or mark `⚠️ unverified`. Conflicts → `## Conflicts` + `status: conflict`. Archive (never delete) → `wiki/archived/`.
- Pages in Korean; filenames lowercase-kebab; links `[[wiki-link]]`.

## QMD refresh (§3-5) — write skills only

QMD is an **optional** search index over the vault; markdown is the source of truth. Read-only skills (`wiki-query`, `wiki-status`) never refresh. Stateless — qmd's own registry is the single source, no config file.

**Gate** (before any refresh/search):
1. `command -v ${QMD_CLI:-qmd}` fails → Grep fallback, report `QMD skipped: qmd CLI unavailable`.
2. `${QMD_CLI:-qmd} collection list` has no collection whose path matches `$VAULT_PATH/$WIKI_DIR` → Grep fallback + "/wiki-setup --update-qmd로 등록하세요", report `QMD skipped: collection not registered`.
3. both pass → use the matched collection name as `QMD_WIKI_COLLECTION` (works even if it isn't literally "wiki").

**Sequence** (the write-end last step, after page→index→log→hot; **once per skill run, not per file** — `update` is a full hash-scan):
```bash
${QMD_CLI:-qmd} update                  # text/BM25 index — cheap, always
${QMD_CLI:-qmd} embed                    # vector index — only when update reports new hashes need vectors
${QMD_CLI:-qmd} get "qmd://$QMD_WIKI_COLLECTION/<category>/<page>.md" -l 5   # verify (or: ls "$QMD_WIKI_COLLECTION" | grep <slug>)
```
On failure **never roll back the vault** — report QMD status separately. Skip entirely if nothing was written (hash-matched ingest, report-only lint).

**Report exactly one status string:**
`QMD refreshed: update + embed + verified` · `QMD refreshed: update only + verified` · `QMD partial: update 성공 · verify 실패 (인덱스 미반영 가능 — 단발 무시, 반복 시 --update-qmd)` · `QMD skipped: collection not registered` · `QMD skipped: qmd CLI unavailable` · `QMD failed: <짧은 에러 요약>`

**Self-healing:** a single failure needs no action — the next write skill's full-scan `update` absorbs the gap, and search falls back to Grep meanwhile. 2 consecutive failures or stale results → `/wiki-setup --update-qmd` (full reconcile).

## Routing — invoke the matching skill

`wiki-setup` init/repair · `wiki-ingest` raw source · `ingest-url` a URL · `wiki-capture` this conversation · `wiki-query` answer · `wiki-lint` audit/fix · `wiki-status` what's left · `wiki-knowledge` synthesize · `wiki-project-init` / `wiki-project-design` / `wiki-project-record` projects.

If unsure which applies, ask — don't guess.
