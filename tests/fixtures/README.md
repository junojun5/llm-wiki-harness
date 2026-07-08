# Hook payload fixtures (§9-6)

가드 훅(`wiki-protect-raw`, `wiki-validate-frontmatter`)과 `session-start`가 의존하는 **플랫폼별 stdin/stdout 스키마**의 골든 픽스처.

## 상태

| 플랫폼 | stdin 스키마 | 상태 |
|---|---|---|
| Claude Code | `{tool_name, tool_input:{file_path\|command, …}}` · 출력 exit 2 / `hookSpecificOutput.additionalContext` | ✅ 검증 — 단위 테스트가 이 형태로 통과 (`tests/hooks/`) |
| Codex | `~/.codex/hooks.json` 등록 · `/hooks` trust 필요 | ⚠️ **미검증** — `codex-hooks/expected-*.json`은 배포 설계 §12 문서 기반 *예상치*. 실제 CLI로 캡처 후 교체 필요 |
| Cursor | `.cursor/hooks.json` 등록 · `preToolUse`→`permission:deny` / `sessionStart`→`additional_context`+`env` | ⚠️ **미검증** — `cursor-hooks/expected-*.json`은 배포 설계 §13 문서 기반 *예상치* |

가드 훅은 이 불확실성을 **다중 키 탐색**(`file_path`/`path`/`filePath`/`command`/`cmd` 등)으로 보수적으로 흡수하도록 작성돼 있으나, 필드명이 모두 빗나가면 보호가 조용히 무력화될 수 있다 — 그래서 실측 픽스처가 필요하다.

## 실제 픽스처 캡처 절차

1. 해당 플랫폼 훅 등록(`hooks-codex.json` / `hooks-cursor.json`)에서 명령을 임시로 `probe-hook.sh`로 교체:
   ```
   PROBE_OUT_DIR=tests/fixtures/codex-hooks  <hooks-dir>/probe-hook.sh pretooluse-write
   ```
2. 각 이벤트를 한 번씩 트리거:
   - `PreToolUse` — `apply_patch` / `Edit` / `Write`
   - `PostToolUse` — `apply_patch` / `Edit` / `Write`
   - `SessionStart` — `startup` / `resume` / `clear` / `compact`
   - (Cursor) `preToolUse`(`tool_name`·파일경로 필드명) / `sessionStart`
3. 생성된 `*.captured.json`을 검토·정규화해 골든 픽스처로 커밋하고, 가드 훅의 다중 키 탐색이 실제 필드명을 포함하는지 단위 테스트에 추가.
4. trust 검증: `/hooks`에서 `wiki-protect-raw`·`wiki-validate-frontmatter`·`session-start`가 trusted로 보이는지, trust 후 `raw/` 쓰기가 실제 차단되는지 스모크.
