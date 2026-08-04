#!/usr/bin/env bash
# 단위 테스트: hooks/wiki-protect-raw.sh (하네스 스펙 §5-2)
# raw/ 수정 차단, 삭제(rm) 허용, 비볼트 통과. 플랫폼별 차단 신호:
#   claude/codex → stderr + exit 2 ; cursor → stdout {"permission":"deny"} + exit 0
set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/wiki-protect-raw.sh"
# 페이로드·config의 경로는 python3가 **값으로** 받는다 — 네이티브 형태여야 한다 (MSYS 주의)
. "$REPO_ROOT/tests/lib/paths.sh"
PASS=0; FAIL=0

new_sandbox() {
  SANDBOX="$(mktemp -d)"
  # 격리된 ~/.llm-wiki/scripts/resolve-vault.sh (repo 스크립트로 symlink)
  mkdir -p "$SANDBOX/home/.llm-wiki/scripts"
  ln -sf "$REPO_ROOT/scripts/resolve-vault.sh" "$SANDBOX/home/.llm-wiki/scripts/resolve-vault.sh"
  # 유효 볼트
  VAULT="$SANDBOX/vault"; mkdir -p "$VAULT/wiki" "$VAULT/raw"
  VAULT_N="$(native_path "$VAULT")"
  : > "$VAULT/wiki/index.md"; : > "$VAULT/wiki/log.md"
  cat > "$VAULT/.wiki-config.json" <<JSON
{ "version": 1, "vault": { "path": "$VAULT_N", "wiki_dir": "wiki", "raw_dir": "raw" }, "created": "2026-06-25" }
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
run_hook claude "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT_N/raw/articles/x.md\"}}"
eq "exit 2" "2" "$CODE"; has "stderr 안내" "raw/" "$ERR"
cleanup

echo "test: wiki/ Write 통과 (exit 0)"
new_sandbox
run_hook claude "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT_N/wiki/concepts/x.md\"}}"
eq "exit 0" "0" "$CODE"
cleanup

echo "test: raw/ 대상 rm 명령은 허용 (exit 0)"
new_sandbox
run_hook claude "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm $VAULT_N/raw/old.md\"}}"
eq "exit 0 (rm 허용)" "0" "$CODE"
cleanup

echo "test: raw/ 대상 echo 리다이렉트 Bash는 차단 (exit 2)"
new_sandbox
run_hook claude "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo hi > $VAULT_N/raw/x.md\"}}"
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
run_hook cursor "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT_N/raw/x.md\"}}"
eq "exit 0 (cursor)" "0" "$CODE"
# stdout이 유효 JSON이고 permission=deny
PYTHONUTF8=1 python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['permission']=='deny'" "$OUT" 2>/dev/null && ok "permission:deny JSON" || no "permission:deny JSON (got [$OUT])"
cleanup

# ── 상대경로 해석 (§5-4 실측: Codex·Cursor 경로는 대부분 cwd 상대경로) ──────────
# 절대경로 전제 가드는 이 케이스들을 조용히 통과시켰다.

echo "test: apply_patch 상대경로가 raw/ 를 가리키면 차단 (exit 2)"
new_sandbox
run_hook codex "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: raw/articles/x.md\n+body\n*** End Patch\n\"}}"
eq "exit 2" "2" "$CODE"; has "stderr 안내" "raw/" "$ERR"
cleanup

echo "test: apply_patch 상대경로가 wiki/ 를 가리키면 통과 (exit 0)"
new_sandbox
run_hook codex "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: wiki/concepts/x.md\n+body\n*** End Patch\n\"}}"
eq "exit 0" "0" "$CODE"
cleanup

echo "test: Write 상대경로가 raw/ 를 가리키면 차단 (cwd 기준 절대화)"
new_sandbox
run_hook codex "{\"tool_name\":\"Write\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"file_path\":\"raw/x.md\"}}"
eq "exit 2" "2" "$CODE"
cleanup

echo "test: Write 상대경로가 wiki/ 를 가리키면 통과"
new_sandbox
run_hook codex "{\"tool_name\":\"Write\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"file_path\":\"wiki/concepts/x.md\"}}"
eq "exit 0" "0" "$CODE"
cleanup

echo "test: Cursor는 cwd 없이 workspace_roots[0] 기준으로 절대화 (§5-4)"
new_sandbox
run_hook cursor "{\"tool_name\":\"Write\",\"workspace_roots\":[\"$VAULT_N\"],\"tool_input\":{\"file_path\":\"raw/x.md\"}}"
eq "exit 0 (cursor)" "0" "$CODE"
PYTHONUTF8=1 python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['permission']=='deny'" "$OUT" 2>/dev/null && ok "permission:deny JSON" || no "permission:deny JSON (got [$OUT])"
cleanup

echo "test: raw 형제 디렉토리(raw-backup/)는 오탐 없이 통과"
new_sandbox
run_hook codex "{\"tool_name\":\"Write\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"file_path\":\"raw-backup/x.md\"}}"
eq "exit 0 (오탐 없음)" "0" "$CODE"
cleanup

# ⚠️ 알려진 한계 (§5-2, 의도적 비목표): COMMAND 문자열 **안의** 상대경로는 탐지하지 않는다.
#    TARGET은 BASE 기준으로 절대화하지만 셸 문법 전면 해석은 비목표이므로
#    `printf 'x' > raw/a.md` 는 통과한다. 이 테스트는 그 한계를 고정해 둔다 —
#    통과가 아니라 차단으로 바뀌길 원하면 먼저 spec §5-2를 개정해야 한다.
echo "test: [알려진 한계] shell COMMAND 내 상대경로는 미탐지 → 통과 (exit 0)"
new_sandbox
run_hook codex "{\"tool_name\":\"shell\",\"cwd\":\"$VAULT_N\",\"tool_input\":{\"command\":\"printf 'x' > raw/a.md\"}}"
eq "exit 0 (§5-2 비목표)" "0" "$CODE"
cleanup

# ── 비UTF-8 locale (§3-9) ─────────────────────────────────────────────────
# 차단 메시지 MSG는 한국어다. Cursor 분기는 그 메시지를 python3로 JSON 직렬화해 **stdout에**
# 내보내므로, locale이 비UTF-8이면 출력이 UnicodeEncodeError로 죽고 **deny가 조용히 사라진다**
# (2026-08-04 Windows CI 실측: cp1252에서 permission:deny JSON이 빈 출력).
echo "test: ASCII locale에서도 Cursor deny JSON이 나온다 (한국어 메시지)"
new_sandbox
OUT="$(cd "$VAULT" && printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT_N/raw/x.md\"}}" \
  | HOME="$SANDBOX/home" LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 bash "$HOOK" cursor 2>"$SANDBOX/err")"
CODE=$?
eq "exit 0 (cursor)" "0" "$CODE"
PYTHONUTF8=1 python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['permission']=='deny'; assert '읽기 전용' in d['user_message']" "$OUT" 2>/dev/null \
  && ok "deny JSON + 한국어 메시지 온전" || no "deny JSON 손실 (got [$OUT])"
cleanup

echo "test: ASCII locale + 한글 경로 raw/ 쓰기도 차단 (claude)"
new_sandbox
OUT="$(cd "$VAULT" && printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT_N/raw/한글문서.md\"}}" \
  | HOME="$SANDBOX/home" LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 bash "$HOOK" claude 2>"$SANDBOX/err")"
CODE=$?; ERR="$(cat "$SANDBOX/err")"
eq "exit 2 (한글 경로도 판정)" "2" "$CODE"
has "stderr 안내" "raw/" "$ERR"
cleanup

# PATH 단독 좁히기는 **MSYS/Git Bash(Windows)에서 성립하지 않는다** — MSYS의 `ln -s`는 기본
# 설정에서 복사본을 만들고, 복사된 bash·sed 등은 msys-2.0.dll 의존이 끊겨 실행이 실패하거나
# **응답 없이 대기**한다(2026-08-04 Windows CI 실측: 스위트가 매달렸고 개별 timeout으로도
# 끊기지 않았다). 그 플랫폼에서는 은닉 기법 자체가 검증 대상이 아니므로 스킵하되
# **시끄럽게 알린다** — 조용한 스킵은 "커버했다"로 오독된다.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) SKIP_NOPY=1 ;;
  *)                    SKIP_NOPY=0 ;;
esac

if [ "$SKIP_NOPY" = 1 ]; then
  echo "test: (SKIP) python3 fail-open 케이스 — MSYS/Windows에서 PATH 단독 좁히기가 성립하지 않는다"
  echo "  SKIP: 은닉 대상 도구가 msys-2.0.dll 의존으로 실행되지 않아 스위트가 매달린다 (2026-08-04 실측)"
else
# ⚠️ 의도된 fail-open (§5-2): python3가 없으면 resolver가 E_NO_RUNTIME(exit 7)로 실패하고
#    이 훅은 **통과시킨다**. 차단으로 돌리면 raw/만 골라 막을 수 없고(경로 판정 블록 자체가
#    python3다) 볼트 안 전체가 막힌다 — 훅이 글로벌이라 무관 프로젝트까지 함께 막힌다.
#    고지는 hooks/session-start가 세션당 1회 담당한다. 이 테스트는 그 결정을 고정해 둔다 —
#    차단으로 바꾸려면 먼저 spec §5-2를 개정해야 한다.
echo "test: [의도된 fail-open] python3 없음 + 볼트 안 raw/ Write → 통과 (exit 0)"
new_sandbox
NOPY="$SANDBOX/nopy"; mkdir -p "$NOPY"
for c in bash dirname head sed cat env; do ln -sf "$(command -v "$c")" "$NOPY/$c"; done
OUT="$(cd "$VAULT" && printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$VAULT_N/raw/x.md\"}}" \
  | HOME="$SANDBOX/home" PATH="$NOPY" "$BASH" "$HOOK" claude 2>"$SANDBOX/err")"; CODE=$?
ERR="$(cat "$SANDBOX/err")"
eq "exit 0 (§5-2 fail-open)" "0" "$CODE"
# resolver가 실제로 E_NO_RUNTIME 경로를 탔는지 — 다른 이유로 통과한 게 아님을 확인
(cd "$VAULT" && HOME="$SANDBOX/home" PATH="$NOPY" "$BASH" "$SANDBOX/home/.llm-wiki/scripts/resolve-vault.sh" >/dev/null 2>&1)
eq "resolver는 exit 7(E_NO_RUNTIME)" "7" "$?"
cleanup

fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
