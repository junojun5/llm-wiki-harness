#!/usr/bin/env bash
# 단위 테스트: hooks/wiki-validate-frontmatter.sh (하네스 스펙 §5-3)
# wiki/ 하위 .md 쓰기마다 validate-frontmatter.sh를 wrapper로 호출. 위반 시 exit 2 + stderr.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/wiki-validate-frontmatter.sh"
PASS=0; FAIL=0

new_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/home/.llm-wiki/scripts"
  ln -sf "$REPO_ROOT/scripts/resolve-vault.sh"      "$SANDBOX/home/.llm-wiki/scripts/resolve-vault.sh"
  ln -sf "$REPO_ROOT/scripts/validate-frontmatter.sh" "$SANDBOX/home/.llm-wiki/scripts/validate-frontmatter.sh"
  VAULT="$SANDBOX/vault"; mkdir -p "$VAULT/wiki/knowledge" "$VAULT/raw"
  : > "$VAULT/wiki/index.md"; : > "$VAULT/wiki/log.md"
  cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
JSON
  printf '%s\n' "$VAULT" > "$SANDBOX/home/.llm-wiki/default-vault"
}
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
trap cleanup EXIT
run_hook() {
  OUT="$(cd "$VAULT" && printf '%s' "$1" | HOME="$SANDBOX/home" bash "$HOOK" 2>"$SANDBOX/err")"
  CODE=$?; ERR="$(cat "$SANDBOX/err")"
}
ok(){ PASS=$((PASS+1)); echo "  ok: $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1 (exp [$2] got [$3])"; }

VALID='---
title: "유효"
category: knowledge
tags: [a]
sources: ["raw/x.md"]
created: 2026-06-25
updated: 2026-06-25
summary: "요약"
status: verified
base_confidence: 0.8
---
본문.'

echo "test: 유효 wiki/.md 쓰기 → exit 0"
new_sandbox
printf '%s' "$VALID" > "$VAULT/wiki/knowledge/good.md"
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/wiki/knowledge/good.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: 필수키 누락 wiki/.md → exit 2 + stderr"
new_sandbox
printf '%s' "${VALID/summary: \"요약\"$'\n'/}" > "$VAULT/wiki/knowledge/bad.md"
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/wiki/knowledge/bad.md\"}}"
eq "exit 2" "2" "$CODE"
[ -n "$ERR" ] && ok "stderr 출력" || no "stderr 출력"; cleanup

echo "test: 클래스③ 원장(index.md) → exit 0 (validator 면제)"
new_sandbox
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/wiki/index.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: wiki/ 밖 경로 → 통과 (exit 0)"
new_sandbox
run_hook "{\"tool_input\":{\"file_path\":\"$VAULT/raw/x.md\"}}"
eq "exit 0" "0" "$CODE"; cleanup

echo "test: 비볼트 → 통과 (exit 0)"
new_sandbox; rm -f "$SANDBOX/home/.llm-wiki/default-vault"
OUT="$(cd "$SANDBOX" && printf '%s' "{\"tool_input\":{\"file_path\":\"$SANDBOX/x.md\"}}" | HOME="$SANDBOX/home" bash "$HOOK" 2>/dev/null)"; CODE=$?
eq "exit 0" "0" "$CODE"; cleanup

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
