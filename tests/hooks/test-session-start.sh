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
OUT="$(cd "$SB" && HOME="$HOMESB" bash "$HOOK" claude </dev/null 2>"$SB/err")"; CODE=$?
[ "$CODE" = 0 ] && ok "exit 0" || no "exit 0 (got $CODE)"
[ -L "$HOMESB/.llm-wiki/scripts/resolve-vault.sh" ] && ok "부트스트랩: resolve-vault.sh symlink 생성" || no "부트스트랩 symlink 없음"
[ -L "$HOMESB/.llm-wiki/scripts/validate-frontmatter.sh" ] && ok "부트스트랩: validate-frontmatter.sh symlink" || no "validate symlink 없음"
[ -z "$OUT" ] && ok "비볼트 → 주입 없음(빈 stdout)" || no "비볼트인데 출력 있음: $OUT"

echo "test: 볼트 CWD (claude) — 주입 발생"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" claude </dev/null 2>/dev/null)"
printf '%s' "$OUT" | python3 -c "import json,sys;json.load(sys.stdin)" 2>/dev/null && ok "유효 JSON" || no "invalid JSON"
jpath "additionalContext에 Config Gate" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"
jpath "additionalContext에 raw 불변" "d['hookSpecificOutput']['additionalContext']" "raw/ 는 불변" "$OUT"
jpath "EXTREMELY_IMPORTANT 래핑" "d['hookSpecificOutput']['additionalContext']" "EXTREMELY_IMPORTANT" "$OUT"
jpath "hookEventName=SessionStart" "d['hookSpecificOutput']['hookEventName']" "SessionStart" "$OUT"

echo "test: 볼트 하위 디렉토리 CWD — 여전히 주입"
mkdir -p "$VAULT/wiki/summaries"
OUT="$(cd "$VAULT/wiki/summaries" && HOME="$HOMESB" bash "$HOOK" claude </dev/null 2>/dev/null)"
jpath "하위 CWD도 주입" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"

# Codex는 Claude와 동일 포맷이다 (2026-07-31 실측 — §5-1).
# {"additional_context":…}를 내보내면 `hook: SessionStart Failed`로 주입이 조용히 무효가 된다.
echo "test: 볼트 CWD (codex) — Claude와 동일한 hookSpecificOutput 포맷"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" codex </dev/null 2>/dev/null)"
jpath "codex additionalContext" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"
jpath "codex hookEventName=SessionStart" "d['hookSpecificOutput']['hookEventName']" "SessionStart" "$OUT"
printf '%s' "$OUT" | python3 -c "import json,sys;sys.exit(0 if 'additional_context' not in json.load(sys.stdin) else 1)" \
  && ok "codex에 additional_context 없음" || no "codex에 additional_context가 남아 있음"

echo "test: 볼트 CWD (cursor) — additional_context + env(절대경로)"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" cursor </dev/null 2>/dev/null)"
jpath "cursor additional_context" "d['additional_context']" "raw/ 는 불변" "$OUT"
jpath "cursor env.LLM_WIKI_RESOLVER 절대경로" "d['env']['LLM_WIKI_RESOLVER']" "$HOMESB/.llm-wiki/scripts/resolve-vault.sh" "$OUT"
printf '%s' "$OUT" | python3 -c "import json,sys;sys.exit(0 if not json.load(sys.stdin)['env']['LLM_WIKI_RESOLVER'].startswith('~') else 1)" \
  && ok "cursor env에 틸드 없음(미확장 방지)" || no "cursor env가 틸드로 시작"

# 페이로드 판별 — Cursor는 Claude 포맷 등록도 실행하므로 argv가 claude인 채 발화할 수 있다 (§5-1).
echo "test: 페이로드에 cursor_version → argv가 claude여도 cursor 포맷"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" claude < "$REPO_ROOT/tests/fixtures/cursor-hooks/sessionstart.json" 2>/dev/null)"
jpath "cursor 포맷으로 전환" "d['additional_context']" "Config Gate" "$OUT"
jpath "env도 함께 출력" "d['env']['LLM_WIKI_RESOLVER']" "resolve-vault.sh" "$OUT"

echo "test: Codex 골든 픽스처(cursor_version 없음) → codex 포맷 유지"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$HOOK" codex < "$REPO_ROOT/tests/fixtures/codex-hooks/sessionstart.json" 2>/dev/null)"
jpath "codex 포맷 유지" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"

# stdin 회귀 — 훅은 페이로드를 읽되 **절대 무한 대기하지 않아야** 한다.
# 닫히지 않은 파이프를 상속하면(수동 실행·래퍼 경유) 세션 시작 자체가 멈춘다.
if command -v timeout >/dev/null 2>&1; then
  echo "test: 열린 idle 파이프를 stdin으로 받아도 블로킹하지 않는다"
  FIFO="$SB/idle.pipe"; rm -f "$FIFO"; mkfifo "$FIFO"
  ( sleep 30 > "$FIFO" & )   # 파이프를 열어두고 아무것도 쓰지 않는 writer
  OUT="$(timeout 10 bash -c "cd '$VAULT' && HOME='$HOMESB' bash '$HOOK' claude < '$FIFO'" 2>/dev/null)"; CODE=$?
  [ "$CODE" != 124 ] && ok "타임아웃 없이 종료 (exit $CODE)" || no "여전히 블로킹(124)"
  jpath "블로킹 없이도 주입은 정상" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"
  rm -f "$FIFO"
else
  echo "test: (skip) timeout 명령 없음 — stdin 블로킹 회귀 테스트 생략"
fi

# run-hook.cmd 폴리글랏 런처 — Unix 분기가 <hook> [platform] 을 그대로 위임하는지.
# (Windows/cmd 분기는 macOS·Linux에서 실행할 수 없어 정적 검토로만 확인 — hooks/run-hook.cmd 주석 참조)
echo "test: run-hook.cmd Unix 분기 — 플랫폼 인자가 훅에 그대로 전달"
LAUNCHER="$REPO_ROOT/hooks/run-hook.cmd"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$LAUNCHER" session-start codex </dev/null 2>/dev/null)"
jpath "런처 경유 codex 포맷" "d['hookSpecificOutput']['additionalContext']" "Config Gate" "$OUT"
OUT="$(cd "$VAULT" && HOME="$HOMESB" bash "$LAUNCHER" session-start cursor </dev/null 2>/dev/null)"
jpath "런처 경유 cursor 포맷" "d['additional_context']" "Config Gate" "$OUT"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
