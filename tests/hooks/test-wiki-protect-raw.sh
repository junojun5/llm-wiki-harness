#!/usr/bin/env bash
# 단위 테스트: hooks/wiki-protect-raw.sh (하네스 스펙 §5-2)
# raw/ 수정 차단, 삭제(rm) 허용, 비볼트 통과. 플랫폼별 차단 신호:
#   claude/codex → stderr + exit 2 ; cursor → stdout {"permission":"deny"} + exit 0
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/wiki-protect-raw.sh"
PASS=0; FAIL=0

new_sandbox() {
  SANDBOX="$(mktemp -d)"
  # 격리된 ~/.llm-wiki/scripts/resolve-vault.sh (repo 스크립트로 symlink)
  mkdir -p "$SANDBOX/home/.llm-wiki/scripts"
  ln -sf "$REPO_ROOT/scripts/resolve-vault.sh" "$SANDBOX/home/.llm-wiki/scripts/resolve-vault.sh"
  # 유효 볼트
  VAULT="$SANDBOX/vault"; mkdir -p "$VAULT/wiki" "$VAULT/raw"
  : > "$VAULT/wiki/index.md"; : > "$VAULT/wiki/log.md"
  cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
JSON
  printf '%s\n' "$VAULT" > "$SANDBOX/home/.llm-wiki/default-vault"
}
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

# 훅 실행: $1=platform, $2=stdin JSON. CWD는 볼트 안(resolve가 CWD로 찾도록), HOME 격리.
run_hook() {
  OUT="$(cd "$VAULT" && printf '%s' "$2" | HOME="$SANDBOX/home" bash "$HOOK" "$1" 2>"$SANDBOX/err")"
  CODE=$?; ERR="$(cat "$SANDBOX/err")"
}
ok() { PASS=$((PASS+1)); echo "  ok: $1"; }
no() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
eq() { [ "$2" = "$3" ] && ok "$1" || { no "$1 (expected [$2] got [$3])"; }; }
has(){ printf '%s' "$3" | grep -qF -- "$2" && ok "$1" || no "$1 (want [$2] in [$3])"; }

echo "test: raw/ Write 차단 (claude → exit 2 + stderr)"
new_sandbox
run_hook claude "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT/raw/articles/x.md\"}}"
eq "exit 2" "2" "$CODE"; has "stderr 안내" "raw/" "$ERR"
cleanup

echo "test: wiki/ Write 통과 (exit 0)"
new_sandbox
run_hook claude "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT/wiki/concepts/x.md\"}}"
eq "exit 0" "0" "$CODE"
cleanup

echo "test: raw/ 대상 rm 명령은 허용 (exit 0)"
new_sandbox
run_hook claude "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm $VAULT/raw/old.md\"}}"
eq "exit 0 (rm 허용)" "0" "$CODE"
cleanup

echo "test: raw/ 대상 echo 리다이렉트 Bash는 차단 (exit 2)"
new_sandbox
run_hook claude "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hi > $VAULT/raw/x.md\"}}"
eq "exit 2" "2" "$CODE"
cleanup

echo "test: 비볼트(resolver 실패) → 통과 (exit 0)"
new_sandbox
rm -f "$SANDBOX/home/.llm-wiki/default-vault"
OUT="$(cd "$SANDBOX" && printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SANDBOX/elsewhere/x.md\"}}" | HOME="$SANDBOX/home" bash "$HOOK" claude 2>/dev/null)"; CODE=$?
eq "exit 0 (비볼트 통과)" "0" "$CODE"
cleanup

echo "test: cursor 플랫폼 — raw/ Write 차단은 JSON permission:deny + exit 0"
new_sandbox
run_hook cursor "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT/raw/x.md\"}}"
eq "exit 0 (cursor)" "0" "$CODE"
# stdout이 유효 JSON이고 permission=deny
python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['permission']=='deny'" "$OUT" 2>/dev/null && ok "permission:deny JSON" || no "permission:deny JSON (got [$OUT])"
cleanup

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
