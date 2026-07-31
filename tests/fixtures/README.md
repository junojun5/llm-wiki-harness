# Hook payload fixtures

가드 훅(`wiki-protect-raw`, `wiki-validate-frontmatter`)과 `session-start`가 의존하는 **플랫폼별 stdin/stdout 스키마**의 골든 픽스처. 계약 설명의 단일 출처는 `docs/specs/spec.md` §5-4.

## 상태 — 2026-07-31 실측 완료

| 플랫폼 | 검증 | 방법 |
|---|---|---|
| Claude Code | ✅ | 단위 테스트가 이 형태로 통과 (`tests/hooks/`) |
| Codex | ✅ **실측** | codex-cli 0.145.0. 로컬 마켓플레이스에 probe 플러그인 설치 → `codex exec --dangerously-bypass-hook-trust` |
| Cursor | ✅ **실측** | cursor-agent 2026.07.23. `{ws}/.cursor/hooks.json` 및 `{ws}/.claude/settings.json` 등록 → `cursor-agent -p` |
| Antigravity | ❌ 불가 | 훅 스키마 미공개(`schemas/v1/hooks.json` 404, `agy` 0 handlers) |

모든 픽스처는 **경로가 `/PROBE_WS`로, `user_email`이 `user@example.com`으로 마스킹**돼 있다.

## 실측으로 드러난 것 — 구현이 반드시 흡수해야 함

1. **Codex `apply_patch`에는 `file_path`가 없다.** 대상 파일이 `tool_input.command`의 패치 본문(`*** Add File: …`)에 **상대경로로** 들어 있다. 이 경로를 처리하지 않으면 frontmatter 검증이 무발화하고 raw/ 가드가 통과된다.
2. **경로는 대부분 cwd 상대경로다.** Codex는 `cwd`, Cursor는 `workspace_roots[0]`(Shell 도구는 `tool_input.cwd`)를 기준으로 절대화해야 한다.
3. **차단 신호가 플랫폼마다 다르다.** Claude·Codex = stderr + `exit 2`, Cursor = `{"permission":"deny","user_message":…}` + `exit 0`.
4. **SessionStart 주입 포맷이 갈린다.** Claude·Codex = `hookSpecificOutput.additionalContext`, Cursor = `additional_context`(+`env`). Codex에 `additional_context`를 주면 `hook: SessionStart Failed`로 끝나고 주입이 무효가 된다.
5. **Cursor `tool_use_id`에는 개행이 포함**된다(두 ID 연결) — 단순 파싱 시 주의.
6. **Cursor는 Claude 포맷 등록도 실행한다.** `cursor-hooks/sessionstart.json`·`pretooluse-write.json`은 `{ws}/.claude/settings.json`에 **Claude 포맷**으로 등록해 얻은 페이로드다 — 등록 포맷과 무관하게 페이로드는 항상 Cursor 스키마다. 훅 설정 7개 소스가 병합되므로 Claude 설정과 Cursor 설정에 같은 훅을 **중복 등록하면 2회 발화**한다.

## 재캡처 절차 (CLI 메이저 버전 변경 시)

1. probe 번들을 만든다 — 훅 등록 JSON의 command만 `probe-hook.sh <label>`로 바꾼 사본. **레포의 실제 훅 파일은 건드리지 않는다.**
2. Codex: `.agents/plugins/marketplace.json`을 포함한 번들을 `codex plugin marketplace add <path>` → `codex plugin add <plugin>@<marketplace>` → `codex exec --skip-git-repo-check -C <ws> -s workspace-write --dangerously-bypass-hook-trust "<프롬프트>"`.
   ⚠️ trust 없이 실행하면 훅이 **경고 없이 조용히 no-op** 한다(캡처 0건). 플러그인 매니페스트의 `hooks` 키만으로는 발화하지 않는다.
3. Cursor: `{ws}/.cursor/hooks.json`에 절대경로 command로 등록 → `cursor-agent -p --workspace <ws> --trust --force "<프롬프트>"`.
   ⚠️ `.cursor-plugin/plugin.json`의 `hooks` 키는 **소비되지 않는다**(내부 `getPluginHooks` 미호출). `--plugin-dir`·`~/.cursor/plugins/local/` 모두 훅이 발화하지 않으므로 설정 파일 경로를 써야 한다.
4. 캡처본의 경로·이메일을 마스킹하고 `_status`를 갱신해 커밋한다.
5. 끝나면 환경을 원복한다 — `codex plugin remove <p>@<m>`, `codex plugin marketplace remove <m>`, `~/.codex/config.toml` 복원, 플러그인 캐시 삭제.
