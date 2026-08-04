#!/usr/bin/env bash
# 단위 테스트: scripts/check-guards.sh (스펙 §5-5, 설계 docs/specs/guard-liveness-design.md)
#
# 이 스위트가 지키는 계약 3가지:
#   ① 오탐 금지 — "등록 파일 없음"은 대부분 정상이다(그 도구를 안 쓴다). 전부 경고면 무시된다.
#   ② 거짓 초록불 금지 — ~/.claude/llm-wiki-hooks.settings.json은 **머지 안내 파일**이지 등록이 아니다.
#      그걸 등록으로 세면 이 점검이 잡아야 할 바로 그 결함(0바이트)을 놓친다.
#   ③ read-only — L2 프로브는 볼트에 아무것도 쓰지 않는다.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-guards.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ok: $1"; }
no() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1 (expected [$2] got [$3])"; }
has(){ printf '%s' "$3" | grep -qF -- "$2" && ok "$1" || no "$1 (want [$2] in [$3])"; }
hasnt(){ printf '%s' "$3" | grep -qF -- "$2" && no "$1 (unwanted [$2])" || ok "$1"; }

# 격리 샌드박스: ~/.llm-wiki/scripts + 유효 볼트. 훅 본체는 repo 것을 symlink한다.
new_sandbox() {
  SANDBOX="$(mktemp -d)"
  HOME_DIR="$SANDBOX/home"; VAULT="$SANDBOX/vault"
  mkdir -p "$HOME_DIR/.llm-wiki/scripts" "$VAULT/wiki" "$VAULT/raw"
  for s in resolve-vault.sh check-guards.sh; do
    ln -sf "$REPO_ROOT/scripts/$s" "$HOME_DIR/.llm-wiki/scripts/$s"
  done
  : > "$VAULT/wiki/index.md"; : > "$VAULT/wiki/log.md"
  cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
JSON
  printf '%s\n' "$VAULT" > "$HOME_DIR/.llm-wiki/default-vault"
}
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

# 훅 본체를 <dir>에 배치 (실제 설치와 같은 모양)
place_hooks() {
  mkdir -p "$1"
  for f in run-hook.cmd wiki-protect-raw.sh wiki-validate-frontmatter.sh session-start; do
    ln -sf "$REPO_ROOT/hooks/$f" "$1/$f"
  done
}
# Cursor 등록 파일 생성 — command는 <hooksdir>/run-hook.cmd 절대참조
write_cursor_reg() { # write_cursor_reg <regfile> <hooksdir>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<JSON
{ "version": 1, "hooks": {
  "preToolUse":  [ { "command": "$2/run-hook.cmd wiki-protect-raw.sh cursor" } ],
  "postToolUse": [ { "command": "$2/run-hook.cmd wiki-validate-frontmatter.sh cursor" } ],
  "sessionStart":[ { "command": "$2/run-hook.cmd session-start cursor" } ] } }
JSON
}
run_check() { OUT="$(cd "$VAULT" && HOME="$HOME_DIR" bash "$CHECKER" ${1:+--platform "$1"} 2>"$SANDBOX/err")"; CODE=$?; ERR="$(cat "$SANDBOX/err")"; }

echo "test: 정상 등록 — L1 ok + L2 판정 확인 (양성·음성 대조군)"
new_sandbox
place_hooks "$HOME_DIR/.cursor/hooks"
write_cursor_reg "$HOME_DIR/.cursor/hooks.json" "$HOME_DIR/.cursor/hooks"
run_check
eq "exit 0" "0" "$CODE"
has "cursor L1 ok" "GUARD cursor L1 ok" "$OUT"
has "cursor L2 ok" "GUARD cursor L2 ok" "$OUT"
has "SUMMARY 라인" "SUMMARY guards=" "$OUT"
cleanup

echo "test: [핵심 회귀] 등록 파일 0바이트 → corrupt (install.sh render 결함, 2026-08-04)"
new_sandbox
place_hooks "$HOME_DIR/.cursor/hooks"
mkdir -p "$HOME_DIR/.cursor"; : > "$HOME_DIR/.cursor/hooks.json"
run_check
eq "exit 1 (degraded)" "1" "$CODE"
has "corrupt 판정" "GUARD cursor L1 corrupt" "$OUT"
has "0바이트 지목" "0바이트" "$OUT"
cleanup

echo "test: 등록 파일 JSON 파싱 실패 → corrupt"
new_sandbox
place_hooks "$HOME_DIR/.cursor/hooks"
printf '{ "hooks": ' > "$HOME_DIR/.cursor/hooks.json"
run_check
eq "exit 1" "1" "$CODE"
has "corrupt 판정" "GUARD cursor L1 corrupt" "$OUT"
cleanup

echo "test: [오탐 금지] 도구 경로 자체가 없음 → n/a, exit 0"
new_sandbox
run_check
eq "exit 0 (경고 아님)" "0" "$CODE"
hasnt "corrupt 없음" "corrupt" "$OUT"
hasnt "absent 없음" "absent" "$OUT"
has "skipped 계수" "skipped=" "$OUT"
cleanup

echo "test: 도구 경로는 있는데 등록 파일 없음 → absent"
new_sandbox
mkdir -p "$HOME_DIR/.cursor"
run_check
eq "exit 1" "1" "$CODE"
has "absent 판정" "GUARD cursor L1 absent" "$OUT"
cleanup

echo "test: 등록 command가 실재하지 않는 경로 → broken-ref"
new_sandbox
mkdir -p "$HOME_DIR/.cursor"
write_cursor_reg "$HOME_DIR/.cursor/hooks.json" "$HOME_DIR/.cursor/hooks"   # 훅 본체 미배치
run_check
eq "exit 1" "1" "$CODE"
has "broken-ref 판정" "GUARD cursor L1 broken-ref" "$OUT"
cleanup

echo "test: [거짓 초록불 방지] Claude 스니펫만 있고 settings.json에 등록 없음 → absent"
new_sandbox
mkdir -p "$HOME_DIR/.claude"
place_hooks "$HOME_DIR/.claude/hooks"
# install.sh가 만드는 머지 *안내* 파일 — 이것의 존재는 등록이 아니다
cat > "$HOME_DIR/.claude/llm-wiki-hooks.settings.json" <<JSON
{ "hooks": { "PreToolUse": [ { "hooks": [ { "type": "command", "command": "$HOME_DIR/.claude/hooks/run-hook.cmd wiki-protect-raw.sh claude" } ] } ] } }
JSON
run_check
eq "exit 1" "1" "$CODE"
has "absent 판정 (스니펫을 등록으로 세지 않는다)" "GUARD claude L1 absent" "$OUT"
has "머지 안내" "settings.json" "$OUT"
cleanup

echo "test: Claude settings.json에 실제 등록 → ok"
new_sandbox
mkdir -p "$HOME_DIR/.claude"
place_hooks "$HOME_DIR/.claude/hooks"
cat > "$HOME_DIR/.claude/settings.json" <<JSON
{ "hooks": { "PreToolUse": [ { "matcher": "Write", "hooks": [ { "type": "command", "command": "$HOME_DIR/.claude/hooks/run-hook.cmd wiki-protect-raw.sh claude" } ] } ] } }
JSON
run_check
eq "exit 0" "0" "$CODE"
has "claude L1 ok" "GUARD claude L1 ok" "$OUT"
cleanup

echo "test: Claude 마켓플레이스 캐시 — \${CLAUDE_PLUGIN_ROOT}를 플러그인 루트로 해석"
new_sandbox
PLUG="$HOME_DIR/.claude/plugins/cache/mkt/llm-wiki-harness/0.3.1"
mkdir -p "$PLUG/.claude-plugin"
place_hooks "$PLUG/hooks"
mkdir -p "$PLUG/hooks"
cat > "$PLUG/hooks/hooks.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "matcher": "Write", "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd wiki-protect-raw.sh claude" } ] } ] } }
JSON
run_check
eq "exit 0" "0" "$CODE"
has "플러그인 등록 ok" "GUARD claude L1 ok" "$OUT"
cleanup

echo "test: [read-only 계약] L2 프로브가 볼트에 아무것도 쓰지 않는다"
new_sandbox
place_hooks "$HOME_DIR/.cursor/hooks"
write_cursor_reg "$HOME_DIR/.cursor/hooks.json" "$HOME_DIR/.cursor/hooks"
BEFORE="$(find "$VAULT" | sort)"
run_check
AFTER="$(find "$VAULT" | sort)"
[ "$BEFORE" = "$AFTER" ] && ok "볼트 파일 변화 0건" || no "L2 프로브가 볼트를 변경했다"
cleanup

echo "test: Antigravity는 항상 n/a (훅 스키마 미공개)"
new_sandbox
mkdir -p "$HOME_DIR/.gemini/config"
run_check
has "antigravity n/a" "GUARD antigravity - n/a" "$OUT"
cleanup

echo "test: resolver 실패 → exit 2 (degraded와 구분한다)"
new_sandbox
rm -f "$VAULT/.wiki-config.json" "$HOME_DIR/.llm-wiki/default-vault"
OUT="$(cd "$SANDBOX" && HOME="$HOME_DIR" bash "$CHECKER" 2>/dev/null)"; CODE=$?
eq "exit 2 (점검 불가)" "2" "$CODE"
has "unknown 판정" "unknown" "$OUT"
cleanup

echo "test: ASCII locale + 한글 볼트 경로에서도 동일 (§3-9)"
new_sandbox
KVAULT="$SANDBOX/한글볼트"; mkdir -p "$KVAULT/wiki" "$KVAULT/raw"
: > "$KVAULT/wiki/index.md"; : > "$KVAULT/wiki/log.md"
cat > "$KVAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$KVAULT", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
JSON
place_hooks "$HOME_DIR/.cursor/hooks"
write_cursor_reg "$HOME_DIR/.cursor/hooks.json" "$HOME_DIR/.cursor/hooks"
OUT="$(cd "$KVAULT" && HOME="$HOME_DIR" LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 bash "$CHECKER" 2>/dev/null)"; CODE=$?
eq "exit 0" "0" "$CODE"
has "ASCII locale에서도 L1 ok" "GUARD cursor L1 ok" "$OUT"
has "ASCII locale에서도 L2 ok" "GUARD cursor L2 ok" "$OUT"
cleanup

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
