#!/usr/bin/env bash
# test-merge-json.sh — install.sh의 공유 등록 파일 **병합** 계약 (배포 설계 §7-1 공존 정책).
#
# ── 왜 있는가 ──────────────────────────────────────────────────────────────────
# install.sh는 공유 등록 파일(~/.claude/settings.json · ~/.codex/hooks.json ·
# ~/.cursor/hooks.json · {vault}/.codex/hooks.json · {vault}/.cursor/hooks.json ·
# {vault}/.cursor/sandbox.json)에 대해 "원본 보존 + `.llm-wiki` 사본 + 수동 머지 안내"만 했다.
# 덮어쓰지 않으니 안전하지만 **통합이 사용자 손에 남아**, 다른 레포도 같은 정책을 쓰면
# 사본만 쌓이고 훅은 아무것도 등록되지 않은 채 설치가 "성공"한다 — §5-5 가드 생존 문제의
# 또 다른 입구다.
#
# 해법은 **마커 기반 멱등 병합**이다. 우리 항목은 command가 `run-hook.cmd`를 경유하고
# 우리 훅 스크립트명을 인자로 실어 식별 가능하다: 읽기 → 우리 마커 항목만 제거 →
# 현재 항목 삽입 → 쓰기.
#
# ── 왜 멱등성을 별도로 고정하는가 ──────────────────────────────────────────────
# 이 부류의 대표 실패가 `conda init`의 멱등성 버그(conda#8703)다 — 재실행마다 자기 블록을
# 다시 삽입해 설정이 무한히 자란다. "제거 후 삽입"은 **제거가 삽입한 것을 정확히 되찾을 때만**
# 멱등이다. 설치 경로가 바뀌면(레포 이동·플러그인 캐시 갱신) 항목의 절대경로가 달라지므로
# 경로로 식별하는 마커는 자기 항목을 못 찾아 중복을 쌓는다. 그래서 마커는 경로에 의존하지 않고,
# 아래 [3](재실행 멱등)·[4](stale 교체)가 그 두 함정을 각각 고정한다.
#
# ── 무엇을 절대 하지 않는가 ────────────────────────────────────────────────────
# 남의 항목은 건드리지 않는다. 파싱 불가한 대상 파일은 손대지 않고 기존 사본 경로로 강등한다
# ([5]) — 병합이 사용자 설정을 파괴하는 것은 수동 머지보다 나쁘다.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ✓ $1"; }
no(){ FAIL=$((FAIL+1)); echo "  ✗ $1"; }

SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
# 렌더된 절대경로를 grep으로 확인할 때는 native 형태여야 한다 (MSYS 주의 — tests/lib/paths.sh)
. "$REPO/tests/lib/paths.sh"

# count_ours <file> <event> — 해당 이벤트에서 우리 마커(run-hook.cmd)를 가진 항목 수
count_ours(){
  PYTHONUTF8=1 python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("ERR"); sys.exit(0)
def cmds(e):
    out = []
    if isinstance(e, dict):
        if isinstance(e.get("command"), str): out.append(e["command"])
        for h in (e.get("hooks") or []):
            if isinstance(h, dict) and isinstance(h.get("command"), str): out.append(h["command"])
    return out
ev = (d.get("hooks") or {}).get(sys.argv[2]) or []
print(sum(1 for e in ev if any("run-hook.cmd" in c for c in cmds(e))))
' "$1" "$2"
}
# count_all <file> <event> — 해당 이벤트의 전체 항목 수 (남의 항목 보존 확인용)
count_all(){
  PYTHONUTF8=1 python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("ERR"); sys.exit(0)
print(len((d.get("hooks") or {}).get(sys.argv[2]) or []))
' "$1" "$2"
}

# ─────────────────────────────────────────────────────────────────────────────
echo "[1] 첫 설치 — 대상 파일이 없으면 생성한다 (기존 동작 유지)"
H1="$SB/fresh/home"; V1="$SB/fresh/vault"
mkdir -p "$H1/.claude" "$H1/.cursor" "$H1/.codex" "$V1"
HOME="$H1" bash "$REPO/install.sh" --fallback --vault "$V1" >"$SB/fresh.out" 2>&1
[ -f "$H1/.claude/settings.json" ] && ok "~/.claude/settings.json 생성" || no "~/.claude/settings.json 미생성 — Claude 훅이 등록되지 않는다"
[ "$(count_ours "$H1/.claude/settings.json" SessionStart)" = "1" ] && ok "settings.json SessionStart 우리 항목 1건" || no "settings.json SessionStart 항목 수 이상: $(count_ours "$H1/.claude/settings.json" SessionStart)"
[ "$(count_ours "$H1/.claude/settings.json" PreToolUse)" = "1" ]  && ok "settings.json PreToolUse 우리 항목 1건"  || no "settings.json PreToolUse 항목 수 이상"
[ "$(count_ours "$H1/.claude/settings.json" PostToolUse)" = "1" ] && ok "settings.json PostToolUse 우리 항목 1건" || no "settings.json PostToolUse 항목 수 이상"
[ "$(count_ours "$H1/.codex/hooks.json" SessionStart)" = "1" ]    && ok "~/.codex/hooks.json 우리 항목 1건"        || no "~/.codex/hooks.json 항목 수 이상"
[ "$(count_ours "$H1/.cursor/hooks.json" sessionStart)" = "1" ]   && ok "~/.cursor/hooks.json 우리 항목 1건"       || no "~/.cursor/hooks.json 항목 수 이상"
# 사본은 병합이 성공하는 경로에서 나오지 않아야 한다
[ "$(find "$SB/fresh" -name '*.llm-wiki.*' | wc -l | tr -d ' ')" = "0" ] && ok "첫 설치에 사본 0건" || no "첫 설치가 사본을 만들었다"

# ─────────────────────────────────────────────────────────────────────────────
echo "[2] 남의 항목 보존 — 기존 파일에 우리 항목만 더한다"
H2="$SB/coexist/home"; V2="$SB/coexist/vault"
mkdir -p "$H2/.claude" "$H2/.cursor" "$H2/.codex" "$V2/.cursor" "$V2/.codex"
# 다른 레포의 훅 + 훅과 무관한 사용자 설정(permissions)이 함께 든 settings.json
cat > "$H2/.claude/settings.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(npm test)"] },
  "model": "claude-opus-5",
  "hooks": {
    "SessionStart": [
      { "matcher": "startup", "hooks": [ { "type": "command", "command": "/other/repo/hooks/greet.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "/other/repo/hooks/lint.sh" } ] }
    ]
  }
}
JSON
cat > "$H2/.codex/hooks.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "matcher": "Write", "hooks": [ { "type": "command", "command": "/other/repo/codex-guard.sh" } ] } ] } }
JSON
cat > "$H2/.cursor/hooks.json" <<'JSON'
{ "version": 1, "hooks": { "preToolUse": [ { "command": "/other/repo/cursor-guard.sh", "matcher": "Write" } ] } }
JSON
cat > "$V2/.cursor/sandbox.json" <<'JSON'
{ "additionalReadwritePaths": ["~/my-own-path"] }
JSON
HOME="$H2" bash "$REPO/install.sh" --fallback --vault "$V2" >"$SB/coexist.out" 2>&1
# 훅과 무관한 키가 살아 있는가
grep -q 'npm test'      "$H2/.claude/settings.json" && ok "settings.json permissions 보존"        || no "settings.json permissions 소실"
grep -q 'claude-opus-5' "$H2/.claude/settings.json" && ok "settings.json model 보존"              || no "settings.json model 소실"
# 남의 훅이 살아 있는가
grep -q 'greet.sh'         "$H2/.claude/settings.json" && ok "settings.json 남의 SessionStart 보존" || no "settings.json 남의 SessionStart 삭제됨"
grep -q 'lint.sh'          "$H2/.claude/settings.json" && ok "settings.json 남의 PreToolUse 보존"   || no "settings.json 남의 PreToolUse 삭제됨"
grep -q 'codex-guard.sh'   "$H2/.codex/hooks.json"     && ok "~/.codex 남의 항목 보존"              || no "~/.codex 남의 항목 삭제됨"
grep -q 'cursor-guard.sh'  "$H2/.cursor/hooks.json"    && ok "~/.cursor 남의 항목 보존"             || no "~/.cursor 남의 항목 삭제됨"
grep -q 'my-own-path'      "$V2/.cursor/sandbox.json"  && ok "sandbox 사용자 경로 보존"             || no "sandbox 사용자 경로 삭제됨"
# 우리 항목이 더해졌는가 — 남의 것 1 + 우리 것 1 = 2
[ "$(count_all "$H2/.claude/settings.json" SessionStart)" = "2" ] && ok "settings.json SessionStart 남의것+우리것=2" || no "settings.json SessionStart 개수 이상: $(count_all "$H2/.claude/settings.json" SessionStart)"
[ "$(count_ours "$H2/.claude/settings.json" PostToolUse)" = "1" ] && ok "settings.json 없던 이벤트(PostToolUse) 신설" || no "settings.json PostToolUse 미신설"
[ "$(count_ours "$H2/.cursor/hooks.json" preToolUse)" = "1" ]     && ok "~/.cursor preToolUse 우리 항목 삽입"        || no "~/.cursor preToolUse 우리 항목 없음"
[ "$(count_all "$H2/.cursor/hooks.json" preToolUse)" = "2" ]      && ok "~/.cursor preToolUse 남의것+우리것=2"       || no "~/.cursor preToolUse 개수 이상"
grep -q '~/.llm-wiki' "$V2/.cursor/sandbox.json" && ok "sandbox 우리 경로 추가"  || no "sandbox 우리 경로 없음"
# 병합에 성공했으면 사본을 남기지 않고, '수동 머지 필요'로 사용자를 부르지도 않는다
[ "$(find "$SB/coexist" -name '*.llm-wiki.*' | wc -l | tr -d ' ')" = "0" ] && ok "병합 성공 → 사본 0건" || no "병합했는데 사본이 남았다"
grep -q '수동 머지 필요' "$SB/coexist.out" && no "병합했는데 수동 머지를 요구한다" || ok "수동 머지 안내 없음"

# ─────────────────────────────────────────────────────────────────────────────
echo "[3] 재실행 멱등 — 항목이 누적되지 않는다 (conda#8703 부류)"
# [2]의 결과 위에 2회 더 돌린다. 2회차와 3회차 산출물이 **바이트 단위로 동일**해야 한다.
HOME="$H2" bash "$REPO/install.sh" --fallback --vault "$V2" >/dev/null 2>&1
for f in "$H2/.claude/settings.json" "$H2/.codex/hooks.json" "$H2/.cursor/hooks.json" "$V2/.cursor/sandbox.json"; do
  cp "$f" "$SB/snap.$(basename "$(dirname "$f")").$(basename "$f")"
done
HOME="$H2" bash "$REPO/install.sh" --fallback --vault "$V2" >"$SB/rerun.out" 2>&1
for f in "$H2/.claude/settings.json" "$H2/.codex/hooks.json" "$H2/.cursor/hooks.json" "$V2/.cursor/sandbox.json"; do
  snap="$SB/snap.$(basename "$(dirname "$f")").$(basename "$f")"
  cmp -s "$snap" "$f" && ok "재실행 불변: ${f#"$SB/coexist/"}" || no "재실행이 파일을 변경했다: ${f#"$SB/coexist/"}"
done
[ "$(count_all "$H2/.claude/settings.json" SessionStart)" = "2" ] && ok "3회 실행 후에도 SessionStart 2건(누적 없음)" || no "재실행이 항목을 누적했다: $(count_all "$H2/.claude/settings.json" SessionStart)"
[ "$(count_ours "$H2/.cursor/hooks.json" sessionStart)" = "1" ]  && ok "3회 실행 후에도 cursor sessionStart 1건"    || no "cursor 항목 누적: $(count_ours "$H2/.cursor/hooks.json" sessionStart)"
[ "$(grep -c '~/.llm-wiki' "$V2/.cursor/sandbox.json")" = "1" ]  && ok "sandbox 경로 중복 삽입 없음"                || no "sandbox 경로가 중복됐다"
grep -q '이미 최신' "$SB/rerun.out" && ok "재실행은 '이미 최신'으로 보고" || no "재실행 '이미 최신' 보고 없음"

# ─────────────────────────────────────────────────────────────────────────────
echo "[4] 우리 stale 항목 교체 — 설치 경로가 바뀌어도 중복이 남지 않는다"
# 마커가 경로에 의존하면 여기서 실패한다: 예전 플러그인 캐시 경로로 등록된 우리 항목을
# 못 알아보고 새 항목을 덧붙여 **같은 훅이 2회 발화**한다.
H4="$SB/stale/home"; V4="$SB/stale/vault"
mkdir -p "$H4/.claude" "$H4/.cursor" "$H4/.codex" "$V4"
cat > "$H4/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact", "hooks": [ { "type": "command", "command": "/old/plugin/cache/v0.2.1/hooks/run-hook.cmd session-start claude" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "/old/plugin/cache/v0.2.1/hooks/run-hook.cmd wiki-protect-raw.sh claude" } ] },
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "/other/repo/hooks/lint.sh" } ] }
    ]
  }
}
JSON
cat > "$H4/.cursor/hooks.json" <<'JSON'
{ "version": 1, "hooks": { "sessionStart": [ { "command": "/old/cache/hooks/run-hook.cmd session-start cursor" } ] } }
JSON
HOME="$H4" bash "$REPO/install.sh" --fallback --vault "$V4" >"$SB/stale.out" 2>&1
grep -q '/old/plugin/cache' "$H4/.claude/settings.json" && no "stale 우리 항목이 남았다 — 같은 훅이 2회 발화한다" || ok "stale 우리 항목 제거"
grep -q '/old/cache'        "$H4/.cursor/hooks.json"    && no "cursor stale 우리 항목이 남았다"                   || ok "cursor stale 우리 항목 제거"
[ "$(count_ours "$H4/.claude/settings.json" SessionStart)" = "1" ] && ok "SessionStart 우리 항목 정확히 1건" || no "SessionStart 우리 항목 $(count_ours "$H4/.claude/settings.json" SessionStart)건"
[ "$(count_ours "$H4/.claude/settings.json" PreToolUse)" = "1" ]   && ok "PreToolUse 우리 항목 정확히 1건"   || no "PreToolUse 우리 항목 $(count_ours "$H4/.claude/settings.json" PreToolUse)건"
grep -q 'lint.sh' "$H4/.claude/settings.json" && ok "stale 교체 중에도 남의 항목 보존" || no "stale 교체가 남의 항목을 지웠다"
[ "$(count_ours "$H4/.cursor/hooks.json" sessionStart)" = "1" ] && ok "cursor sessionStart 우리 항목 1건" || no "cursor sessionStart 우리 항목 수 이상"

# ─────────────────────────────────────────────────────────────────────────────
echo "[5] 손상된 대상 파일 — 손대지 않고 사본으로 강등한다"
H5="$SB/broken/home"; V5="$SB/broken/vault"
mkdir -p "$H5/.claude" "$H5/.cursor" "$H5/.codex" "$V5"
printf '{ "hooks": { "SessionStart": [ }}} 이건 JSON이 아니다\n' > "$H5/.claude/settings.json"
BROKEN_BEFORE="$(cat "$H5/.claude/settings.json")"
HOME="$H5" bash "$REPO/install.sh" --fallback --vault "$V5" >"$SB/broken.out" 2>&1
[ "$(cat "$H5/.claude/settings.json")" = "$BROKEN_BEFORE" ] && ok "손상 파일 원본 그대로 보존" || no "손상 파일을 변경했다"
[ -f "$H5/.claude/settings.llm-wiki.json" ] && ok "사본으로 강등: settings.llm-wiki.json" || no "강등 사본 없음 — 사용자가 복구 경로를 잃는다"
grep -q '수동 머지 필요' "$SB/broken.out" && ok "요약에 수동 머지 재고지" || no "손상 시 수동 머지 미고지"
# 손상은 한 파일에 국한된다 — 나머지 대상은 정상 병합되어야 한다
[ "$(count_ours "$H5/.cursor/hooks.json" sessionStart)" = "1" ] && ok "한 파일 손상이 다른 대상을 막지 않음" || no "손상 파일이 설치 전체를 막았다"

# ─────────────────────────────────────────────────────────────────────────────
echo "[6] ASCII locale — 한국어가 든 사용자 설정을 손상 없이 병합 (§3-9)"
# 병합은 render와 달리 **사용자 파일을 읽어 되쓴다** — 인코딩 누락의 대가가 render보다 크다.
# render 실패는 우리 파일이 0바이트로 남는 것이었지만, 병합 실패는 사용자 설정을 깨뜨린다.
H6="$SB/ascii/home"; V6="$SB/ascii/vault"
mkdir -p "$H6/.claude" "$H6/.cursor" "$H6/.codex" "$V6"
cat > "$H6/.claude/settings.json" <<'JSON'
{
  "_note": "사용자가 직접 쓴 한국어 주석 — 병합이 이걸 깨뜨리면 안 된다",
  "hooks": { "PreToolUse": [ { "matcher": "Write", "hooks": [ { "type": "command", "command": "/other/repo/린트.sh" } ] } ] }
}
JSON
HOME="$H6" LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
  bash "$REPO/install.sh" --fallback --vault "$V6" >"$SB/ascii.out" 2>&1
grep -q '사용자가 직접 쓴 한국어 주석' "$H6/.claude/settings.json" && ok "ASCII locale에서 한국어 키 왕복 보존" || no "ASCII locale 병합이 한국어를 손상시켰다"
grep -q '린트.sh' "$H6/.claude/settings.json" && ok "ASCII locale에서 한국어 경로 항목 보존" || no "한국어 경로 항목이 손상됐다"
# \uXXXX 이스케이프로 되쓰는 것도 손상이다 — 사용자가 읽을 수 없고 diff가 통째로 뒤집힌다
grep -q '\\uc0ac' "$H6/.claude/settings.json" && no "한국어가 \\uXXXX 이스케이프로 되쓰였다" || ok "ensure_ascii=False로 되쓰기"
[ "$(count_ours "$H6/.claude/settings.json" SessionStart)" = "1" ] && ok "ASCII locale에서도 우리 항목 삽입" || no "ASCII locale에서 병합 실패"
[ "$(count_all "$H6/.claude/settings.json" PreToolUse)" = "2" ]    && ok "ASCII locale에서 남의 항목 보존"   || no "ASCII locale 병합이 남의 항목을 잃었다"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
