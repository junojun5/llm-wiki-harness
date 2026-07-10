#!/usr/bin/env bash
# 단위 테스트: hooks/session-start —
#   ① ~/.llm-wiki/scripts 부트스트랩(없으면 배포본 scripts/에서 symlink) — 마켓플레이스 자가치유
#   ② 볼트 게이트: CWD가 볼트 안일 때만 using-llm-wiki 주입, 비볼트 세션엔 주입 없음(스팸 방지)
# HOME을 샌드박스로 격리해 실제 ~/.llm-wiki를 건드리지 않는다.
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-start"
PASS=0; FAIL=0
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
ok(){ PASS=$((PASS+1)); echo "  ok: $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
jpath(){ # desc pypath needle json
  local v; v="$(printf '%s' "$4" | python3 -c "import json,sys;d=json.load(sys.stdin);print($2)" 2>/dev/null)"
  printf '%s' "$v" | grep -qF -- "$3" && ok "$1" || no "$1 (want [$3] at $2)"
}

HOMESB="$SB/home"; mkdir -p "$HOMESB"
VAULT="$SB/vault"; mkdir -p "$VAULT/wiki"
printf '{"version":1,"vault":{"path":"%s","wiki_dir":"wiki","raw_dir":"raw"},"created":"2026-01-01"}\n' "$VAULT" > "$VAULT/.wiki-config.json"
printf '# Index\n' > "$VAULT/wiki/index.md"
printf 'log\n' > "$VAULT/wiki/log.md"

echo "test: 비볼트 CWD — 부트스트랩만, 주입 없음"
OUT="$(cd "$SB" && HOME="$HOMESB" bash "$HOOK" claude 2>"$SB/err")"; CODE=$?
[ "$CODE" = 0 ] && ok "exit 0" || no "exit 0 (got $CODE)"
[ -L "$HOMESB/.llm-wiki/scripts/resolve-vault.sh" ] && ok "부트스트랩: resolve-vault.sh symlink 생성" || no "부트스트랩 symlink 없음"
[ -L "$HOMESB/.llm-wiki/scripts/validate-frontmatter.sh" ] && ok "부트스트랩: validate-frontmatter.sh symlink" || no "validate symlink 없음"
[ -z "$OUT" ] && ok "비볼트 → 주입 없음(빈 stdout)" || no "비볼트인데 출력 있음: $OUT"

echo "test: 볼트 CWD (claude) — 주입 발생"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" claude 2>/dev/null)"
printf '%s' "$OUT" | python3 -c "import json,sys;json.load(sys.stdin)" 2>/dev/null && ok "유효 JSON" || no "invalid JSON"
jpath "additionalContext에 Config Gate" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"
jpath "additionalContext에 raw 불변" "d['hookSpecificOutput']['additionalContext']" "raw/ 는 불변" "$OUT"
jpath "EXTREMELY_IMPORTANT 래핑" "d['hookSpecificOutput']['additionalContext']" "EXTREMELY_IMPORTANT" "$OUT"
jpath "hookEventName=SessionStart" "d['hookSpecificOutput']['hookEventName']" "SessionStart" "$OUT"

echo "test: 볼트 하위 디렉토리 CWD — 여전히 주입"
mkdir -p "$VAULT/wiki/summaries"
OUT="$(cd "$VAULT/wiki/summaries" && HOME="$HOMESB" bash "$HOOK" claude 2>/dev/null)"
jpath "하위 CWD도 주입" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"

echo "test: 볼트 CWD (codex) — additional_context"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" codex 2>/dev/null)"
jpath "codex additional_context" "d['additional_context']" "Config Gate" "$OUT"

echo "test: 볼트 CWD (cursor) — additional_context + env"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" cursor 2>/dev/null)"
jpath "cursor additional_context" "d['additional_context']" "raw/ 는 불변" "$OUT"
jpath "cursor env.LLM_WIKI_RESOLVER" "d['env']['LLM_WIKI_RESOLVER']" "resolve-vault.sh" "$OUT"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
