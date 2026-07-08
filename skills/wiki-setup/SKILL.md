---
name: wiki-setup
description: Use when initializing a new LLM Wiki vault or repairing a broken vault configuration. Must run before any other wiki skill. Sets up the vault config and the global vault pointer.
---

# wiki-setup

Initializes or repairs a vault. **The only skill that runs before the Config Gate exists** — it creates the config the gate reads, so it does NOT call resolve-vault.sh itself.

## Modes
- `/wiki-setup` — interactive init.
- `/wiki-setup --vault <path> [--yes]` — non-interactive.
- `/wiki-setup --update-path` — re-point to a moved/renamed vault (updates config + pointer).
- `/wiki-setup --repair` — re-create missing config/dirs/templates.
- `/wiki-setup --update-qmd` — full QMD reconcile: register the collection if missing (`collection add … --name wiki`), then `qmd update` (+ `embed` if update reports new hashes). Use after manual edits/moves outside a skill, or after repeated QMD staleness (§3-5 self-healing escalation). Runs the §3-5 gate first; if qmd is unavailable, says so and stops.

**Idempotent — existence-only.** Every file/dir below: create if missing, otherwise leave untouched. Never overwrite existing content even if the format looks old — diagnosing stale format is `wiki-lint --fix`'s job, not setup's.

## Workflow
1. Ask for the vault absolute path (or use `--vault`).
2. Propose `raw_dir="raw"`, `wiki_dir="wiki"` → confirm.
3. Write `<vault>/.wiki-config.json` (schema minimalism — answers only "where is the vault"; no QMD/flags/feature keys):
   ```json
   { "version": 1, "vault": { "path": "<abs>", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "YYYY-MM-DD" }
   ```
4. Write global pointer `~/.llm-wiki/default-vault` = vault absolute path, one line. If it exists and differs, show `old → new` and confirm before overwriting (no `.bak` — re-run `--update-path` to revert). **Under `--yes`, never silently overwrite a pointer that targets a *different* vault — stop and tell the user to run `--update-path` explicitly** (non-interactive must not hijack another vault's pointer). This is what lets skills resolve the vault from any directory.
5. Create fixed dirs if missing: `wiki/concepts/ wiki/knowledge/ wiki/entities/ wiki/projects/ wiki/meetings/ wiki/archived/`. **Do NOT create `wiki/summaries/*` subfolders** — ingest creates those to mirror `raw/` (YAGNI). Do not create raw/ subfolders, benchmark/, or meta/.
6. `wiki/index.md` — if missing, initial template with empty category sections: summaries / concepts / knowledge / entities / projects.
7. `wiki/log.md` — if missing, seed plaintext with a dated `INIT — vault created` entry (ledger: no frontmatter).
8. `wiki/hot.md` — if missing, this canonical template (single source; other skills cite "§4-1 Step 8 template"):
   ```
   ---
   title: Hot Cache
   updated: YYYY-MM-DD
   ---
   # Hot Cache
   *A ~500-word semantic snapshot of recent activity.*
   ## Recent Activity
   - [TIMESTAMP] INIT — vault created
   ## Active Threads
   *None yet.*
   ## Key Takeaways
   *None yet.*
   ## Flagged Contradictions
   *None yet.*
   ```
   Repair exception: if `log.md` exists but `hot.md` is missing, rebuild Recent Activity from log.md's last ~10 entries.
9. QMD — ask "qmd가 설치돼 있나요?"
   - installed → `${QMD_CLI:-qmd} collection add <vault>/<wiki_dir> --name wiki` (skip if `qmd collection list` already shows the path), then `qmd update`. Store QMD config nowhere — qmd's own registry is the single source. Empty vault: `update` only, no `embed`.
   - not installed → "Grep fallback으로 동작합니다. 설치 후 `/wiki-setup --update-qmd` 가능."
10. `<vault>/.manifest.json` — if missing, `{ "version": 1 }`.
11. `<vault>/.wiki-config.example.json` — empty template with the absolute path removed (git-tracked).
12. If the vault is a git repo, ensure `.gitignore` lists `.wiki-config.json` (machine-specific absolute path); the `.example` stays tracked.
13. Print a sanity-check list of everything created vs. confirmed-existing.

install.sh deploys skills/scripts/hooks to the platform; wiki-setup only configures the *vault*.
