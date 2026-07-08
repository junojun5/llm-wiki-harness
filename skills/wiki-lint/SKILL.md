---
name: wiki-lint
description: Use when the user wants to audit, lint, or check the wiki for problems — orphans, broken links, format errors, conflicts, stale pages, PII, cleanable raw files — or asks "lint the wiki", "/wiki-lint", "wiki 점검/audit".
---

# wiki-lint

Audits the vault and (optionally) fixes mechanical issues. Config Gate first. **Report-only runs are read-only** (only a `log.md` LINT line is appended); `--fix` is the only mode that writes pages.

## Use the canonical scripts — do NOT reinvent
Deterministic checks come from the **single code source** (same scripts the validator hook uses, so results never drift). Don't hand-roll `rg`/grep link scans:
- `~/.llm-wiki/scripts/build-link-graph.sh <WIKI_DIR>` → **one O(N) pass** producing orphans, broken links, concept gaps, relationship target/self issues (checks 1, 2, 9, 12). Never per-file grep (O(N×M)).
- `~/.llm-wiki/scripts/validate-frontmatter.sh <file>` → per-page class-aware frontmatter check (check 3). Run across pages; it applies the §3-3 document-class rules (ledger files exempt, changes/troubleshooting enums).

## 17 checks (group output by severity 🔴 ERROR → 🟡 REVIEW → ℹ️ SOFT)
| # | key | check | sev | source |
|--|--|--|--|--|
|1|orphans|inbound 0 (excl. index/log/hot)|🟡|graph|
|2|broken_links|`[[link]]` target missing|🟡|graph|
|3|format_errors|missing required keys / base_confidence out of [0,1]|🔴|validate-fm|
|4|missing_summary|no `summary:` / >400 chars|ℹ️|grep|
|5|unprocessed|raw/ not in manifest|🟡|raw vs manifest|
|6|index_missing|page not in index.md|🟡|index|
|7|unverified|inline `⚠️ unverified`|ℹ️|grep|
|8|conflicts|`status: conflict` (open items ≥1)|🟡|frontmatter|
|9|concept_gaps|referenced-but-absent (same data as #2, "to create")|🟡|graph|
|10|stale|`updated` older than newest source; verified+stale = higher priority|🟡|frontmatter+manifest|
|11|pii_exposure|keyword+real value (api_key:/token:/password:…); skip placeholders + `<!-- lint-ignore: pii -->`|ℹ️|grep|
|12|relationship_issues|type not in enum / broken target / self-ref|🔴|graph+fm|
|13|provenance_drift|recompute from `^[inferred]`/`^[ambiguous]` markers; Δ≥0.20, ambiguous>0.15, inferred>0.40 unsourced, or block+markers both absent on conversation/inferred page|ℹ️|body markers|
|14|supersession_issues|`superseded_by` target missing / not archived|🟡|frontmatter|
|15|raw_deletable|all 3: content_hash in manifest + summaries page exists + ingested_at >14d|ℹ️|manifest|
|16|change_proposal_issues|applied w/o decisions link · proposed >14d · broken target · stray applied/rejected in changes/ root|🟡|projects/*/changes|
|17|manifest_integrity|manifest pages_created path missing on disk|🟡|manifest|

Attach a **next-action line** to each group, especially un-fixable ones (conflict→"adopt a source then update §3-3 resolved", PII→"redact / .gitignore", unprocessed→"/wiki-ingest <path>", orphan→"link or archive").

## `--fix` model — dry-run default, differentiated apply
- `--fix` alone = **dry-run**: show what would change, write nothing.
- Reversible/low-risk (add missing format field, register in index.md, relationship type typo→`related_to`): one batch confirm; `--fix --yes` auto-applies.
- **Irreversible (check 15 raw deletion): ALWAYS individual confirm — `--yes` does NOT skip it.** Re-verify the summaries/ page exists before deleting.
- Not auto-fixable (judgment): 1, 2, 9, 12 / needs ingest: 5 / value judgment: 3's base_confidence range.
- **Frontmatter edits are append-only**: add a missing field at the end; preserve existing field order/comments. Never re-serialize the YAML (avoids churn). Value changes are never auto-applied.

## Close-out
- `log.md`: `[YYYY-MM-DD] LINT issues_found=N orphans=A broken_links=B format_errors=C missing_summary=D unprocessed=E index_missing=F unverified=G conflicts=H concept_gaps=I stale=J pii_exposure=K relationship_issues=L provenance_drift=M supersession_issues=N raw_deletable=O change_proposal_issues=P manifest_integrity=Q`
- QMD refresh **only if `--fix` actually wrote** (report-only is read-only, no refresh).
