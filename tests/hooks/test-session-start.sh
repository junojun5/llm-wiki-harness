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

# ── 런처의 줄바꿈 계약 (2026-08-04 Windows CI 실측) ────────────────────────
# cmd.exe는 **LF-only 배치의 줄 경계를 잡지 못해** 파일을 중간부터 오해석한다 — 주석
# 조각과 코드 조각이 각각 별개 명령으로 실행되며 런처가 죽었다. 그래서 CRLF로 배포하는데,
# 이 파일은 bash에서도 실행되는 폴리글랏이라 CR이 그냥 들어가면 Unix 분기가 `shift\r`
# 같은 토큰을 실행하려다 죽는다. 해법은 실행 줄 끝의 ' #'으로 CR을 주석에 흡수시키는 것 —
# **CRLF와 ' #'은 한 쌍이고, 둘 중 하나만 있으면 한쪽 플랫폼이 조용히 깨진다.**
# 위 두 케이스가 "CR이 있어도 Unix 분기가 산다"를 이미 실증하므로, 여기서는 계약 자체를
# 고정한다(누가 LF로 되돌리거나 ' #' 없는 실행 줄을 추가하면 잡힌다).
echo "test: run-hook.cmd 줄바꿈 계약 — CRLF + 실행 줄의 CR 흡수 주석"
CRS="$(tr -cd '\r' < "$LAUNCHER" | wc -c | tr -d ' ')"
[ "$CRS" -gt 0 ] \
  && ok "CRLF로 배포된다 (CR ${CRS}개)" \
  || no "LF-only — cmd.exe가 줄 경계를 잃어 Windows에서 런처가 죽는다"
BAD=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in
    ':; #'*|':;') continue ;;                      # 주석 줄은 CR이 이미 주석 안이다
    ':; '*) case "$line" in *' #') ;; *) BAD=$((BAD+1)); echo "    CR 흡수 없음: $line" ;; esac ;;
  esac
done < "$LAUNCHER"
[ "$BAD" -eq 0 ] \
  && ok "Unix 분기 실행 줄이 전부 ' #'으로 CR을 흡수한다" \
  || no "' #' 없는 실행 줄 ${BAD}개 — CRLF에서 bash 분기가 죽는다"

# ── 부트스트랩 ①: 버전 업데이트 시 stale symlink 재지정 ────────────────────
# 마켓플레이스 캐시는 버전별 디렉토리라, 존재 여부만 보면 symlink가 구버전에 영구히
# 고정된다. 2026-08-01 실측: 캐시는 0.2.0인데 런타임 홈은 0.1.0이라 고친 결함이 그대로
# 재현됐다. 형제 버전은 재지정하고 사용자 클론(install.sh)은 보존해야 한다.

# 가짜 플러그인 캐시 레이아웃 — ROOT가 */plugins/cache/* 안이어야 형제 판정이 켜진다
# 비교를 물리 경로로 한다 — macOS의 mktemp는 /var(→ /private/var) 심볼릭 아래에 만든다
mkdir -p "$SB/plugins/cache/llm-wiki-harness/llm-wiki-harness"
MP="$(cd "$SB/plugins/cache/llm-wiki-harness/llm-wiki-harness" && pwd -P)"
for v in 0.1.0 0.2.0; do
  mkdir -p "$MP/$v/hooks" "$MP/$v/scripts" "$MP/$v/skills/using-llm-wiki"
  cp "$HOOK" "$MP/$v/hooks/session-start"
  cp "$REPO_ROOT/skills/using-llm-wiki/SKILL.md" "$MP/$v/skills/using-llm-wiki/SKILL.md"
  for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
    printf '#!/usr/bin/env bash\necho %s\n' "$v" > "$MP/$v/scripts/$s"
  done
done

echo "test: 형제 버전 stale symlink → 새 버전으로 재지정"
H2="$SB/home2/.llm-wiki/scripts"; mkdir -p "$H2"
for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
  ln -sfn "$MP/0.1.0/scripts/$s" "$H2/$s"
done
(cd "$SB" && HOME="$SB/home2" bash "$MP/0.2.0/hooks/session-start" claude </dev/null >/dev/null 2>&1)
[ "$(readlink "$H2/resolve-vault.sh")" = "$MP/0.2.0/scripts/resolve-vault.sh" ] \
  && ok "형제 버전 재지정 (0.1.0 → 0.2.0)" || no "재지정 안 됨: $(readlink "$H2/resolve-vault.sh")"
[ "$(bash "$H2/build-link-graph.sh")" = "0.2.0" ] \
  && ok "재지정 후 새 버전이 실행된다" || no "여전히 옛 스크립트 실행"

echo "test: 사용자 클론을 가리키는 symlink는 보존 (install.sh 비파괴 정책)"
H3="$SB/home3/.llm-wiki/scripts"; mkdir -p "$H3"
CLONE="$SB/my-clone/scripts"; mkdir -p "$CLONE"
for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
  printf '#!/usr/bin/env bash\necho clone\n' > "$CLONE/$s"
  ln -sfn "$CLONE/$s" "$H3/$s"
done
(cd "$SB" && HOME="$SB/home3" bash "$MP/0.2.0/hooks/session-start" claude </dev/null >/dev/null 2>&1)
[ "$(readlink "$H3/resolve-vault.sh")" = "$CLONE/resolve-vault.sh" ] \
  && ok "사용자 클론 링크 보존" || no "클론 링크가 덮어써짐: $(readlink "$H3/resolve-vault.sh")"

echo "test: 깨진 symlink → 복구"
H4="$SB/home4/.llm-wiki/scripts"; mkdir -p "$H4"
ln -sfn "$SB/gone/scripts/resolve-vault.sh" "$H4/resolve-vault.sh"
(cd "$SB" && HOME="$SB/home4" bash "$MP/0.2.0/hooks/session-start" claude </dev/null >/dev/null 2>&1)
[ "$(readlink "$H4/resolve-vault.sh")" = "$MP/0.2.0/scripts/resolve-vault.sh" ] \
  && ok "깨진 링크 복구" || no "깨진 링크 방치: $(readlink "$H4/resolve-vault.sh")"

echo "test: symlink가 아닌 실제 파일은 손대지 않는다"
H5="$SB/home5/.llm-wiki/scripts"; mkdir -p "$H5"
printf '#!/usr/bin/env bash\necho mine\n' > "$H5/resolve-vault.sh"
(cd "$SB" && HOME="$SB/home5" bash "$MP/0.2.0/hooks/session-start" claude </dev/null >/dev/null 2>&1)
[ ! -L "$H5/resolve-vault.sh" ] && [ "$(bash "$H5/resolve-vault.sh")" = "mine" ] \
  && ok "실제 파일 보존" || no "실제 파일이 symlink로 교체됨"

echo "test: 이미 이 배포본을 가리키면 멱등 (재지정 없음)"
H6="$SB/home6/.llm-wiki/scripts"; mkdir -p "$H6"
ln -sfn "$MP/0.2.0/scripts/resolve-vault.sh" "$H6/resolve-vault.sh"
BEFORE="$(readlink "$H6/resolve-vault.sh")"
(cd "$SB" && HOME="$SB/home6" bash "$MP/0.2.0/hooks/session-start" claude </dev/null >/dev/null 2>&1)
[ "$(readlink "$H6/resolve-vault.sh")" = "$BEFORE" ] && ok "멱등" || no "멱등 위반"

# ── python3 부재 (§3-2 E_NO_RUNTIME · §5-1) ───────────────────────────────
# 부트스트랩과 경고 경로는 **python3에 의존할 수 없다** — 런타임 부재를 알리는 경로가
# 그 런타임을 요구하면 조용히 죽는다(2026-08-01 실측: realpath가 python3라 ROOT가
# CWD의 부모로 잡히고 부트스트랩이 no-op).
# 은닉은 PATH를 화이트리스트 디렉토리 **단독**으로 좁혀 만든다 — 뒤에 /usr/bin을 붙이면
# 거기 있는 python3가 보이고, shim 파일을 두면 `command -v python3`가 성공해 부재가
# 재현되지 않는다. 목록에서 빠진 명령이 있으면 시끄럽게 실패한다(안전한 방향).
NOPY="$SB/nopy"; mkdir -p "$NOPY"
for c in bash dirname head sed readlink ln mkdir cat env; do
  ln -sf "$(command -v "$c")" "$NOPY/$c"
done

echo "test: python3 없음 + 볼트 안 — 경고를 주입과 stderr 양쪽에 낸다"
H7="$SB/home7"; mkdir -p "$H7"
OUT="$(cd "$VAULT" && HOME="$H7" PATH="$NOPY" "$BASH" "$HOOK" claude </dev/null 2>"$SB/err7")"; CODE=$?
ERR7="$(cat "$SB/err7")"
[ "$CODE" = 0 ] && ok "exit 0 (세션을 막지 않는다)" || no "exit 0 (got $CODE)"
printf '%s' "$OUT" | python3 -c "import json,sys;json.load(sys.stdin)" 2>/dev/null \
  && ok "경고도 유효 JSON" || no "invalid JSON: $OUT"
jpath "경고가 additionalContext로 주입" "d['hookSpecificOutput']['additionalContext']" "python3" "$OUT"
jpath "가드 훅 비활성 고지" "d['hookSpecificOutput']['additionalContext']" "가드 훅" "$OUT"
jpath "--repair로는 안 된다는 고지" "d['hookSpecificOutput']['additionalContext']" "--repair" "$OUT"
jpath "hookEventName=SessionStart 유지" "d['hookSpecificOutput']['hookEventName']" "SessionStart" "$OUT"
printf '%s' "$ERR7" | grep -qF "E_NO_RUNTIME" && ok "stderr에 E_NO_RUNTIME" || no "stderr에 경고 없음: [$ERR7]"

echo "test: python3 없음 + Cursor 페이로드 — 래퍼 없는 additional_context"
H8="$SB/home8"; mkdir -p "$H8"
OUT="$(cd "$VAULT" && HOME="$H8" PATH="$NOPY" "$BASH" "$HOOK" claude \
  < "$REPO_ROOT/tests/fixtures/cursor-hooks/sessionstart.json" 2>/dev/null)"
jpath "cursor 포맷 경고" "d['additional_context']" "python3" "$OUT"
printf '%s' "$OUT" | python3 -c "import json,sys;sys.exit(0 if 'hookSpecificOutput' not in json.load(sys.stdin) else 1)" 2>/dev/null \
  && ok "cursor 경고에 hookSpecificOutput 래퍼 없음" || no "cursor 경고에 래퍼가 남아 있음"

echo "test: python3 없음 + 볼트 없음 — 무성 (무관 프로젝트에 스팸 없음)"
H9="$SB/home9"; mkdir -p "$H9"
OUT="$(cd "$SB" && HOME="$H9" PATH="$NOPY" "$BASH" "$HOOK" claude </dev/null 2>"$SB/err9")"; CODE=$?
ERR9="$(cat "$SB/err9")"
[ "$CODE" = 0 ] && ok "exit 0" || no "exit 0 (got $CODE)"
[ -z "$OUT" ] && ok "stdout 무성" || no "볼트 없는데 주입: $OUT"
[ -z "$ERR9" ] && ok "stderr 무성" || no "볼트 없는데 경고: $ERR9"

echo "test: python3 없음 + symlink 경유 실행 — ROOT가 옳게 잡혀 부트스트랩 동작"
H10="$SB/home10"; mkdir -p "$H10"
LINKED="$SB/linked-session-start"; ln -sfn "$MP/0.2.0/hooks/session-start" "$LINKED"
(cd "$SB" && HOME="$H10" PATH="$NOPY" "$BASH" "$LINKED" claude </dev/null >/dev/null 2>&1)
BOOTED=0
for s in resolve-vault.sh validate-frontmatter.sh build-link-graph.sh; do
  [ -L "$H10/.llm-wiki/scripts/$s" ] && BOOTED=$((BOOTED+1))
done
[ "$BOOTED" = 3 ] && ok "symlink 경유 + python3 없음에도 부트스트랩 3개" || no "부트스트랩 $BOOTED/3 (ROOT 오판)"
[ "$(readlink "$H10/.llm-wiki/scripts/resolve-vault.sh")" = "$MP/0.2.0/scripts/resolve-vault.sh" ] \
  && ok "링크 대상이 배포본 scripts/" || no "엉뚱한 대상: $(readlink "$H10/.llm-wiki/scripts/resolve-vault.sh")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
